create table if not exists public.reagent_stock_movements (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  reagent_id uuid not null,
  movement_type text not null check (movement_type in (
    'received','used','adjustment_increase','adjustment_decrease'
  )),
  quantity_delta numeric(12,2) not null check (quantity_delta <> 0),
  quantity_before numeric(12,2) not null check (quantity_before >= 0),
  quantity_after numeric(12,2) not null check (quantity_after >= 0),
  note text not null check (length(btrim(note)) between 2 and 240),
  reference text check (reference is null or length(reference) <= 80),
  created_by uuid references auth.users(id),
  transaction_id bigint not null default txid_current(),
  created_at timestamptz not null default now(),
  foreign key (reagent_id, lab_id)
    references public.reagent_stock(id, lab_id) on delete restrict,
  check (quantity_after = quantity_before + quantity_delta),
  check (
    (movement_type in ('received','adjustment_increase') and quantity_delta > 0)
    or (movement_type in ('used','adjustment_decrease') and quantity_delta < 0)
  )
);

create index if not exists reagent_stock_movements_lab_created_idx
  on public.reagent_stock_movements(lab_id, created_at desc);
create index if not exists reagent_stock_movements_reagent_created_idx
  on public.reagent_stock_movements(reagent_id, created_at desc);

alter table public.reagent_stock_movements enable row level security;
drop policy if exists reagent_stock_movements_lab_read on public.reagent_stock_movements;
create policy reagent_stock_movements_lab_read on public.reagent_stock_movements
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'inventory.read')
  );
grant select on public.reagent_stock_movements to authenticated;
revoke insert, update, delete on public.reagent_stock_movements from public, anon, authenticated;

create or replace function public.require_reagent_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.quantity is not distinct from old.quantity then
    return new;
  end if;
  if tg_op = 'INSERT' and new.quantity = 0 then
    return new;
  end if;

  if not exists (
    select 1
    from public.reagent_stock_movements movement
    where movement.lab_id = new.lab_id
      and movement.reagent_id = new.id
      and movement.transaction_id = txid_current()
      and movement.quantity_after = new.quantity
  ) then
    raise exception using
      errcode = '23514',
      message = 'Stock quantity changes must include a matching inventory movement';
  end if;
  return new;
end;
$$;

drop trigger if exists reagent_stock_quantity_movement_guard on public.reagent_stock;
create trigger reagent_stock_quantity_movement_guard
  after insert or update of quantity on public.reagent_stock
  for each row execute function public.require_reagent_stock_movement();

drop trigger if exists audit_lab_row_change on public.reagent_stock_movements;
create trigger audit_lab_row_change
  after insert or update or delete on public.reagent_stock_movements
  for each row execute function public.audit_lab_row_change();

create or replace function public.save_lab_reagent(
  p_lab_id uuid,
  p_id uuid,
  p_values jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  reagent_name text;
  saved_id uuid;
  item_reorder_level numeric(12,2);
  item_unit_price numeric(12,2);
  expiry date;
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'inventory.manage') then
    raise exception using errcode = '42501', message = 'Inventory management permission required';
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception using errcode = '22023', message = 'Valid reagent details are required';
  end if;

  reagent_name := nullif(btrim(p_values ->> 'name'), '');
  item_reorder_level := coalesce(nullif(p_values ->> 'reorder_level', '')::numeric, 0);
  item_unit_price := coalesce(nullif(p_values ->> 'unit_price', '')::numeric, 0);
  expiry := nullif(p_values ->> 'expiry_date', '')::date;
  if reagent_name is null or length(reagent_name) > 120
    or item_reorder_level < 0 or item_unit_price < 0 then
    raise exception using errcode = '22023', message = 'Reagent details are invalid';
  end if;

  if p_id is null then
    insert into public.reagent_stock(
      lab_id, name, quantity, reorder_level, expiry_date, supplier,
      batch_number, unit_price, storage
    )
    values (
      p_lab_id, reagent_name, 0, item_reorder_level, expiry,
      nullif(btrim(p_values ->> 'supplier'), ''),
      nullif(btrim(p_values ->> 'batch_number'), ''),
      item_unit_price,
      nullif(btrim(p_values ->> 'storage'), '')
    )
    returning id into saved_id;
  else
    update public.reagent_stock
    set name = reagent_name,
        reorder_level = item_reorder_level,
        expiry_date = expiry,
        supplier = nullif(btrim(p_values ->> 'supplier'), ''),
        batch_number = nullif(btrim(p_values ->> 'batch_number'), ''),
        unit_price = item_unit_price,
        storage = nullif(btrim(p_values ->> 'storage'), ''),
        updated_at = now()
    where id = p_id and lab_id = p_lab_id and deleted_at is null
    returning id into saved_id;
  end if;

  if saved_id is null then
    raise exception using errcode = 'P0002', message = 'Reagent not found in this laboratory';
  end if;
  return saved_id;
end;
$$;

create or replace function public.record_lab_reagent_movement(
  p_lab_id uuid,
  p_reagent_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_note text,
  p_reference text default null
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_quantity numeric(12,2);
  quantity_delta numeric(12,2);
  next_quantity numeric(12,2);
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'inventory.manage') then
    raise exception using errcode = '42501', message = 'Inventory management permission required';
  end if;
  if p_movement_type is null
    or p_movement_type not in ('received','used','adjustment_increase','adjustment_decrease')
    or p_quantity is null or p_quantity <= 0 or p_quantity <> round(p_quantity, 2)
    or p_note is null or length(btrim(p_note)) not between 2 and 240
    or length(coalesce(p_reference, '')) > 80 then
    raise exception using errcode = '22023', message = 'Inventory movement details are invalid';
  end if;

  select reagent.quantity into current_quantity
  from public.reagent_stock reagent
  where reagent.id = p_reagent_id
    and reagent.lab_id = p_lab_id
    and reagent.deleted_at is null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Active reagent not found in this laboratory';
  end if;

  quantity_delta := case
    when p_movement_type in ('received','adjustment_increase') then p_quantity
    else -p_quantity
  end;
  next_quantity := current_quantity + quantity_delta;
  if next_quantity < 0 then
    raise exception using errcode = '23514', message = 'Stock movement would make the quantity negative';
  end if;

  insert into public.reagent_stock_movements(
    lab_id, reagent_id, movement_type, quantity_delta,
    quantity_before, quantity_after, note, reference, created_by, transaction_id
  )
  values (
    p_lab_id, p_reagent_id, p_movement_type, quantity_delta,
    current_quantity, next_quantity, btrim(p_note),
    nullif(btrim(p_reference), ''), auth.uid(), txid_current()
  );
  update public.reagent_stock
  set quantity = next_quantity, updated_at = now()
  where id = p_reagent_id and lab_id = p_lab_id;

  return next_quantity;
end;
$$;

create or replace function public.get_lab_reagent_movements(
  p_lab_id uuid,
  p_reagent_id uuid default null,
  p_limit integer default 200
)
returns table(
  movement_id uuid,
  reagent_id uuid,
  reagent_name text,
  movement_type text,
  quantity_delta numeric,
  quantity_before numeric,
  quantity_after numeric,
  note text,
  reference text,
  created_by_name text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_lab_permission(p_lab_id, 'inventory.read') then
    raise exception using errcode = '42501', message = 'Inventory read permission required';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception using errcode = '22023', message = 'Movement history limit must be between 1 and 500';
  end if;
  if p_reagent_id is not null and not exists (
    select 1 from public.reagent_stock reagent
    where reagent.id = p_reagent_id and reagent.lab_id = p_lab_id
  ) then
    raise exception using errcode = '22023', message = 'Reagent does not belong to this laboratory';
  end if;

  return query
    select movement.id, movement.reagent_id, reagent.name,
      movement.movement_type, movement.quantity_delta, movement.quantity_before,
      movement.quantity_after, movement.note, movement.reference,
      coalesce(profile.full_name, ''), movement.created_at
    from public.reagent_stock_movements movement
    join public.reagent_stock reagent
      on reagent.id = movement.reagent_id and reagent.lab_id = movement.lab_id
    left join public.profiles profile on profile.id = movement.created_by
    where movement.lab_id = p_lab_id
      and (p_reagent_id is null or movement.reagent_id = p_reagent_id)
    order by movement.created_at desc, movement.id desc
    limit p_limit;
end;
$$;

revoke all on function public.require_reagent_stock_movement() from public, anon, authenticated;
revoke all on function public.save_lab_reagent(uuid, uuid, jsonb) from public, anon;
revoke all on function public.record_lab_reagent_movement(uuid, uuid, text, numeric, text, text) from public, anon;
revoke all on function public.get_lab_reagent_movements(uuid, uuid, integer) from public, anon;
grant execute on function public.save_lab_reagent(uuid, uuid, jsonb) to authenticated;
grant execute on function public.record_lab_reagent_movement(uuid, uuid, text, numeric, text, text) to authenticated;
grant execute on function public.get_lab_reagent_movements(uuid, uuid, integer) to authenticated;
