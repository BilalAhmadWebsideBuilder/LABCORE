do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'appointment_patient_no_overlap'
      and conrelid = 'public.appointments'::regclass
  ) then
    alter table public.appointments
      add constraint appointment_patient_no_overlap
      exclude using gist (
        patient_id with =,
        tstzrange(starts_at, ends_at, '[)') with &&
      ) where (status = 'scheduled');
  end if;
end;
$$;

create or replace function public.create_lab_appointment(
  p_lab_id uuid,
  p_patient_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  appointment_id uuid;
  lab_timezone text;
  local_start timestamp;
  local_end timestamp;
  open_time time;
  close_time time;
  is_closed boolean;
begin
  if auth.uid() is null
    or not public.has_lab_permission(p_lab_id, 'appointments.manage') then
    raise exception using errcode = '42501', message = 'Appointment scheduling permission required';
  end if;
  if p_starts_at is null or p_ends_at is null
    or p_starts_at < now()
    or p_ends_at <= p_starts_at
    or p_ends_at - p_starts_at > interval '8 hours'
    or length(coalesce(p_reason, '')) > 240 then
    raise exception using errcode = '22023', message = 'Appointment time or reason is invalid';
  end if;
  if not exists (
    select 1 from public.patients p
    where p.id = p_patient_id and p.lab_id = p_lab_id and p.deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Patient is unavailable in this laboratory';
  end if;

  select coalesce(settings.timezone, 'UTC') into lab_timezone
  from public.lab_settings settings where settings.lab_id = p_lab_id;
  local_start := p_starts_at at time zone coalesce(lab_timezone, 'UTC');
  local_end := p_ends_at at time zone coalesce(lab_timezone, 'UTC');
  if local_start::date <> local_end::date then
    raise exception using errcode = '22023', message = 'Appointments must start and end on the same local date';
  end if;
  select hours.opens_at, hours.closes_at, hours.closed
  into open_time, close_time, is_closed
  from public.working_hours hours
  where hours.lab_id = p_lab_id
    and hours.weekday = extract(dow from local_start)::smallint;
  if found and (
    is_closed
    or local_start::time < open_time
    or local_end::time > close_time
  ) then
    raise exception using errcode = '23514', message = 'Appointment is outside the laboratory working hours';
  end if;

  insert into public.appointments(lab_id, patient_id, starts_at, ends_at, status, reason)
  values (p_lab_id, p_patient_id, p_starts_at, p_ends_at, 'scheduled', nullif(btrim(p_reason), ''))
  returning id into appointment_id;
  return appointment_id;
end;
$$;

create or replace function public.cancel_lab_appointment(
  p_lab_id uuid,
  p_appointment_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'appointments.manage') then
    raise exception using errcode = '42501', message = 'Appointment management permission required';
  end if;
  if length(btrim(coalesce(p_reason, ''))) not between 2 and 240 then
    raise exception using errcode = '22023', message = 'Provide a cancellation reason';
  end if;
  update public.appointments
  set status = 'cancelled',
      reason = concat_ws(' - ', nullif(btrim(reason), ''), 'Cancelled: ' || btrim(p_reason)),
      updated_at = now()
  where id = p_appointment_id and lab_id = p_lab_id and status = 'scheduled';
  if not found then
    raise exception using errcode = 'P0002', message = 'Scheduled appointment not found';
  end if;
end;
$$;

create or replace function public.get_lab_appointments(
  p_lab_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table(
  appointment_id uuid,
  patient_id uuid,
  patient_name text,
  patient_code text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'appointments.read') then
    raise exception using errcode = '42501', message = 'Appointment read permission required';
  end if;
  if p_from is null or p_to is null or p_from >= p_to or p_to - p_from > interval '62 days' then
    raise exception using errcode = '22023', message = 'Select a date range of at most 62 days';
  end if;
  return query
    select a.id, a.patient_id, p.full_name, p.patient_code,
      a.starts_at, a.ends_at, a.status, a.reason
    from public.appointments a
    join public.patients p on p.id = a.patient_id and p.lab_id = a.lab_id
    where a.lab_id = p_lab_id
      and a.starts_at >= p_from and a.starts_at < p_to
    order by a.starts_at
    limit 1000;
end;
$$;

create or replace function public.get_lab_patient_choices(p_lab_id uuid)
returns table(patient_id uuid, patient_code text, full_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.patient_code, p.full_name
  from public.patients p
  where p.lab_id = p_lab_id
    and p.deleted_at is null
    and (
      public.has_lab_permission(p_lab_id, 'appointments.manage')
      or public.has_lab_permission(p_lab_id, 'patients.read')
    )
  order by p.full_name
  limit 500;
$$;

create or replace function public.save_lab_working_hour(
  p_lab_id uuid,
  p_weekday smallint,
  p_opens_at time,
  p_closes_at time,
  p_closed boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'scheduling.manage') then
    raise exception using errcode = '42501', message = 'Schedule management permission required';
  end if;
  if p_weekday not between 0 and 6
    or p_closed is null
    or (not p_closed and (p_opens_at is null or p_closes_at is null or p_opens_at >= p_closes_at)) then
    raise exception using errcode = '22023', message = 'Working-hour values are invalid';
  end if;
  insert into public.working_hours(lab_id, weekday, opens_at, closes_at, closed)
  values (p_lab_id, p_weekday, coalesce(p_opens_at, time '09:00'), coalesce(p_closes_at, time '17:00'), p_closed)
  on conflict (lab_id, weekday)
  do update set opens_at = excluded.opens_at,
    closes_at = excluded.closes_at,
    closed = excluded.closed,
    updated_at = now();
end;
$$;

revoke insert, update, delete on public.appointments, public.working_hours
  from public, anon, authenticated;

revoke all on function public.create_lab_appointment(uuid, uuid, timestamptz, timestamptz, text) from public, anon;
revoke all on function public.cancel_lab_appointment(uuid, uuid, text) from public, anon;
revoke all on function public.get_lab_appointments(uuid, timestamptz, timestamptz) from public, anon;
revoke all on function public.get_lab_patient_choices(uuid) from public, anon;
revoke all on function public.save_lab_working_hour(uuid, smallint, time, time, boolean) from public, anon;

grant execute on function public.create_lab_appointment(uuid, uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.cancel_lab_appointment(uuid, uuid, text) to authenticated;
grant execute on function public.get_lab_appointments(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.get_lab_patient_choices(uuid) to authenticated;
grant execute on function public.save_lab_working_hour(uuid, smallint, time, time, boolean) to authenticated;
