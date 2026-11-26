create table if not exists public.platform_developers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.platform_developers enable row level security;
revoke all on table public.platform_developers from public, anon, authenticated;

create or replace function public.is_platform_developer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_developers pd
    where pd.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_platform_developer() from public, anon;
grant execute on function public.is_platform_developer() to authenticated;

create or replace function public.is_lab_member(target_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not public.is_platform_developer()
    and exists (
      select 1
      from public.memberships m
      where m.lab_id = target_lab
        and m.user_id = (select auth.uid())
        and m.active
    );
$$;

create or replace function public.is_patient_owner(target_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not public.is_platform_developer()
    and exists (
      select 1
      from public.patient_accounts pa
      where pa.patient_id = target_patient
        and pa.user_id = (select auth.uid())
        and pa.activated_at is not null
    );
$$;

create or replace function public.is_lab_auditor(target_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not public.is_platform_developer()
    and exists (
      select 1
      from public.memberships m
      where m.lab_id = target_lab
        and m.user_id = (select auth.uid())
        and m.active
        and m.role in ('lab_admin', 'platform_admin')
    );
$$;

create or replace function public.has_lab_permission(target_lab uuid, target_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not public.is_platform_developer()
    and coalesce((
      select coalesce(
        (
          select rp.allowed
          from public.roles_permissions rp
          where rp.lab_id = m.lab_id
            and rp.role_key = m.role
            and rp.permission_key = target_permission
        ),
        exists (
          select 1
          from public.role_default_permissions rdp
          where rdp.role_key = m.role
            and rdp.permission_key = target_permission
        )
      )
      from public.memberships m
      where m.lab_id = target_lab
        and m.user_id = (select auth.uid())
        and m.active
      limit 1
    ), false);
$$;

drop policy if exists platform_developer_labs_read on public.labs;
create policy platform_developer_labs_read on public.labs
  for select to authenticated
  using (public.is_platform_developer());

revoke all on public.labs from public, anon;
revoke insert, update, delete, truncate, references, trigger
  on public.labs from authenticated;
grant select on public.labs to authenticated;
grant select on public.memberships to authenticated;

create or replace function public.create_lab(
  p_name text,
  p_slug text,
  p_currency text default 'USD',
  p_timezone text default 'UTC'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_lab_id uuid;
begin
  if auth.uid() is null or not public.is_platform_developer() then
    raise exception using errcode = '42501', message = 'Platform developer access required';
  end if;

  if p_name is null or length(btrim(p_name)) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'Lab name must be between 2 and 120 characters';
  end if;

  if p_slug is null
    or length(p_slug) > 80
    or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
  then
    raise exception using errcode = '22023', message = 'Lab slug must use lowercase letters, numbers, and hyphens';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Currency must be a three-letter uppercase code';
  end if;

  if p_timezone is null or not exists (
    select 1
    from pg_catalog.pg_timezone_names tz
    where tz.name = btrim(p_timezone)
  ) then
    raise exception using errcode = '22023', message = 'Timezone is not recognized';
  end if;

  insert into public.labs (name, slug)
  values (btrim(p_name), p_slug)
  returning id into new_lab_id;

  insert into public.lab_settings (lab_id, currency, timezone)
  values (new_lab_id, p_currency::char(3), btrim(p_timezone));

  insert into public.audit_logs (
    lab_id,
    actor_id,
    action,
    entity_type,
    entity_id,
    after_redacted
  )
  values (
    new_lab_id,
    auth.uid(),
    'lab.created',
    'lab',
    new_lab_id::text,
    jsonb_build_object('name', btrim(p_name), 'slug', p_slug)
  );

  return new_lab_id;
end;
$$;

revoke all on function public.create_lab(text, text, text, text) from public, anon;
grant execute on function public.create_lab(text, text, text, text) to authenticated;
