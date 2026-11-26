alter table public.samples
  add column if not exists rejection_reason text;

insert into public.role_default_page_grants(role_key, page_key)
values ('lab_manager','analytics')
on conflict do nothing;

create or replace function public.has_lab_permission(target_lab uuid, target_permission text)
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
        ), false)
        and case
          when target_permission in ('patients.read','patients.write') then
            public.has_lab_page_access(target_lab, 'patients')
          when target_permission like 'services.%' then
            public.has_lab_page_access(target_lab, 'tests')
            or public.has_lab_page_access(target_lab, 'departments')
            or public.has_lab_page_access(target_lab, 'test_billing')
          when target_permission like 'orders.%' then
            public.has_lab_page_access(target_lab, 'samples')
            or public.has_lab_page_access(target_lab, 'test_billing')
            or public.has_lab_page_access(target_lab, 'reports')
          when target_permission like 'billing.%' then
            public.has_lab_page_access(target_lab, 'invoice_history')
            or public.has_lab_page_access(target_lab, 'test_billing')
          when target_permission like 'reports.%' then
            public.has_lab_page_access(target_lab, 'reports')
          when target_permission like 'appointments.%' then
            public.has_lab_page_access(target_lab, 'appointments')
          when target_permission like 'scheduling.%' then
            public.has_lab_page_access(target_lab, 'scheduling')
          when target_permission like 'doctors.%' then
            public.has_lab_page_access(target_lab, 'referring_doctors')
          when target_permission like 'inventory.%' then
            public.has_lab_page_access(target_lab, 'reagent_stock')
          when target_permission like 'expenses.%' then
            public.has_lab_page_access(target_lab, 'expenses')
          when target_permission in ('staff.manage','roles.manage') then
            public.has_lab_page_access(target_lab, 'manage_users')
          when target_permission = 'analytics.read' or target_permission = 'export.run' then
            public.has_lab_page_access(target_lab, 'analytics')
          when target_permission like 'settings.%'
            or target_permission = 'support.access.manage' then
            public.has_lab_page_access(target_lab, 'settings')
          when target_permission like 'print_requests.%' then
            public.has_lab_page_access(target_lab, 'print_requests')
            or public.has_lab_page_access(target_lab, 'my_print_requests')
          when target_permission like 'notifications.%' then
            public.has_lab_page_access(target_lab, 'dashboard')
          when target_permission in ('audit.read','audit.write') then true
          else true
        end
    );
$$;

create or replace function public.create_lab_invoice(
  p_lab_id uuid,
  p_patient_id uuid,
  p_service_ids uuid[],
  p_discount numeric,
  p_discount_reason text,
  p_initial_payment numeric,
  p_payment_method text
)
returns table(invoice_id uuid, invoice_number text, visit_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  item_count integer;
  item_subtotal numeric(12,2);
  invoice_total numeric(12,2);
  lab_currency char(3);
  new_visit_id uuid;
  new_invoice_id uuid;
  new_invoice_number text;
  new_visit_code text;
  selected_service record;
  new_order_item_id uuid;
begin
  if auth.uid() is null
    or not public.has_lab_permission(p_lab_id, 'orders.manage')
    or not public.has_lab_permission(p_lab_id, 'billing.manage')
    or not public.has_lab_permission(p_lab_id, 'patients.read')
    or not public.has_lab_permission(p_lab_id, 'services.read') then
    raise exception using errcode = '42501', message = 'Test billing permission required';
  end if;
  if p_service_ids is null or cardinality(p_service_ids) not between 1 and 100
    or cardinality(p_service_ids) <> (
      select count(distinct service_id) from unnest(p_service_ids) as service_id
    ) then
    raise exception using errcode = '22023', message = 'Select between 1 and 100 distinct tests';
  end if;
  if not exists (
    select 1 from public.patients p
    where p.id = p_patient_id and p.lab_id = p_lab_id and p.deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Patient is unavailable in this laboratory';
  end if;

  select count(*), coalesce(sum(s.price), 0)
    into item_count, item_subtotal
  from public.services s
  where s.lab_id = p_lab_id
    and s.id = any(p_service_ids)
    and s.active
    and s.deleted_at is null;
  if item_count <> cardinality(p_service_ids) then
    raise exception using errcode = '22023', message = 'One or more selected tests are unavailable';
  end if;

  select settings.currency into lab_currency
  from public.lab_settings settings where settings.lab_id = p_lab_id;
  if lab_currency is null then
    raise exception using errcode = 'P0002', message = 'Laboratory billing settings are missing';
  end if;
  if coalesce(p_discount, 0) < 0 or coalesce(p_discount, 0) > item_subtotal then
    raise exception using errcode = '22023', message = 'Discount must be between zero and the subtotal';
  end if;
  if coalesce(p_discount, 0) > 0 and (
    not public.has_lab_permission(p_lab_id, 'billing.discount')
    or p_discount_reason is null
    or length(btrim(p_discount_reason)) not between 2 and 240
  ) then
    raise exception using errcode = '42501', message = 'A discount permission and reason are required';
  end if;
  invoice_total := item_subtotal - coalesce(p_discount, 0);
  if coalesce(p_initial_payment, 0) < 0 or p_initial_payment > invoice_total then
    raise exception using errcode = '22023', message = 'Payment must not exceed the invoice total';
  end if;
  if p_initial_payment > 0 and p_payment_method not in ('cash','card','bank_transfer','mobile_wallet','other') then
    raise exception using errcode = '22023', message = 'Select a valid payment method';
  end if;

  new_visit_code := 'V-' || to_char(now(), 'YYYYMMDD') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  insert into public.visits(lab_id, patient_id, visit_code, registered_by)
  values (p_lab_id, p_patient_id, new_visit_code, auth.uid())
  returning id into new_visit_id;

  insert into public.invoices(
    lab_id, patient_id, visit_id, invoice_number, currency, subtotal,
    discount, discount_reason, tax, total, status, created_by
  )
  values (
    p_lab_id, p_patient_id, new_visit_id, '', lab_currency, item_subtotal,
    coalesce(p_discount, 0), nullif(btrim(p_discount_reason), ''), 0,
    invoice_total, 'open', auth.uid()
  )
  returning id, invoices.invoice_number into new_invoice_id, new_invoice_number;

  for selected_service in
    select s.id, s.name, s.price
    from public.services s
    where s.lab_id = p_lab_id and s.id = any(p_service_ids)
    order by s.name
  loop
    insert into public.order_items(lab_id, visit_id, service_id, price)
    values (p_lab_id, new_visit_id, selected_service.id, selected_service.price)
    returning id into new_order_item_id;

    insert into public.invoice_items(
      lab_id, invoice_id, order_item_id, description, quantity, unit_price, line_total
    )
    values (
      p_lab_id, new_invoice_id, new_order_item_id, selected_service.name, 1,
      selected_service.price, selected_service.price
    );

    insert into public.samples(lab_id, order_item_id, barcode)
    values (
      p_lab_id,
      new_order_item_id,
      'S-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 14))
    );

    update public.order_items
    set status = 'test_scheduled', updated_at = now()
    where id = new_order_item_id and lab_id = p_lab_id;
  end loop;

  if p_initial_payment > 0 then
    insert into public.payments(lab_id, invoice_id, amount, method, received_by)
    values (p_lab_id, new_invoice_id, p_initial_payment, p_payment_method, auth.uid())
    returning id into new_order_item_id;

    insert into public.receipts(lab_id, invoice_id, payment_id, receipt_number)
    values (
      p_lab_id, new_invoice_id, new_order_item_id,
      'R-' || to_char(now(), 'YYYYMMDD') || '-' ||
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
    );
  end if;

  return query select new_invoice_id, new_invoice_number, new_visit_code;
end;
$$;

create or replace function public.record_invoice_payment(
  p_lab_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  invoice_total numeric(12,2);
  paid_total numeric(12,2);
  new_payment_id uuid;
  new_receipt_number text;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'billing.manage') then
    raise exception using errcode = '42501', message = 'Payment permission required';
  end if;
  if p_amount is null or p_amount <= 0
    or p_method not in ('cash','card','bank_transfer','mobile_wallet','other') then
    raise exception using errcode = '22023', message = 'Enter a positive payment and valid method';
  end if;

  select i.total into invoice_total
  from public.invoices i
  where i.id = p_invoice_id and i.lab_id = p_lab_id
  for update;
  if invoice_total is null then
    raise exception using errcode = 'P0002', message = 'Invoice not found';
  end if;
  select coalesce(sum(p.amount), 0) into paid_total
  from public.payments p
  where p.invoice_id = p_invoice_id and p.lab_id = p_lab_id and p.voided_at is null;
  if p_amount > invoice_total - paid_total then
    raise exception using errcode = '22023', message = 'Payment exceeds the outstanding balance';
  end if;

  insert into public.payments(lab_id, invoice_id, amount, method, reference, received_by)
  values (p_lab_id, p_invoice_id, p_amount, p_method, nullif(btrim(p_reference), ''), auth.uid())
  returning id into new_payment_id;

  new_receipt_number := 'R-' || to_char(now(), 'YYYYMMDD') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  insert into public.receipts(lab_id, invoice_id, payment_id, receipt_number)
  values (p_lab_id, p_invoice_id, new_payment_id, new_receipt_number);
  return new_receipt_number;
end;
$$;

create or replace function public.update_sample_status(
  p_lab_id uuid,
  p_sample_id uuid,
  p_status text,
  p_rejection_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  sample_order_item uuid;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'orders.manage') then
    raise exception using errcode = '42501', message = 'Sample processing permission required';
  end if;
  if p_status not in ('collected','rejected','recollected') then
    raise exception using errcode = '22023', message = 'Select a valid sample status';
  end if;
  select s.order_item_id into sample_order_item
  from public.samples s
  where s.id = p_sample_id and s.lab_id = p_lab_id
  for update;
  if sample_order_item is null or not public.has_order_item_access(p_lab_id, sample_order_item) then
    raise exception using errcode = '42501', message = 'Sample is not assigned to your laboratory role';
  end if;
  if p_status = 'rejected'
    and length(btrim(coalesce(p_rejection_reason, ''))) not between 2 and 240 then
    raise exception using errcode = '22023', message = 'A reason is required when rejecting a sample';
  end if;

  update public.samples
  set status = p_status,
      rejection_reason = case when p_status = 'rejected' then btrim(p_rejection_reason) else null end,
      updated_at = now()
  where id = p_sample_id and lab_id = p_lab_id;

  if p_status in ('collected','recollected') then
    update public.order_items
    set status = 'sample_collected', updated_at = now()
    where id = sample_order_item and lab_id = p_lab_id and status = 'test_scheduled';
  end if;
end;
$$;

create or replace function public.update_order_item_status(
  p_lab_id uuid,
  p_order_item_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'orders.manage') then
    raise exception using errcode = '42501', message = 'Order processing permission required';
  end if;
  if p_status not in ('in_progress','additional_information_required','cancelled') then
    raise exception using errcode = '22023', message = 'Select a valid order status';
  end if;
  if not public.has_order_item_access(p_lab_id, p_order_item_id) then
    raise exception using errcode = '42501', message = 'Order is not assigned to your laboratory role';
  end if;
  update public.order_items
  set status = p_status, updated_at = now()
  where id = p_order_item_id and lab_id = p_lab_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Order was not found';
  end if;
end;
$$;

create or replace function public.assign_order_item(
  p_lab_id uuid,
  p_order_item_id uuid,
  p_technician_id uuid,
  p_doctor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'orders.assign') then
    raise exception using errcode = '42501', message = 'Order assignment permission required';
  end if;
  if p_technician_id is not null and not exists (
    select 1 from public.memberships m
    where m.lab_id = p_lab_id and m.user_id = p_technician_id
      and m.active and m.role = 'technician'
  ) then
    raise exception using errcode = '22023', message = 'Select an active technician in this laboratory';
  end if;
  if p_doctor_id is not null and not exists (
    select 1 from public.memberships m
    where m.lab_id = p_lab_id and m.user_id = p_doctor_id
      and m.active and m.role = 'reporting_doctor'
  ) then
    raise exception using errcode = '22023', message = 'Select an active reporting doctor in this laboratory';
  end if;
  update public.order_items
  set assigned_technician_id = p_technician_id,
      assigned_doctor_id = p_doctor_id,
      updated_at = now()
  where id = p_order_item_id and lab_id = p_lab_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Order item not found';
  end if;
end;
$$;

create or replace function public.save_report_result(
  p_lab_id uuid,
  p_order_item_id uuid,
  p_result_text text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_patient uuid;
  target_status text;
  result_id uuid;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'reports.upload')
    or not public.has_order_item_access(p_lab_id, p_order_item_id) then
    raise exception using errcode = '42501', message = 'Report entry permission required';
  end if;
  if p_result_text is null or length(btrim(p_result_text)) not between 1 and 10000 then
    raise exception using errcode = '22023', message = 'Result must be between 1 and 10,000 characters';
  end if;

  select v.patient_id into target_patient
  from public.order_items oi
  join public.visits v on v.id = oi.visit_id and v.lab_id = oi.lab_id
  where oi.id = p_order_item_id and oi.lab_id = p_lab_id and oi.status = 'in_progress';
  if target_patient is null then
    raise exception using errcode = '23514', message = 'Start the order before entering results';
  end if;

  select rr.status into target_status
  from public.report_results rr
  where rr.lab_id = p_lab_id and rr.order_item_id = p_order_item_id
  for update;
  if target_status is not null and target_status not in ('awaiting_result','changes_required') then
    raise exception using errcode = '23514', message = 'This report is already under review or published';
  end if;

  insert into public.report_results(
    lab_id, patient_id, order_item_id, result_text, status, entered_by, entered_at, updated_at
  )
  values (
    p_lab_id, target_patient, p_order_item_id, btrim(p_result_text), 'entered',
    auth.uid(), now(), now()
  )
  on conflict (lab_id, order_item_id) do update
  set result_text = excluded.result_text,
      status = 'entered',
      entered_by = auth.uid(),
      entered_at = now(),
      reviewed_by = null,
      reviewed_at = null,
      updated_at = now()
  returning id into result_id;

  update public.order_items
  set status = 'awaiting_doctor_review', updated_at = now()
  where id = p_order_item_id and lab_id = p_lab_id;
  return result_id;
end;
$$;

create or replace function public.review_report_result(
  p_lab_id uuid,
  p_report_result_id uuid,
  p_decision text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_order_item uuid;
  target_entered_by uuid;
  allow_self_review boolean;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'reports.review') then
    raise exception using errcode = '42501', message = 'Report review permission required';
  end if;
  if p_decision not in ('approved','changes_required') then
    raise exception using errcode = '22023', message = 'Select an allowed review decision';
  end if;
  select rr.order_item_id, rr.entered_by
  into target_order_item, target_entered_by
  from public.report_results rr
  where rr.id = p_report_result_id and rr.lab_id = p_lab_id and rr.status = 'entered'
  for update;
  if target_order_item is null or not public.has_order_item_access(p_lab_id, target_order_item) then
    raise exception using errcode = '42501', message = 'Report is unavailable for review';
  end if;
  select settings.allow_report_self_approval into allow_self_review
  from public.lab_settings settings where settings.lab_id = p_lab_id;
  if target_entered_by = auth.uid() and not coalesce(allow_self_review, false) then
    raise exception using errcode = '42501', message = 'The report author cannot review their own result';
  end if;

  update public.report_results
  set status = p_decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      updated_at = now()
  where id = p_report_result_id and lab_id = p_lab_id;

  if p_decision = 'changes_required' then
    update public.order_items
    set status = 'additional_information_required', updated_at = now()
    where id = target_order_item and lab_id = p_lab_id;
  end if;
end;
$$;

create or replace function public.publish_report_result(
  p_lab_id uuid,
  p_report_result_id uuid,
  p_token_hash text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_order_item uuid;
  target_author uuid;
  dual_approval boolean;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'reports.publish') then
    raise exception using errcode = '42501', message = 'Report publication permission required';
  end if;
  if p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'A valid report-link digest is required';
  end if;
  select rr.order_item_id, rr.entered_by
  into target_order_item, target_author
  from public.report_results rr
  where rr.id = p_report_result_id and rr.lab_id = p_lab_id and rr.status = 'approved'
  for update;
  if target_order_item is null or not public.has_order_item_access(p_lab_id, target_order_item) then
    raise exception using errcode = '42501', message = 'Only an approved assigned report can be published';
  end if;
  select settings.require_dual_approval into dual_approval
  from public.lab_settings settings where settings.lab_id = p_lab_id;
  if coalesce(dual_approval, true) and target_author = auth.uid() then
    raise exception using errcode = '42501', message = 'A different staff member must publish this report';
  end if;

  insert into public.report_result_links(lab_id, report_result_id, token_hash, expires_at)
  values (p_lab_id, p_report_result_id, p_token_hash, now() + interval '90 days');
  update public.report_results
  set status = 'published',
      published_by = auth.uid(),
      published_at = now(),
      updated_at = now()
  where id = p_report_result_id and lab_id = p_lab_id;
  update public.order_items
  set status = 'report_available', updated_at = now()
  where id = target_order_item and lab_id = p_lab_id;
end;
$$;

create or replace function public.get_public_report(p_token_hash text)
returns table(
  laboratory_name text,
  patient_name text,
  patient_code text,
  test_name text,
  result_text text,
  published_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select l.name, p.full_name, p.patient_code, s.name, rr.result_text, rr.published_at
  from public.report_result_links link
  join public.report_results rr
    on rr.id = link.report_result_id and rr.lab_id = link.lab_id
  join public.labs l on l.id = rr.lab_id
  join public.patients p on p.id = rr.patient_id and p.lab_id = rr.lab_id
  join public.order_items oi on oi.id = rr.order_item_id and oi.lab_id = rr.lab_id
  join public.services s on s.id = oi.service_id and s.lab_id = oi.lab_id
  where link.token_hash = p_token_hash
    and link.revoked_at is null
    and (link.expires_at is null or link.expires_at > now())
    and rr.status = 'published'
  limit 1;
$$;

create or replace function public.get_lab_sample_board(p_lab_id uuid)
returns table(
  sample_id uuid,
  barcode text,
  sample_status text,
  rejection_reason text,
  order_item_id uuid,
  assigned_technician_id uuid,
  assigned_doctor_id uuid,
  order_status text,
  patient_name text,
  patient_code text,
  test_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'orders.read') then
    raise exception using errcode = '42501', message = 'Sample board access required';
  end if;
  return query
    select s.id, s.barcode, s.status, s.rejection_reason, oi.id,
      oi.assigned_technician_id, oi.assigned_doctor_id, oi.status,
      p.full_name, p.patient_code, service.name
    from public.samples s
    join public.order_items oi on oi.id = s.order_item_id and oi.lab_id = s.lab_id
    join public.visits v on v.id = oi.visit_id and v.lab_id = oi.lab_id
    join public.patients p on p.id = v.patient_id and p.lab_id = v.lab_id
    join public.services service on service.id = oi.service_id and service.lab_id = oi.lab_id
    where s.lab_id = p_lab_id
      and public.has_order_item_access(p_lab_id, oi.id)
    order by s.created_at desc
    limit 500;
end;
$$;

create or replace function public.get_lab_report_queue(p_lab_id uuid)
returns table(
  report_result_id uuid,
  order_item_id uuid,
  result_text text,
  report_status text,
  patient_name text,
  patient_code text,
  test_name text,
  entered_by uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'reports.read') then
    raise exception using errcode = '42501', message = 'Report queue access required';
  end if;
  return query
    select rr.id, rr.order_item_id, rr.result_text, rr.status,
      p.full_name, p.patient_code, service.name, rr.entered_by
    from public.report_results rr
    join public.order_items oi on oi.id = rr.order_item_id and oi.lab_id = rr.lab_id
    join public.visits v on v.id = oi.visit_id and v.lab_id = oi.lab_id
    join public.patients p on p.id = rr.patient_id and p.lab_id = rr.lab_id
    join public.services service on service.id = oi.service_id and service.lab_id = oi.lab_id
    where rr.lab_id = p_lab_id
      and public.has_order_item_access(p_lab_id, oi.id)
    order by rr.created_at desc
    limit 500;
end;
$$;

create or replace function public.get_reportable_order_items(p_lab_id uuid)
returns table(
  order_item_id uuid,
  patient_name text,
  patient_code text,
  test_name text,
  order_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'reports.upload') then
    raise exception using errcode = '42501', message = 'Result entry access required';
  end if;
  return query
    select oi.id, p.full_name, p.patient_code, service.name, oi.status
    from public.order_items oi
    join public.visits v on v.id = oi.visit_id and v.lab_id = oi.lab_id
    join public.patients p on p.id = v.patient_id and p.lab_id = v.lab_id
    join public.services service on service.id = oi.service_id and service.lab_id = oi.lab_id
    left join public.report_results rr
      on rr.lab_id = oi.lab_id and rr.order_item_id = oi.id
    where oi.lab_id = p_lab_id
      and oi.status in ('in_progress','additional_information_required')
      and (rr.id is null or rr.status = 'changes_required')
      and public.has_order_item_access(p_lab_id, oi.id)
    order by oi.created_at
    limit 200;
end;
$$;

create or replace function public.get_lab_analytics(
  p_lab_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
  patients_total bigint;
  orders_total bigint;
  samples_pending bigint;
  reports_pending bigint;
  revenue_total numeric(12,2);
  expenses_total numeric(12,2);
  due_total numeric(12,2);
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'analytics.read') then
    raise exception using errcode = '42501', message = 'Analytics permission required';
  end if;
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 366 then
    raise exception using errcode = '22023', message = 'Select a date range of at most 366 days';
  end if;

  select count(*) into patients_total
  from public.patients p
  where p.lab_id = p_lab_id and p.deleted_at is null
    and p.created_at::date between p_from and p_to;
  select count(*) into orders_total
  from public.visits v
  where v.lab_id = p_lab_id and v.created_at::date between p_from and p_to;
  select count(*) into samples_pending
  from public.samples s
  where s.lab_id = p_lab_id and s.status = 'pending'
    and s.created_at::date between p_from and p_to;
  select count(*) into reports_pending
  from public.report_results r
  where r.lab_id = p_lab_id and r.status in ('awaiting_result','entered','changes_required')
    and r.created_at::date between p_from and p_to;

  if public.has_lab_permission(p_lab_id, 'billing.read') then
    select coalesce(sum(p.amount), 0) into revenue_total
    from public.payments p
    where p.lab_id = p_lab_id and p.voided_at is null
      and p.received_at::date between p_from and p_to;
    select coalesce(sum(i.total - coalesce(paid.amount, 0)), 0) into due_total
    from public.invoices i
    left join lateral (
      select sum(p.amount) as amount from public.payments p
      where p.invoice_id = i.id and p.lab_id = i.lab_id and p.voided_at is null
    ) paid on true
    where i.lab_id = p_lab_id and i.status not in ('void','credited')
      and i.created_at::date between p_from and p_to;
  end if;
  if public.has_lab_permission(p_lab_id, 'expenses.read') then
    select coalesce(sum(e.amount), 0) into expenses_total
    from public.expenses e
    where e.lab_id = p_lab_id and e.deleted_at is null
      and e.expense_date between p_from and p_to;
  end if;

  result := jsonb_build_object(
    'patients', case when public.has_lab_permission(p_lab_id, 'patients.read') then patients_total else null end,
    'visits', orders_total,
    'pending_samples', samples_pending,
    'pending_reports', reports_pending,
    'revenue', revenue_total,
    'outstanding', due_total,
    'expenses', expenses_total,
    'estimated_margin',
      case when revenue_total is not null and expenses_total is not null
        then revenue_total - expenses_total else null end,
    'margin_note', 'Estimated margin excludes reagent costs'
  );
  return result;
end;
$$;

create or replace function public.set_staff_access(
  p_lab_id uuid,
  p_user_id uuid,
  p_role text,
  p_page_keys text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_role text;
begin
  if auth.uid() is null
    or not public.has_lab_permission(p_lab_id, 'staff.manage')
    or not public.has_lab_permission(p_lab_id, 'roles.manage') then
    raise exception using errcode = '42501', message = 'Staff and role management permission required';
  end if;
  if p_role not in ('lab_admin','lab_manager','receptionist','technician','billing_staff','reporting_doctor')
    or p_page_keys is null
    or exists (
      select 1 from unnest(p_page_keys) as page_key
      where not exists (
        select 1 from public.role_default_page_grants d
        where d.page_key = page_key
      )
    )
    or exists (
      select 1 from unnest(p_page_keys) as page_key
      where not public.has_lab_page_access(p_lab_id, page_key)
    ) then
    raise exception using errcode = '22023', message = 'Role or page grant is not permitted';
  end if;

  select m.role into current_role
  from public.memberships m
  where m.lab_id = p_lab_id and m.user_id = p_user_id and m.active
  for update;
  if current_role is null then
    raise exception using errcode = 'P0002', message = 'Active staff membership not found';
  end if;
  if current_role = 'lab_admin' and p_role <> 'lab_admin'
    and not exists (
      select 1 from public.memberships m
      where m.lab_id = p_lab_id and m.active and m.role = 'lab_admin'
        and m.user_id <> p_user_id
    ) then
    raise exception using errcode = '23514', message = 'A laboratory must retain an active administrator';
  end if;

  update public.memberships
  set role = p_role, updated_at = now()
  where lab_id = p_lab_id and user_id = p_user_id;

  delete from public.page_grants
  where lab_id = p_lab_id and user_id = p_user_id;
  insert into public.page_grants(lab_id, user_id, page_key, granted_by)
  select p_lab_id, p_user_id, page_key, auth.uid()
  from (select distinct unnest(p_page_keys) as page_key) requested;
end;
$$;

create or replace function public.get_lab_staff_access(p_lab_id uuid)
returns table(
  user_id uuid,
  full_name text,
  phone text,
  role text,
  active boolean,
  page_keys text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'staff.manage') then
    raise exception using errcode = '42501', message = 'Staff management permission required';
  end if;
  return query
    select m.user_id, coalesce(p.full_name, ''), p.phone, m.role, m.active,
      coalesce(array_agg(pg.page_key order by pg.page_key)
        filter (where pg.page_key is not null), '{}'::text[])
    from public.memberships m
    left join public.profiles p on p.id = m.user_id
    left join public.page_grants pg
      on pg.lab_id = m.lab_id and pg.user_id = m.user_id
    where m.lab_id = p_lab_id
    group by m.user_id, p.full_name, p.phone, m.role, m.active
    order by m.role, p.full_name nulls last;
end;
$$;

create or replace function public.set_staff_active(
  p_lab_id uuid,
  p_user_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_role text;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'staff.manage') then
    raise exception using errcode = '42501', message = 'Staff management permission required';
  end if;
  select m.role into target_role
  from public.memberships m
  where m.lab_id = p_lab_id and m.user_id = p_user_id
  for update;
  if target_role is null then
    raise exception using errcode = 'P0002', message = 'Staff membership not found';
  end if;
  if not p_active and target_role = 'lab_admin'
    and not exists (
      select 1 from public.memberships m
      where m.lab_id = p_lab_id and m.active and m.role = 'lab_admin'
        and m.user_id <> p_user_id
    ) then
    raise exception using errcode = '23514', message = 'A laboratory must retain an active administrator';
  end if;
  update public.memberships
  set active = p_active, updated_at = now()
  where lab_id = p_lab_id and user_id = p_user_id;
end;
$$;

create or replace function public.assign_invited_member(
  p_lab_id uuid,
  p_user_id uuid,
  p_role text,
  p_page_keys text[],
  p_full_name text,
  p_phone text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
    or not public.has_lab_permission(p_lab_id, 'staff.manage')
    or not public.has_lab_permission(p_lab_id, 'roles.manage') then
    raise exception using errcode = '42501', message = 'Staff invitation permission required';
  end if;
  if p_full_name is null or length(btrim(p_full_name)) not between 2 and 120
    or length(coalesce(p_phone, '')) > 32
    or not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception using errcode = '22023', message = 'Invited staff details are invalid';
  end if;
  if p_role = 'lab_admin'
    and not exists (
      select 1 from public.memberships m
      where m.lab_id = p_lab_id and m.user_id = auth.uid()
        and m.active and m.role = 'lab_admin'
    ) then
    raise exception using errcode = '42501', message = 'Only a laboratory administrator can invite another administrator';
  end if;

  update public.profiles
  set full_name = btrim(p_full_name),
      phone = nullif(btrim(p_phone), ''),
      updated_at = now()
  where id = p_user_id;
  insert into public.audit_logs(
    lab_id, actor_id, action, entity_type, entity_id, after_redacted
  )
  values (
    p_lab_id, auth.uid(), 'update.staff_profile', 'profile', p_user_id::text,
    jsonb_build_object('fields', jsonb_build_array('full_name','phone'))
  );

  insert into public.memberships(lab_id, user_id, role, active)
  values (p_lab_id, p_user_id, p_role, true)
  on conflict (lab_id, user_id)
  do update set role = excluded.role, active = true, updated_at = now();

  perform public.set_staff_access(p_lab_id, p_user_id, p_role, p_page_keys);
end;
$$;

create or replace function public.save_lab_settings(
  p_lab_id uuid,
  p_name text,
  p_city text,
  p_phone text,
  p_email text,
  p_address text,
  p_currency text,
  p_timezone text,
  p_receipt_format text,
  p_receipt_footer text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'settings.manage') then
    raise exception using errcode = '42501', message = 'Laboratory settings permission required';
  end if;
  if p_name is null or length(btrim(p_name)) not between 2 and 120
    or p_currency !~ '^[A-Z]{3}$'
    or p_timezone is null or length(p_timezone) > 80
    or p_receipt_format not in ('thermal_80mm','a4_lab_memo')
    or length(coalesce(p_receipt_footer, '')) > 500 then
    raise exception using errcode = '22023', message = 'One or more laboratory settings are invalid';
  end if;

  update public.labs
  set name = btrim(p_name),
      city = nullif(btrim(p_city), ''),
      phone = nullif(btrim(p_phone), ''),
      email = nullif(btrim(p_email), ''),
      address = nullif(btrim(p_address), ''),
      receipt_format = p_receipt_format,
      receipt_footer = nullif(btrim(p_receipt_footer), ''),
      updated_at = now()
  where id = p_lab_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Laboratory not found';
  end if;
  update public.lab_settings
  set currency = p_currency, timezone = p_timezone, updated_at = now()
  where lab_id = p_lab_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Laboratory settings record not found';
  end if;
  insert into public.audit_logs(
    lab_id, actor_id, action, entity_type, entity_id, after_redacted
  )
  values (
    p_lab_id, auth.uid(), 'update.lab_settings', 'lab', p_lab_id::text,
    jsonb_build_object('fields', jsonb_build_array(
      'name','city','phone','email','address','currency','timezone',
      'receipt_format','receipt_footer'
    ))
  );
end;
$$;

create or replace function public.create_print_request(p_lab_id uuid, p_invoice_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_request_id uuid;
begin
  if auth.uid() is null
    or not public.has_lab_permission(p_lab_id, 'print_requests.manage')
    or not public.has_lab_permission(p_lab_id, 'billing.read') then
    raise exception using errcode = '42501', message = 'Invoice print request permission required';
  end if;
  if not exists (
    select 1 from public.invoices i
    where i.id = p_invoice_id and i.lab_id = p_lab_id and i.status <> 'void'
  ) then
    raise exception using errcode = 'P0002', message = 'Invoice is not available for printing';
  end if;
  insert into public.print_requests(lab_id, invoice_id, requested_by)
  values (p_lab_id, p_invoice_id, auth.uid())
  returning id into new_request_id;
  return new_request_id;
end;
$$;

create or replace function public.review_print_request(
  p_lab_id uuid,
  p_request_id uuid,
  p_decision text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'print_requests.manage') then
    raise exception using errcode = '42501', message = 'Print request management permission required';
  end if;
  if p_decision not in ('approved','rejected','completed')
    or (p_decision = 'rejected' and length(btrim(coalesce(p_reason, ''))) < 2) then
    raise exception using errcode = '22023', message = 'Select a valid decision and provide a reason if rejecting';
  end if;
  update public.print_requests
  set status = p_decision,
      decision_reason = nullif(btrim(p_reason), ''),
      decided_by = auth.uid(),
      decided_at = now(),
      updated_at = now()
  where id = p_request_id and lab_id = p_lab_id
    and (
      (p_decision in ('approved','rejected') and status = 'pending')
      or (p_decision = 'completed' and status = 'approved')
    );
  if not found then
    raise exception using errcode = 'P0002', message = 'Pending print request not found';
  end if;
end;
$$;

create or replace function public.archive_lab_item(p_lab_id uuid, p_kind text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  permission_key text;
begin
  permission_key := case p_kind
    when 'patient' then 'patients.write'
    when 'test' then 'services.manage'
    when 'category' then 'services.manage'
    when 'doctor' then 'doctors.manage'
    when 'reagent' then 'inventory.manage'
    when 'expense' then 'expenses.manage'
    else null
  end;
  if auth.uid() is null or permission_key is null
    or not public.has_lab_permission(p_lab_id, permission_key) then
    raise exception using errcode = '42501', message = 'Archive permission required';
  end if;

  if p_kind = 'patient' then
    update public.patients set deleted_at = now(), updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is null;
  elsif p_kind = 'test' then
    update public.services set deleted_at = now(), updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is null;
  elsif p_kind = 'category' then
    if exists (
      select 1 from public.services s
      where s.lab_id = p_lab_id and s.category_id = p_id and s.deleted_at is null
    ) then
      raise exception using errcode = '23514', message = 'Move or archive the department tests first';
    end if;
    update public.service_categories set deleted_at = now(), updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is null;
  elsif p_kind = 'doctor' then
    update public.referring_doctors set deleted_at = now(), updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is null;
  elsif p_kind = 'reagent' then
    update public.reagent_stock set deleted_at = now(), updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is null;
  else
    update public.expenses set deleted_at = now(), updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is null;
  end if;

  if not found then
    raise exception using errcode = 'P0002', message = 'Active item not found';
  end if;

  if p_kind = 'patient' then
    insert into public.audit_logs(lab_id, actor_id, action, entity_type, entity_id, after_redacted)
    values (
      p_lab_id, auth.uid(), 'archive.patient', 'patient', p_id::text,
      jsonb_build_object('fields', jsonb_build_array('deleted_at'))
    );
  end if;
end;
$$;

create or replace function public.restore_lab_item(p_lab_id uuid, p_kind text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  permission_key text;
begin
  permission_key := case p_kind
    when 'patient' then 'patients.write'
    when 'test' then 'services.manage'
    when 'category' then 'services.manage'
    when 'doctor' then 'doctors.manage'
    when 'reagent' then 'inventory.manage'
    when 'expense' then 'expenses.manage'
    else null
  end;
  if auth.uid() is null or permission_key is null
    or not public.has_lab_permission(p_lab_id, permission_key)
    or not public.has_lab_page_access(p_lab_id, 'trash_bin') then
    raise exception using errcode = '42501', message = 'Restore permission required';
  end if;

  if p_kind = 'patient' then
    update public.patients set deleted_at = null, updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is not null;
  elsif p_kind = 'test' then
    update public.services set deleted_at = null, updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is not null;
  elsif p_kind = 'category' then
    update public.service_categories set deleted_at = null, updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is not null;
  elsif p_kind = 'doctor' then
    update public.referring_doctors set deleted_at = null, updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is not null;
  elsif p_kind = 'reagent' then
    update public.reagent_stock set deleted_at = null, updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is not null;
  elsif p_kind = 'expense' then
    update public.expenses set deleted_at = null, updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is not null;
  else
    raise exception using errcode = '22023', message = 'Unsupported archived item type';
  end if;
  if not found then
    raise exception using errcode = 'P0002', message = 'Archived item not found';
  end if;
  if p_kind = 'patient' then
    insert into public.audit_logs(lab_id, actor_id, action, entity_type, entity_id, after_redacted)
    values (
      p_lab_id, auth.uid(), 'restore.patient', 'patient', p_id::text,
      jsonb_build_object('fields', jsonb_build_array('deleted_at'))
    );
  end if;
end;
$$;

create or replace function public.get_lab_trash(p_lab_id uuid)
returns table(item_id uuid, item_kind text, item_name text, archived_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_page_access(p_lab_id, 'trash_bin') then
    raise exception using errcode = '42501', message = 'Trash-bin access required';
  end if;
  return query
    select p.id, 'patient'::text, p.patient_code || ' · ' || p.full_name, p.deleted_at
    from public.patients p
    where p.lab_id = p_lab_id and p.deleted_at is not null
      and public.has_lab_permission(p_lab_id, 'patients.read')
    union all
    select s.id, 'test'::text, s.code || ' · ' || s.name, s.deleted_at
    from public.services s
    where s.lab_id = p_lab_id and s.deleted_at is not null
      and public.has_lab_permission(p_lab_id, 'services.read')
    union all
    select c.id, 'category'::text, c.name, c.deleted_at
    from public.service_categories c
    where c.lab_id = p_lab_id and c.deleted_at is not null
      and public.has_lab_permission(p_lab_id, 'services.read')
    union all
    select d.id, 'doctor'::text, d.full_name, d.deleted_at
    from public.referring_doctors d
    where d.lab_id = p_lab_id and d.deleted_at is not null
      and public.has_lab_permission(p_lab_id, 'doctors.read')
    union all
    select r.id, 'reagent'::text, r.name, r.deleted_at
    from public.reagent_stock r
    where r.lab_id = p_lab_id and r.deleted_at is not null
      and public.has_lab_permission(p_lab_id, 'inventory.read')
    union all
    select e.id, 'expense'::text, e.category || ' · ' || e.note, e.deleted_at
    from public.expenses e
    where e.lab_id = p_lab_id and e.deleted_at is not null
      and public.has_lab_permission(p_lab_id, 'expenses.read')
    order by archived_at desc;
end;
$$;

drop policy if exists report_results_lab_read on public.report_results;
create policy report_results_lab_read on public.report_results
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'reports.read')
    and public.has_order_item_access(lab_id, order_item_id)
  );

revoke insert, update, delete on public.visits, public.order_items, public.samples,
  public.invoices, public.invoice_items, public.payments, public.receipts
  from public, anon, authenticated;

revoke all on function public.create_lab_invoice(uuid, uuid, uuid[], numeric, text, numeric, text) from public, anon;
revoke all on function public.record_invoice_payment(uuid, uuid, numeric, text, text) from public, anon;
revoke all on function public.update_sample_status(uuid, uuid, text, text) from public, anon;
revoke all on function public.update_order_item_status(uuid, uuid, text) from public, anon;
revoke all on function public.assign_order_item(uuid, uuid, uuid, uuid) from public, anon;
revoke all on function public.save_report_result(uuid, uuid, text) from public, anon;
revoke all on function public.review_report_result(uuid, uuid, text) from public, anon;
revoke all on function public.publish_report_result(uuid, uuid, text) from public, anon;
revoke all on function public.get_lab_analytics(uuid, date, date) from public, anon;
revoke all on function public.set_staff_access(uuid, uuid, text, text[]) from public, anon;
revoke all on function public.get_lab_staff_access(uuid) from public, anon;
revoke all on function public.set_staff_active(uuid, uuid, boolean) from public, anon;
revoke all on function public.assign_invited_member(uuid, uuid, text, text[], text, text) from public, anon;
revoke all on function public.save_lab_settings(uuid, text, text, text, text, text, text, text, text, text) from public, anon;
revoke all on function public.create_print_request(uuid, uuid) from public, anon;
revoke all on function public.review_print_request(uuid, uuid, text, text) from public, anon;
revoke all on function public.archive_lab_item(uuid, text, uuid) from public, anon;
revoke all on function public.restore_lab_item(uuid, text, uuid) from public, anon;
revoke all on function public.get_lab_trash(uuid) from public, anon;
revoke all on function public.get_public_report(text) from public;
revoke all on function public.get_lab_sample_board(uuid) from public, anon;
revoke all on function public.get_lab_report_queue(uuid) from public, anon;
revoke all on function public.get_reportable_order_items(uuid) from public, anon;

grant execute on function public.create_lab_invoice(uuid, uuid, uuid[], numeric, text, numeric, text) to authenticated;
grant execute on function public.record_invoice_payment(uuid, uuid, numeric, text, text) to authenticated;
grant execute on function public.update_sample_status(uuid, uuid, text, text) to authenticated;
grant execute on function public.update_order_item_status(uuid, uuid, text) to authenticated;
grant execute on function public.assign_order_item(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.save_report_result(uuid, uuid, text) to authenticated;
grant execute on function public.review_report_result(uuid, uuid, text) to authenticated;
grant execute on function public.publish_report_result(uuid, uuid, text) to authenticated;
grant execute on function public.get_lab_analytics(uuid, date, date) to authenticated;
grant execute on function public.set_staff_access(uuid, uuid, text, text[]) to authenticated;
grant execute on function public.get_lab_staff_access(uuid) to authenticated;
grant execute on function public.set_staff_active(uuid, uuid, boolean) to authenticated;
grant execute on function public.assign_invited_member(uuid, uuid, text, text[], text, text) to authenticated;
grant execute on function public.save_lab_settings(uuid, text, text, text, text, text, text, text, text, text) to authenticated;
grant execute on function public.create_print_request(uuid, uuid) to authenticated;
grant execute on function public.review_print_request(uuid, uuid, text, text) to authenticated;
grant execute on function public.archive_lab_item(uuid, text, uuid) to authenticated;
grant execute on function public.restore_lab_item(uuid, text, uuid) to authenticated;
grant execute on function public.get_lab_trash(uuid) to authenticated;
grant execute on function public.get_public_report(text) to anon, authenticated;
grant execute on function public.get_lab_sample_board(uuid) to authenticated;
grant execute on function public.get_lab_report_queue(uuid) to authenticated;
grant execute on function public.get_reportable_order_items(uuid) to authenticated;
