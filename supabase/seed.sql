-- Synthetic development fixtures only. Never run this seed in production.
insert into public.labs (id, name, slug, status)
values
  ('10000000-0000-4000-8000-000000000001', 'Demo Central Diagnostics', 'demo-central', 'active'),
  ('20000000-0000-4000-8000-000000000002', 'Demo North Laboratory', 'demo-north', 'active')
on conflict (id) do update
set name = excluded.name, slug = excluded.slug, status = excluded.status;

insert into public.lab_settings (lab_id, currency, timezone, patient_code_prefix, invoice_code_prefix)
values
  ('10000000-0000-4000-8000-000000000001', 'PKR', 'Asia/Karachi', 'LN', 'INV'),
  ('20000000-0000-4000-8000-000000000002', 'USD', 'America/New_York', 'NL', 'NINV')
on conflict (lab_id) do nothing;

insert into public.service_categories (id, lab_id, name)
values
  ('10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'Pathology'),
  ('10000000-0000-4000-8000-000000000012', '10000000-0000-4000-8000-000000000001', 'Imaging'),
  ('20000000-0000-4000-8000-000000000021', '20000000-0000-4000-8000-000000000002', 'Laboratory'),
  ('20000000-0000-4000-8000-000000000022', '20000000-0000-4000-8000-000000000002', 'Imaging')
on conflict (id) do nothing;

insert into public.services (id, lab_id, category_id, code, name, service_type, price, duration_minutes, turnaround_minutes, preparation_instructions)
values
  ('10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000011', 'CBC', 'Complete Blood Count', 'laboratory', 1200, 10, 360, null),
  ('10000000-0000-4000-8000-000000000102', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000011', 'LIPID', 'Lipid Profile', 'laboratory', 2500, 15, 720, 'Fast for 9–12 hours before collection.'),
  ('10000000-0000-4000-8000-000000000103', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000011', 'HBA1C', 'HbA1c', 'laboratory', 1800, 10, 720, null),
  ('10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000012', 'XR-CHEST', 'Chest X-ray', 'xray', 3000, 20, 240, null),
  ('10000000-0000-4000-8000-000000000105', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000012', 'ECG', '12-lead ECG', 'ecg', 2000, 15, 120, null),
  ('20000000-0000-4000-8000-000000000201', '20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000021', 'CBC', 'Complete Blood Count', 'laboratory', 35, 10, 360, null),
  ('20000000-0000-4000-8000-000000000202', '20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000021', 'LIPID', 'Lipid Profile', 'laboratory', 55, 15, 720, 'Fast for 9–12 hours before collection.'),
  ('20000000-0000-4000-8000-000000000203', '20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000021', 'HBA1C', 'HbA1c', 'laboratory', 45, 10, 720, null),
  ('20000000-0000-4000-8000-000000000204', '20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000022', 'XR-CHEST', 'Chest X-ray', 'xray', 80, 20, 240, null),
  ('20000000-0000-4000-8000-000000000205', '20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000022', 'ECG', '12-lead ECG', 'ecg', 60, 15, 120, null)
on conflict (id) do nothing;

insert into public.resources (id, lab_id, name, resource_type)
values
  ('10000000-0000-4000-8000-000000000301', '10000000-0000-4000-8000-000000000001', 'Collection Room 1', 'collection_room'),
  ('10000000-0000-4000-8000-000000000302', '10000000-0000-4000-8000-000000000001', 'X-ray Room', 'xray'),
  ('20000000-0000-4000-8000-000000000401', '20000000-0000-4000-8000-000000000002', 'Collection Room 1', 'collection_room'),
  ('20000000-0000-4000-8000-000000000402', '20000000-0000-4000-8000-000000000002', 'X-ray Room', 'xray')
on conflict (id) do nothing;

insert into public.working_hours (lab_id, weekday, opens_at, closes_at, closed)
select labs.id, weekdays.day, time '08:00', time '17:00', weekdays.day = 0
from public.labs
cross join generate_series(0, 6) as weekdays(day)
where labs.id in (
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000002'
)
on conflict (lab_id, weekday) do nothing;

insert into public.patients (id, lab_id, patient_code, full_name, phone)
values
  ('10000000-0000-4000-8000-000000000501', '10000000-0000-4000-8000-000000000001', 'LN-2026-000001', 'Demo Patient One', '+15550000101'),
  ('20000000-0000-4000-8000-000000000601', '20000000-0000-4000-8000-000000000002', 'NL-2026-000001', 'Demo Patient Two', '+15550000102')
on conflict (id) do nothing;

insert into public.patient_code_counters (lab_id, code_year, last_value)
values
  ('10000000-0000-4000-8000-000000000001', 2026, 1),
  ('20000000-0000-4000-8000-000000000002', 2026, 1)
on conflict (lab_id, code_year) do update
set last_value = greatest(public.patient_code_counters.last_value, excluded.last_value);
