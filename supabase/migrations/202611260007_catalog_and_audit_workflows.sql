alter table public.service_categories
  add column if not exists deleted_at timestamptz;

create or replace function public.audit_lab_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_row jsonb;
  new_row jsonb;
  changed_lab_id uuid;
  changed_id text;
  changed_action text;
begin
  if tg_op in ('UPDATE','DELETE') then
    old_row := to_jsonb(old);
  end if;
  if tg_op in ('INSERT','UPDATE') then
    new_row := to_jsonb(new);
  end if;

  changed_lab_id := coalesce(
    nullif(new_row ->> 'lab_id', '')::uuid,
    nullif(old_row ->> 'lab_id', '')::uuid
  );
  changed_id := coalesce(new_row ->> 'id', old_row ->> 'id');
  changed_action := lower(tg_op) || '.' || tg_table_name;

  insert into public.audit_logs (
    lab_id, actor_id, action, entity_type, entity_id, before_redacted, after_redacted
  )
  values (
    changed_lab_id,
    auth.uid(),
    changed_action,
    tg_table_name,
    changed_id,
    case when old_row is null then null else jsonb_build_object(
      'fields', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from jsonb_object_keys(old_row) as keys(k))
    ) end,
    case when new_row is null then null else jsonb_build_object(
      'fields', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from jsonb_object_keys(new_row) as keys(k))
    ) end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

do $$
declare
  target record;
begin
  for target in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'lab_id'
      and not a.attisdropped
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relname not in ('audit_logs','patients')
  loop
    execute format('drop trigger if exists audit_lab_row_change on public.%I', target.relname);
    execute format(
      'create trigger audit_lab_row_change after insert or update or delete on public.%I for each row execute function public.audit_lab_row_change()',
      target.relname
    );
  end loop;
end;
$$;

create or replace function public.save_lab_catalog_item(
  p_lab_id uuid,
  p_kind text,
  p_id uuid,
  p_values jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  required_permission text;
  saved_id uuid;
  item_name text;
  item_code text;
  item_category_id uuid;
  item_price numeric(12,2);
  item_quantity numeric(12,2);
  item_reorder_level numeric(12,2);
  item_unit_price numeric(12,2);
  item_commission numeric(5,2);
begin
  if auth.uid() is null or p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception using errcode = '22023', message = 'A signed-in user and valid item details are required';
  end if;

  required_permission := case p_kind
    when 'category' then 'services.manage'
    when 'test' then 'services.manage'
    when 'doctor' then 'doctors.manage'
    when 'reagent' then 'inventory.manage'
    when 'expense' then 'expenses.manage'
    else null
  end;
  if required_permission is null then
    raise exception using errcode = '22023', message = 'Unsupported catalog item type';
  end if;
  if not public.has_lab_permission(p_lab_id, required_permission) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage this item';
  end if;

  item_name := nullif(btrim(p_values ->> 'name'), '');

  if p_kind = 'category' then
    if item_name is null or length(item_name) > 80 then
      raise exception using errcode = '22023', message = 'Category name must be between 1 and 80 characters';
    end if;
    if p_id is null then
      insert into public.service_categories(lab_id, name, sort_order)
      values (p_lab_id, item_name, coalesce(nullif(p_values ->> 'sort_order', '')::integer, 0))
      returning id into saved_id;
    else
      update public.service_categories
      set name = item_name,
          sort_order = coalesce(nullif(p_values ->> 'sort_order', '')::integer, sort_order),
          updated_at = now()
      where id = p_id and lab_id = p_lab_id and deleted_at is null
      returning id into saved_id;
    end if;

  elsif p_kind = 'test' then
    item_code := upper(nullif(btrim(p_values ->> 'code'), ''));
    item_category_id := nullif(p_values ->> 'category_id', '')::uuid;
    item_price := coalesce(nullif(p_values ->> 'price', '')::numeric, 0);
    if item_name is null or length(item_name) > 120
      or item_code is null or item_code !~ '^[A-Z0-9_-]{1,32}$'
      or item_price < 0
      or coalesce(nullif(p_values ->> 'service_type', ''), 'laboratory')
        not in ('laboratory','xray','ultrasound','ecg','other') then
      raise exception using errcode = '22023', message = 'Test name, code, or price is invalid';
    end if;
    if item_category_id is not null and not exists (
      select 1 from public.service_categories c
      where c.id = item_category_id and c.lab_id = p_lab_id and c.deleted_at is null
    ) then
      raise exception using errcode = '22023', message = 'Select a category from this laboratory';
    end if;
    if p_id is null then
      insert into public.services(
        lab_id, category_id, code, name, description, service_type, price,
        duration_minutes, turnaround_minutes, preparation_instructions,
        fasting_required, method, normal_range, active, patient_visible
      )
      values (
        p_lab_id, item_category_id, item_code, item_name,
        nullif(btrim(p_values ->> 'description'), ''),
        coalesce(nullif(p_values ->> 'service_type', ''), 'laboratory'),
        item_price,
        coalesce(nullif(p_values ->> 'duration_minutes', '')::integer, 15),
        nullif(p_values ->> 'turnaround_minutes', '')::integer,
        nullif(btrim(p_values ->> 'preparation_instructions'), ''),
        coalesce(nullif(p_values ->> 'fasting_required', '')::boolean, false),
        nullif(btrim(p_values ->> 'method'), ''),
        nullif(btrim(p_values ->> 'normal_range'), ''),
        true,
        coalesce(nullif(p_values ->> 'patient_visible', '')::boolean, true)
      )
      returning id into saved_id;
    else
      update public.services
      set category_id = item_category_id,
          code = item_code,
          name = item_name,
          description = nullif(btrim(p_values ->> 'description'), ''),
          service_type = coalesce(nullif(p_values ->> 'service_type', ''), service_type),
          price = item_price,
          duration_minutes = coalesce(nullif(p_values ->> 'duration_minutes', '')::integer, duration_minutes),
          turnaround_minutes = nullif(p_values ->> 'turnaround_minutes', '')::integer,
          preparation_instructions = nullif(btrim(p_values ->> 'preparation_instructions'), ''),
          fasting_required = coalesce(nullif(p_values ->> 'fasting_required', '')::boolean, false),
          method = nullif(btrim(p_values ->> 'method'), ''),
          normal_range = nullif(btrim(p_values ->> 'normal_range'), ''),
          patient_visible = coalesce(nullif(p_values ->> 'patient_visible', '')::boolean, patient_visible),
          updated_at = now()
      where id = p_id and lab_id = p_lab_id and deleted_at is null
      returning id into saved_id;
    end if;

  elsif p_kind = 'doctor' then
    item_commission := coalesce(nullif(p_values ->> 'commission_percent', '')::numeric, 0);
    if item_name is null or length(item_name) > 120
      or item_commission < 0 or item_commission > 100 then
      raise exception using errcode = '22023', message = 'Doctor name or commission is invalid';
    end if;
    if p_id is null then
      insert into public.referring_doctors(
        lab_id, full_name, clinic, phone, email, specialty, commission_percent, address
      )
      values (
        p_lab_id, item_name, nullif(btrim(p_values ->> 'clinic'), ''),
        nullif(btrim(p_values ->> 'phone'), ''), nullif(btrim(p_values ->> 'email'), ''),
        nullif(btrim(p_values ->> 'specialty'), ''), item_commission,
        nullif(btrim(p_values ->> 'address'), '')
      )
      returning id into saved_id;
    else
      update public.referring_doctors
      set full_name = item_name,
          clinic = nullif(btrim(p_values ->> 'clinic'), ''),
          phone = nullif(btrim(p_values ->> 'phone'), ''),
          email = nullif(btrim(p_values ->> 'email'), ''),
          specialty = nullif(btrim(p_values ->> 'specialty'), ''),
          commission_percent = item_commission,
          address = nullif(btrim(p_values ->> 'address'), ''),
          updated_at = now()
      where id = p_id and lab_id = p_lab_id and deleted_at is null
      returning id into saved_id;
    end if;

  elsif p_kind = 'reagent' then
    item_quantity := coalesce(nullif(p_values ->> 'quantity', '')::numeric, 0);
    item_reorder_level := coalesce(nullif(p_values ->> 'reorder_level', '')::numeric, 0);
    item_unit_price := coalesce(nullif(p_values ->> 'unit_price', '')::numeric, 0);
    if item_name is null or length(item_name) > 120
      or item_quantity < 0 or item_reorder_level < 0 or item_unit_price < 0 then
      raise exception using errcode = '22023', message = 'Reagent details are invalid';
    end if;
    if p_id is null then
      insert into public.reagent_stock(
        lab_id, name, quantity, reorder_level, expiry_date, supplier,
        batch_number, unit_price, storage
      )
      values (
        p_lab_id, item_name, item_quantity, item_reorder_level,
        nullif(p_values ->> 'expiry_date', '')::date,
        nullif(btrim(p_values ->> 'supplier'), ''),
        nullif(btrim(p_values ->> 'batch_number'), ''),
        item_unit_price, nullif(btrim(p_values ->> 'storage'), '')
      )
      returning id into saved_id;
    else
      update public.reagent_stock
      set name = item_name,
          quantity = item_quantity,
          reorder_level = item_reorder_level,
          expiry_date = nullif(p_values ->> 'expiry_date', '')::date,
          supplier = nullif(btrim(p_values ->> 'supplier'), ''),
          batch_number = nullif(btrim(p_values ->> 'batch_number'), ''),
          unit_price = item_unit_price,
          storage = nullif(btrim(p_values ->> 'storage'), ''),
          updated_at = now()
      where id = p_id and lab_id = p_lab_id and deleted_at is null
      returning id into saved_id;
    end if;

  else
    if item_name is null or length(item_name) > 80 then
      raise exception using errcode = '22023', message = 'Expense category is required';
    end if;
    if p_values ->> 'note' is null or length(btrim(p_values ->> 'note')) not between 2 and 500 then
      raise exception using errcode = '22023', message = 'Expense note must be between 2 and 500 characters';
    end if;
    if p_id is null then
      insert into public.expenses(
        lab_id, expense_date, category, note, amount, paid_via, receipt_number, created_by
      )
      values (
        p_lab_id, coalesce(nullif(p_values ->> 'expense_date', '')::date, current_date),
        item_name, btrim(p_values ->> 'note'),
        nullif(p_values ->> 'amount', '')::numeric,
        coalesce(nullif(p_values ->> 'paid_via', ''), 'cash'),
        nullif(btrim(p_values ->> 'receipt_number'), ''), auth.uid()
      )
      returning id into saved_id;
    else
      update public.expenses
      set expense_date = coalesce(nullif(p_values ->> 'expense_date', '')::date, expense_date),
          category = item_name,
          note = btrim(p_values ->> 'note'),
          amount = nullif(p_values ->> 'amount', '')::numeric,
          paid_via = coalesce(nullif(p_values ->> 'paid_via', ''), paid_via),
          receipt_number = nullif(btrim(p_values ->> 'receipt_number'), ''),
          updated_at = now()
      where id = p_id and lab_id = p_lab_id and deleted_at is null
      returning id into saved_id;
    end if;
  end if;

  if saved_id is null then
    raise exception using errcode = 'P0002', message = 'The item was not found or is archived';
  end if;
  return saved_id;
end;
$$;

revoke all on function public.audit_lab_row_change() from public, anon, authenticated;
revoke all on function public.save_lab_catalog_item(uuid, text, uuid, jsonb) from public, anon;
grant execute on function public.save_lab_catalog_item(uuid, text, uuid, jsonb) to authenticated;

revoke insert, update, delete on public.service_categories, public.services
  from public, anon, authenticated;
