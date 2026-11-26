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
    with trash_items as (
      select p.id as item_id, 'patient'::text as item_kind,
             p.patient_code || ' · ' || p.full_name as item_name, p.deleted_at as archived_at
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
    )
    select trash_items.item_id, trash_items.item_kind, trash_items.item_name, trash_items.archived_at
    from trash_items
    order by trash_items.archived_at desc;
end;
$$;

revoke all on function public.get_lab_trash(uuid) from public, anon;
grant execute on function public.get_lab_trash(uuid) to authenticated;
