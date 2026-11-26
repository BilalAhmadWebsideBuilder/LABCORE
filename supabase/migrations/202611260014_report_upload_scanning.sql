create table if not exists public.report_result_files (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  report_result_id uuid not null,
  file_name text not null check (length(file_name) between 1 and 180),
  file_path text not null unique,
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  file_size_bytes bigint not null check (file_size_bytes between 1 and 26214400),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  scan_status text not null check (scan_status = 'clean'),
  scanner_name text not null check (length(scanner_name) between 1 and 80),
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (report_result_id, lab_id)
    references public.report_results(id, lab_id) on delete cascade
);

create index if not exists report_result_files_lab_result_idx
  on public.report_result_files(lab_id, report_result_id, created_at desc);
alter table public.report_result_files enable row level security;
grant select on public.report_result_files to authenticated;
revoke insert, update, delete on public.report_result_files from public, anon, authenticated;

drop policy if exists report_result_files_read_assigned on public.report_result_files;
create policy report_result_files_read_assigned on public.report_result_files
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'reports.read')
    and exists (
      select 1
      from public.report_results result
      where result.id = report_result_files.report_result_id
        and result.lab_id = report_result_files.lab_id
        and public.has_order_item_access(report_result_files.lab_id, result.order_item_id)
    )
  );

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-attachments',
  'report-attachments',
  false,
  26214400,
  array['application/pdf','image/jpeg','image/png']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists report_attachment_read_assigned on storage.objects;
create policy report_attachment_read_assigned on storage.objects
  for select to authenticated using (
    bucket_id = 'report-attachments'
    and exists (
      select 1
      from public.report_result_files file
      where file.file_path = name
        and file.lab_id = public.storage_lab_id(name)
    )
  );

create or replace function public.register_scanned_report_attachment(
  p_lab_id uuid,
  p_report_result_id uuid,
  p_file_name text,
  p_file_path text,
  p_mime_type text,
  p_file_size_bytes bigint,
  p_sha256 text,
  p_scanner_name text,
  p_uploaded_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_file_id uuid;
  report_row public.report_results%rowtype;
  extension text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Trusted scanner service required';
  end if;
  if p_file_name is null or length(p_file_name) not between 1 and 180
    or p_mime_type not in ('application/pdf','image/jpeg','image/png')
    or p_file_size_bytes not between 1 and 26214400
    or p_sha256 !~ '^[0-9a-f]{64}$'
    or p_scanner_name is null or length(p_scanner_name) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'Scanned file metadata is invalid';
  end if;

  select result.* into report_row
  from public.report_results result
  where result.id = p_report_result_id and result.lab_id = p_lab_id
  for update;
  if not found or report_row.status = 'published' then
    raise exception using errcode = 'P0002', message = 'Active unpublished report result not found';
  end if;
  if not exists (
    select 1
    from public.memberships member
    where member.lab_id = p_lab_id
      and member.user_id = p_uploaded_by
      and member.active
      and exists (
        select 1 from public.page_grants page_grant
        where page_grant.lab_id = p_lab_id
          and page_grant.user_id = p_uploaded_by
          and page_grant.page_key = 'reports'
      )
      and coalesce((
        select role_permission.allowed
        from public.roles_permissions role_permission
        where role_permission.lab_id = p_lab_id
          and role_permission.role_key = member.role
          and role_permission.permission_key = 'reports.upload'
      ), exists (
        select 1 from public.role_default_permissions default_permission
        where default_permission.role_key = member.role
          and default_permission.permission_key = 'reports.upload'
      ))
  ) then
    raise exception using errcode = '42501', message = 'Uploader is not an active member of this laboratory';
  end if;

  extension := case p_mime_type
    when 'application/pdf' then 'pdf'
    when 'image/jpeg' then 'jpg'
    when 'image/png' then 'png'
  end;
  if p_file_path !~ (
    '^' || p_lab_id::text || '/' || report_row.patient_id::text || '/'
      || p_report_result_id::text || '/[0-9a-f-]{36}\.' || extension || '$'
  ) then
    raise exception using errcode = '22023', message = 'Scanned file path does not match the report';
  end if;

  insert into public.report_result_files(
    lab_id, report_result_id, file_name, file_path, mime_type,
    file_size_bytes, sha256, scan_status, scanner_name, uploaded_by
  )
  values (
    p_lab_id, p_report_result_id, p_file_name, p_file_path, p_mime_type,
    p_file_size_bytes, p_sha256, 'clean', p_scanner_name, p_uploaded_by
  )
  returning id into new_file_id;

  insert into public.audit_logs(
    lab_id, actor_id, action, entity_type, entity_id, after_redacted
  )
  values (
    p_lab_id,
    p_uploaded_by,
    'upload.report_result_file',
    'report_result_files',
    new_file_id::text,
    jsonb_build_object(
      'fields', jsonb_build_array('report_result_id','mime_type','file_size_bytes','sha256','scan_status','scanner_name')
    )
  );

  return new_file_id;
end;
$$;

create or replace function public.get_lab_report_attachments(
  p_lab_id uuid,
  p_limit integer default 200
)
returns table(
  file_id uuid,
  report_result_id uuid,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  scanner_name text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'reports.read') then
    raise exception using errcode = '42501', message = 'Report access permission required';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception using errcode = '22023', message = 'Attachment result limit must be between 1 and 500';
  end if;

  return query
    select file.id, file.report_result_id, file.file_name, file.mime_type,
      file.file_size_bytes, file.scanner_name, file.created_at
    from public.report_result_files file
    join public.report_results result
      on result.id = file.report_result_id and result.lab_id = file.lab_id
    where file.lab_id = p_lab_id
      and public.has_order_item_access(p_lab_id, result.order_item_id)
    order by file.created_at desc
    limit p_limit;
end;
$$;

create or replace function public.get_lab_report_attachment_path(p_file_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  file_path text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Sign-in required';
  end if;

  select file.file_path into file_path
  from public.report_result_files file
  join public.report_results result
    on result.id = file.report_result_id and result.lab_id = file.lab_id
  where file.id = p_file_id
    and public.has_lab_permission(file.lab_id, 'reports.read')
    and public.has_order_item_access(file.lab_id, result.order_item_id);

  if file_path is null then
    raise exception using errcode = 'P0002', message = 'Report attachment not found';
  end if;
  return file_path;
end;
$$;

revoke all on function public.register_scanned_report_attachment(uuid, uuid, text, text, text, bigint, text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.get_lab_report_attachments(uuid, integer) from public, anon;
revoke all on function public.get_lab_report_attachment_path(uuid) from public, anon;
grant execute on function public.register_scanned_report_attachment(uuid, uuid, text, text, text, bigint, text, text, uuid)
  to service_role;
grant execute on function public.get_lab_report_attachments(uuid, integer) to authenticated;
grant execute on function public.get_lab_report_attachment_path(uuid) to authenticated;
