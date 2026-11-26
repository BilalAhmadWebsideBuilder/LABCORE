create or replace function public.get_lab_invoice_print(
  p_lab_id uuid,
  p_invoice_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  print_data jsonb;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'billing.read') then
    raise exception using errcode = '42501', message = 'Invoice access permission required';
  end if;

  select jsonb_build_object(
    'laboratory', jsonb_build_object(
      'name', l.name,
      'city', l.city,
      'address', l.address,
      'phone', l.phone,
      'email', l.email,
      'receipt_format', l.receipt_format,
      'receipt_footer', l.receipt_footer,
      'timezone', settings.timezone
    ),
    'patient', jsonb_build_object(
      'full_name', patient.full_name,
      'patient_code', patient.patient_code
    ),
    'invoice', jsonb_build_object(
      'invoice_number', i.invoice_number,
      'currency', trim(i.currency),
      'subtotal', i.subtotal,
      'discount', i.discount,
      'tax', i.tax,
      'total', i.total,
      'status', i.status,
      'created_at', i.created_at
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'description', item.description,
        'quantity', item.quantity,
        'unit_price', item.unit_price,
        'line_total', item.line_total
      ) order by item.created_at, item.id)
      from public.invoice_items item
      where item.lab_id = i.lab_id and item.invoice_id = i.id
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'amount', payment.amount,
        'method', payment.method,
        'received_at', payment.received_at,
        'receipt_number', receipt.receipt_number
      ) order by payment.received_at, payment.id)
      from public.payments payment
      left join public.receipts receipt
        on receipt.lab_id = payment.lab_id and receipt.payment_id = payment.id
      where payment.lab_id = i.lab_id
        and payment.invoice_id = i.id
        and payment.voided_at is null
    ), '[]'::jsonb)
  )
  into print_data
  from public.invoices i
  join public.labs l on l.id = i.lab_id
  join public.patients patient on patient.id = i.patient_id and patient.lab_id = i.lab_id
  left join public.lab_settings settings on settings.lab_id = i.lab_id
  where i.id = p_invoice_id and i.lab_id = p_lab_id;

  return print_data;
end;
$$;

create or replace function public.get_lab_report_print(
  p_lab_id uuid,
  p_report_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  print_data jsonb;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'reports.read') then
    raise exception using errcode = '42501', message = 'Report access permission required';
  end if;

  select jsonb_build_object(
    'laboratory', jsonb_build_object(
      'name', l.name,
      'city', l.city,
      'address', l.address,
      'phone', l.phone,
      'email', l.email,
      'timezone', settings.timezone
    ),
    'patient', jsonb_build_object(
      'full_name', patient.full_name,
      'patient_code', patient.patient_code
    ),
    'test', jsonb_build_object(
      'name', service.name,
      'method', service.method,
      'normal_range', service.normal_range
    ),
    'report', jsonb_build_object(
      'result_text', result.result_text,
      'published_at', result.published_at
    )
  )
  into print_data
  from public.report_results result
  join public.labs l on l.id = result.lab_id
  join public.patients patient on patient.id = result.patient_id and patient.lab_id = result.lab_id
  join public.order_items order_item on order_item.id = result.order_item_id and order_item.lab_id = result.lab_id
  join public.services service on service.id = order_item.service_id and service.lab_id = order_item.lab_id
  left join public.lab_settings settings on settings.lab_id = result.lab_id
  where result.id = p_report_result_id
    and result.lab_id = p_lab_id
    and result.status = 'published'
    and public.has_order_item_access(p_lab_id, order_item.id);

  return print_data;
end;
$$;

revoke all on function public.get_lab_invoice_print(uuid, uuid) from public, anon;
revoke all on function public.get_lab_report_print(uuid, uuid) from public, anon;
grant execute on function public.get_lab_invoice_print(uuid, uuid) to authenticated;
grant execute on function public.get_lab_report_print(uuid, uuid) to authenticated;
