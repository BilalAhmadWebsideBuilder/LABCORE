create or replace function public.create_lab_with_admin(
  p_name text,
  p_slug text,
  p_currency text default 'USD',
  p_timezone text default 'UTC',
  p_admin_email text default null,
  p_admin_full_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_lab_id uuid;
  admin_user_id uuid;
begin
  if auth.uid() is null or not public.is_platform_developer() then
    raise exception using errcode = '42501', message = 'Platform developer access required';
  end if;

  if p_name is null or length(btrim(p_name)) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'Lab name must be between 2 and 120 characters';
  end if;
  if p_slug is null or length(p_slug) > 80 or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using errcode = '22023', message = 'Lab slug must use lowercase letters, numbers, and hyphens';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Currency must be a three-letter uppercase code';
  end if;
  if p_timezone is null or not exists (
    select 1 from pg_catalog.pg_timezone_names tz where tz.name = btrim(p_timezone)
  ) then
    raise exception using errcode = '22023', message = 'Timezone is not recognized';
  end if;
  if p_admin_email is null
    or p_admin_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  then
    raise exception using errcode = '22023', message = 'Enter a valid laboratory administrator email';
  end if;
  if p_admin_full_name is null or length(btrim(p_admin_full_name)) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'Enter the laboratory administrator name';
  end if;

  select u.id into admin_user_id
  from auth.users u
  where lower(u.email) = lower(btrim(p_admin_email))
  limit 1;

  if admin_user_id is null then
    raise exception using errcode = 'P0002', message = 'Create the administrator in Supabase Authentication first';
  end if;
  if exists (
    select 1 from public.platform_developers pd
    where pd.user_id = admin_user_id
  ) then
    raise exception using errcode = '22023', message = 'The platform developer account cannot be a laboratory administrator';
  end if;
  if exists (
    select 1 from public.memberships m
    where m.user_id = admin_user_id and m.active
  ) then
    raise exception using errcode = '22023', message = 'This administrator already belongs to a laboratory';
  end if;

  insert into public.labs (name, slug)
  values (btrim(p_name), p_slug)
  returning id into new_lab_id;

  insert into public.lab_settings (lab_id, currency, timezone)
  values (new_lab_id, p_currency::char(3), btrim(p_timezone));

  insert into public.profiles (id, full_name)
  values (admin_user_id, btrim(p_admin_full_name))
  on conflict (id) do update set
    full_name = excluded.full_name,
    updated_at = now();

  insert into public.memberships (lab_id, user_id, role, active)
  values (new_lab_id, admin_user_id, 'lab_admin', true);

  insert into public.page_grants (lab_id, user_id, page_key, granted_by)
  select new_lab_id, admin_user_id, d.page_key, auth.uid()
  from public.role_default_page_grants d
  where d.role_key = 'lab_admin'
  on conflict (lab_id, user_id, page_key) do nothing;

  insert into public.audit_logs (
    lab_id, actor_id, action, entity_type, entity_id, after_redacted
  )
  values (
    new_lab_id,
    auth.uid(),
    'lab.created_with_admin',
    'lab',
    new_lab_id::text,
    jsonb_build_object(
      'name', btrim(p_name),
      'slug', p_slug,
      'admin_user_id', admin_user_id
    )
  );

  return new_lab_id;
end;
$$;

revoke all on function public.create_lab_with_admin(text, text, text, text, text, text) from public, anon;
grant execute on function public.create_lab_with_admin(text, text, text, text, text, text) to authenticated;
