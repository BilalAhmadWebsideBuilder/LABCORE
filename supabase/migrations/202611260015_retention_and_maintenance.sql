create or replace function public.get_lab_retention_policy(p_lab_id uuid)
returns table(retention_days integer, legal_hold_enabled boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'settings.read') then
    raise exception using errcode = '42501', message = 'Settings read permission required';
  end if;

  return query
    select policy.retention_days, policy.legal_hold_enabled
    from public.retention_settings policy
    where policy.lab_id = p_lab_id;
  if not found then
    return query select 2555, false;
  end if;
end;
$$;

create or replace function public.save_lab_retention_policy(
  p_lab_id uuid,
  p_retention_days integer,
  p_legal_hold_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'settings.manage') then
    raise exception using errcode = '42501', message = 'Settings management permission required';
  end if;
  if p_retention_days is null or p_retention_days < 365 or p_retention_days > 36500
    or p_legal_hold_enabled is null then
    raise exception using errcode = '22023', message = 'Retention must be between 365 and 36500 days';
  end if;

  insert into public.retention_settings(lab_id, retention_days, legal_hold_enabled)
  values (p_lab_id, p_retention_days, p_legal_hold_enabled)
  on conflict (lab_id) do update
  set retention_days = excluded.retention_days,
      legal_hold_enabled = excluded.legal_hold_enabled,
      updated_at = now();
end;
$$;

create or replace function public.run_lab_retention_cleanup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_holds integer;
  removed_tokens integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Trusted maintenance service required';
  end if;

  expired_holds := public.expire_slot_holds();
  delete from public.portal_tokens token
  where token.expires_at <= now() - interval '30 days'
    and not exists (
      select 1 from public.retention_settings policy
      where policy.lab_id = token.lab_id and policy.legal_hold_enabled
    );
  get diagnostics removed_tokens = row_count;

  return jsonb_build_object(
    'expired_slot_holds', expired_holds,
    'removed_expired_tokens', removed_tokens,
    'clinical_records_deleted', 0
  );
end;
$$;

revoke all on function public.get_lab_retention_policy(uuid) from public, anon;
revoke all on function public.save_lab_retention_policy(uuid, integer, boolean) from public, anon;
revoke all on function public.run_lab_retention_cleanup() from public, anon, authenticated;
grant execute on function public.get_lab_retention_policy(uuid) to authenticated;
grant execute on function public.save_lab_retention_policy(uuid, integer, boolean) to authenticated;
grant execute on function public.run_lab_retention_cleanup() to service_role;
