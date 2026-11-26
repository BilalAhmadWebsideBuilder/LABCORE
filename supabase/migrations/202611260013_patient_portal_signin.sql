create or replace function public.is_patient_portal_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.patient_accounts account
    where account.user_id = auth.uid()
      and account.activated_at is not null
  );
$$;

create or replace function public.get_my_patient_reports()
returns table(
  report_id uuid,
  laboratory_name text,
  patient_name text,
  patient_code text,
  test_name text,
  result_text text,
  published_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_patient_portal_user() then
    raise exception using errcode = '42501', message = 'An activated patient account is required';
  end if;

  return query
    select result.id, lab.name, patient.full_name, patient.patient_code,
      service.name, result.result_text, result.published_at
    from public.patient_accounts account
    join public.patients patient
      on patient.id = account.patient_id and patient.lab_id = account.lab_id
    join public.labs lab on lab.id = account.lab_id
    join public.report_results result
      on result.patient_id = account.patient_id and result.lab_id = account.lab_id
    join public.order_items order_item
      on order_item.id = result.order_item_id and order_item.lab_id = result.lab_id
    join public.services service
      on service.id = order_item.service_id and service.lab_id = order_item.lab_id
    where account.user_id = auth.uid()
      and account.activated_at is not null
      and result.status = 'published'
    order by result.published_at desc nulls last, result.id;
end;
$$;

revoke all on function public.is_patient_portal_user() from public, anon;
revoke all on function public.get_my_patient_reports() from public, anon;
grant execute on function public.is_patient_portal_user() to authenticated;
grant execute on function public.get_my_patient_reports() to authenticated;
