create extension if not exists btree_gist;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'staff_shifts_no_overlap'
      and conrelid = 'public.staff_shifts'::regclass
  ) then
    alter table public.staff_shifts
      add constraint staff_shifts_no_overlap
      exclude using gist (
        staff_id with =,
        tstzrange(starts_at, ends_at, '[)') with &&
      ) where (status in ('scheduled', 'leave'));
  end if;
end;
$$;

create or replace function public.get_lab_schedule_resources(p_lab_id uuid)
returns table(resource_id uuid, name text, resource_type text, active boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.read') then
    raise exception using errcode = '42501', message = 'Scheduling read permission required';
  end if;

  return query
    select r.id, r.name, r.resource_type, r.active
    from public.resources r
    where r.lab_id = p_lab_id
    order by r.active desc, r.name;
end;
$$;

create or replace function public.get_lab_schedule_staff(p_lab_id uuid)
returns table(staff_id uuid, full_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Scheduling management permission required';
  end if;

  return query
    select m.user_id, coalesce(p.full_name, '')
    from public.memberships m
    left join public.profiles p on p.id = m.user_id
    where m.lab_id = p_lab_id and m.active
    order by p.full_name nulls last, m.user_id;
end;
$$;

create or replace function public.get_lab_resource_bookings(
  p_lab_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table(
  booking_id uuid,
  resource_id uuid,
  resource_name text,
  starts_at timestamptz,
  ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.read') then
    raise exception using errcode = '42501', message = 'Scheduling read permission required';
  end if;
  if p_from is null or p_to is null or p_from >= p_to then
    raise exception using errcode = '22023', message = 'A valid schedule range is required';
  end if;

  return query
    select b.id, b.resource_id, r.name, b.starts_at, b.ends_at
    from public.resource_bookings b
    join public.resources r on r.id = b.resource_id and r.lab_id = b.lab_id
    where b.lab_id = p_lab_id
      and b.active
      and b.starts_at < p_to
      and b.ends_at > p_from
    order by b.starts_at, r.name;
end;
$$;

create or replace function public.get_lab_staff_shifts(
  p_lab_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table(
  shift_id uuid,
  staff_id uuid,
  staff_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.read') then
    raise exception using errcode = '42501', message = 'Scheduling read permission required';
  end if;
  if p_from is null or p_to is null or p_from >= p_to then
    raise exception using errcode = '22023', message = 'A valid schedule range is required';
  end if;

  return query
    select s.id, s.staff_id, coalesce(p.full_name, ''), s.starts_at, s.ends_at, s.status
    from public.staff_shifts s
    join public.memberships m on m.user_id = s.staff_id and m.lab_id = s.lab_id and m.active
    left join public.profiles p on p.id = s.staff_id
    where s.lab_id = p_lab_id
      and s.status <> 'cancelled'
      and s.starts_at < p_to
      and s.ends_at > p_from
    order by s.starts_at, p.full_name nulls last;
end;
$$;

create or replace function public.create_lab_resource(
  p_lab_id uuid,
  p_name text,
  p_resource_type text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  resource_name text := nullif(btrim(p_name), '');
  resource_kind text := nullif(btrim(p_resource_type), '');
  saved_id uuid;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Scheduling management permission required';
  end if;
  if resource_name is null or length(resource_name) > 80
    or resource_kind is null or length(resource_kind) > 60 then
    raise exception using errcode = '22023', message = 'Resource name and type are required and must be within the length limits';
  end if;

  insert into public.resources(lab_id, name, resource_type)
  values (p_lab_id, resource_name, resource_kind)
  returning id into saved_id;
  return saved_id;
end;
$$;

create or replace function public.set_lab_resource_active(
  p_lab_id uuid,
  p_resource_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Scheduling management permission required';
  end if;
  if p_active is null then
    raise exception using errcode = '22023', message = 'Resource status is required';
  end if;
  if not p_active and exists (
    select 1 from public.resource_bookings b
    where b.lab_id = p_lab_id
      and b.resource_id = p_resource_id
      and b.active
      and b.ends_at > now()
  ) then
    raise exception using errcode = '23514', message = 'Cancel future bookings before deactivating this resource';
  end if;

  update public.resources
  set active = p_active, updated_at = now()
  where id = p_resource_id and lab_id = p_lab_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Resource not found in this laboratory';
  end if;
end;
$$;

create or replace function public.create_lab_resource_booking(
  p_lab_id uuid,
  p_resource_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_appointment_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved_id uuid;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Scheduling management permission required';
  end if;
  if p_starts_at is null or p_ends_at is null
    or p_starts_at <= now() or p_ends_at <= p_starts_at
    or p_ends_at - p_starts_at > interval '24 hours' then
    raise exception using errcode = '22023', message = 'Resource booking time range is invalid';
  end if;
  if not exists (
    select 1 from public.resources r
    where r.id = p_resource_id and r.lab_id = p_lab_id and r.active
  ) then
    raise exception using errcode = '22023', message = 'Select an active resource from this laboratory';
  end if;
  if p_appointment_id is not null and not exists (
    select 1 from public.appointments a
    where a.id = p_appointment_id
      and a.lab_id = p_lab_id
      and a.status = 'scheduled'
      and p_starts_at >= a.starts_at
      and p_ends_at <= a.ends_at
  ) then
    raise exception using errcode = '22023', message = 'The resource booking must fit inside a scheduled appointment in this laboratory';
  end if;

  insert into public.resource_bookings(
    lab_id, resource_id, appointment_id, starts_at, ends_at, active
  )
  values (p_lab_id, p_resource_id, p_appointment_id, p_starts_at, p_ends_at, true)
  returning id into saved_id;
  return saved_id;
end;
$$;

create or replace function public.cancel_lab_resource_booking(
  p_lab_id uuid,
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Scheduling management permission required';
  end if;

  update public.resource_bookings
  set active = false, updated_at = now()
  where id = p_booking_id and lab_id = p_lab_id and active;
  if not found then
    raise exception using errcode = 'P0002', message = 'Active resource booking not found in this laboratory';
  end if;
end;
$$;

create or replace function public.create_lab_staff_shift(
  p_lab_id uuid,
  p_staff_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_status text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved_id uuid;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Scheduling management permission required';
  end if;
  if p_starts_at is null or p_ends_at is null
    or p_starts_at <= now() or p_ends_at <= p_starts_at
    or p_ends_at - p_starts_at > interval '24 hours'
    or p_status not in ('scheduled', 'leave') then
    raise exception using errcode = '22023', message = 'Staff shift details are invalid';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.lab_id = p_lab_id and m.user_id = p_staff_id and m.active
  ) then
    raise exception using errcode = '22023', message = 'Select an active staff member from this laboratory';
  end if;

  insert into public.staff_shifts(lab_id, staff_id, starts_at, ends_at, status)
  values (p_lab_id, p_staff_id, p_starts_at, p_ends_at, p_status)
  returning id into saved_id;
  return saved_id;
end;
$$;

create or replace function public.cancel_lab_staff_shift(
  p_lab_id uuid,
  p_shift_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Scheduling management permission required';
  end if;

  update public.staff_shifts
  set status = 'cancelled', updated_at = now()
  where id = p_shift_id and lab_id = p_lab_id and status <> 'cancelled';
  if not found then
    raise exception using errcode = 'P0002', message = 'Active staff shift not found in this laboratory';
  end if;
end;
$$;

revoke all on function public.get_lab_schedule_resources(uuid) from public, anon;
revoke all on function public.get_lab_schedule_staff(uuid) from public, anon;
revoke all on function public.get_lab_resource_bookings(uuid, timestamptz, timestamptz) from public, anon;
revoke all on function public.get_lab_staff_shifts(uuid, timestamptz, timestamptz) from public, anon;
revoke all on function public.create_lab_resource(uuid, text, text) from public, anon;
revoke all on function public.set_lab_resource_active(uuid, uuid, boolean) from public, anon;
revoke all on function public.create_lab_resource_booking(uuid, uuid, timestamptz, timestamptz, uuid) from public, anon;
revoke all on function public.cancel_lab_resource_booking(uuid, uuid) from public, anon;
revoke all on function public.create_lab_staff_shift(uuid, uuid, timestamptz, timestamptz, text) from public, anon;
revoke all on function public.cancel_lab_staff_shift(uuid, uuid) from public, anon;

grant execute on function public.get_lab_schedule_resources(uuid) to authenticated;
grant execute on function public.get_lab_schedule_staff(uuid) to authenticated;
grant execute on function public.get_lab_resource_bookings(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.get_lab_staff_shifts(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.create_lab_resource(uuid, text, text) to authenticated;
grant execute on function public.set_lab_resource_active(uuid, uuid, boolean) to authenticated;
grant execute on function public.create_lab_resource_booking(uuid, uuid, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.cancel_lab_resource_booking(uuid, uuid) to authenticated;
grant execute on function public.create_lab_staff_shift(uuid, uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.cancel_lab_staff_shift(uuid, uuid) to authenticated;

revoke insert, update, delete on public.resources, public.resource_bookings, public.staff_shifts
  from public, anon, authenticated;
grant select on public.resources, public.resource_bookings, public.staff_shifts to authenticated;
