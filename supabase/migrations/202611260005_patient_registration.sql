alter table public.patients
  add column if not exists gender text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'patients_gender_allowed'
      and conrelid = 'public.patients'::regclass
  ) then
    alter table public.patients
      add constraint patients_gender_allowed
      check (gender is null or gender in ('female', 'male', 'other', 'prefer_not_to_say'));
  end if;
end;
$$;

revoke all on public.patients from public, anon, authenticated;
grant select on public.patients to authenticated;
grant select on public.profiles to authenticated;

create or replace function public.register_patient(
  p_lab_id uuid,
  p_full_name text,
  p_phone text,
  p_date_of_birth date default null,
  p_gender text default null,
  p_emergency_contact text default null
)
returns table (
  patient_id uuid,
  patient_code text,
  full_name text,
  phone text,
  date_of_birth date,
  gender text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_patient_id uuid;
  new_patient_code text;
begin
  if auth.uid() is null
    or not public.has_lab_permission(p_lab_id, 'patients.write')
  then
    raise exception using errcode = '42501', message = 'Patient registration permission required';
  end if;

  if p_full_name is null or length(btrim(p_full_name)) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'Patient name must be between 2 and 120 characters';
  end if;

  if p_phone is null or length(btrim(p_phone)) not between 5 and 32 then
    raise exception using errcode = '22023', message = 'Phone number must be between 5 and 32 characters';
  end if;

  if p_date_of_birth is not null
    and (p_date_of_birth > current_date or p_date_of_birth < current_date - interval '120 years')
  then
    raise exception using errcode = '22023', message = 'Date of birth is outside the accepted range';
  end if;

  if p_gender is not null
    and p_gender not in ('female', 'male', 'other', 'prefer_not_to_say')
  then
    raise exception using errcode = '22023', message = 'Select a valid gender option';
  end if;

  if p_emergency_contact is not null and length(btrim(p_emergency_contact)) > 120 then
    raise exception using errcode = '22023', message = 'Emergency contact must not exceed 120 characters';
  end if;

  insert into public.patients (lab_id, full_name, phone, date_of_birth, gender)
  values (
    p_lab_id,
    btrim(p_full_name),
    btrim(p_phone),
    p_date_of_birth,
    p_gender
  )
  returning id, patients.patient_code
  into new_patient_id, new_patient_code;

  if nullif(btrim(coalesce(p_emergency_contact, '')), '') is not null then
    insert into public.patient_contacts (lab_id, patient_id, contact_type, value)
    values (p_lab_id, new_patient_id, 'emergency', btrim(p_emergency_contact));
  end if;

  insert into public.audit_logs (
    lab_id,
    actor_id,
    action,
    entity_type,
    entity_id,
    after_redacted
  )
  values (
    p_lab_id,
    auth.uid(),
    'patient.registered',
    'patient',
    new_patient_id::text,
    jsonb_build_object(
      'patient_code', new_patient_code,
      'fields_recorded', jsonb_build_array('full_name', 'phone', 'date_of_birth', 'gender')
    )
  );

  return query
  select p.id, p.patient_code, p.full_name, p.phone, p.date_of_birth, p.gender, p.created_at
  from public.patients p
  where p.id = new_patient_id and p.lab_id = p_lab_id;
end;
$$;

revoke all on function public.register_patient(uuid, text, text, date, text, text)
  from public, anon;
grant execute on function public.register_patient(uuid, text, text, date, text, text)
  to authenticated;
