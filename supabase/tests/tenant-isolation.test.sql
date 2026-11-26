begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

do $$
declare
  setting_name text;
begin
  foreach setting_name in array array[
    'labcore_test.run_id', 'labcore_test.lab_a', 'labcore_test.lab_b',
    'labcore_test.staff_a', 'labcore_test.staff_b',
    'labcore_test.patient_user_a', 'labcore_test.patient_user_b',
    'labcore_test.patient_a', 'labcore_test.patient_b',
    'labcore_test.service_a', 'labcore_test.service_b',
    'labcore_test.visit_a', 'labcore_test.visit_b', 'labcore_test.visit_a_draft',
    'labcore_test.order_a', 'labcore_test.order_b', 'labcore_test.order_a_draft',
    'labcore_test.result_a', 'labcore_test.result_b', 'labcore_test.result_a_draft'
  ] loop
    perform set_config(setting_name, gen_random_uuid()::text, true);
  end loop;
end;
$$;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
select current_setting(setting_name)::uuid, 'authenticated', 'authenticated',
  current_setting(setting_name) || '@labcore-test.invalid', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', label), now(), now()
from (values
  ('labcore_test.staff_a', 'Tenant Test Staff A'),
  ('labcore_test.staff_b', 'Tenant Test Staff B'),
  ('labcore_test.patient_user_a', 'Tenant Test Patient A'),
  ('labcore_test.patient_user_b', 'Tenant Test Patient B')
) as test_users(setting_name, label);

insert into public.labs(id, name, slug)
values
  (current_setting('labcore_test.lab_a')::uuid, 'Tenant Isolation Test A',
    'tenant-test-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12) || '-a'),
  (current_setting('labcore_test.lab_b')::uuid, 'Tenant Isolation Test B',
    'tenant-test-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12) || '-b');

insert into public.memberships(lab_id, user_id, role, active)
values
  (current_setting('labcore_test.lab_a')::uuid, current_setting('labcore_test.staff_a')::uuid, 'lab_admin', true),
  (current_setting('labcore_test.lab_b')::uuid, current_setting('labcore_test.staff_b')::uuid, 'lab_admin', true);

insert into public.patients(id, lab_id, patient_code, full_name, phone)
values
  (current_setting('labcore_test.patient_a')::uuid, current_setting('labcore_test.lab_a')::uuid,
    'TEST-A-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12), 'Fictional Patient A', '+15550001001'),
  (current_setting('labcore_test.patient_b')::uuid, current_setting('labcore_test.lab_b')::uuid,
    'TEST-B-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12), 'Fictional Patient B', '+15550001002');

insert into public.patient_accounts(lab_id, patient_id, user_id, activated_at)
values
  (current_setting('labcore_test.lab_a')::uuid, current_setting('labcore_test.patient_a')::uuid,
    current_setting('labcore_test.patient_user_a')::uuid, now()),
  (current_setting('labcore_test.lab_b')::uuid, current_setting('labcore_test.patient_b')::uuid,
    current_setting('labcore_test.patient_user_b')::uuid, now());

insert into public.services(id, lab_id, code, name, price)
values
  (current_setting('labcore_test.service_a')::uuid, current_setting('labcore_test.lab_a')::uuid,
    'TEST-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12) || '-A', 'Fictional Panel A', 0),
  (current_setting('labcore_test.service_b')::uuid, current_setting('labcore_test.lab_b')::uuid,
    'TEST-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12) || '-B', 'Fictional Panel B', 0);

insert into public.visits(id, lab_id, patient_id, visit_code)
values
  (current_setting('labcore_test.visit_a')::uuid, current_setting('labcore_test.lab_a')::uuid,
    current_setting('labcore_test.patient_a')::uuid, 'TENANT-A-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12)),
  (current_setting('labcore_test.visit_b')::uuid, current_setting('labcore_test.lab_b')::uuid,
    current_setting('labcore_test.patient_b')::uuid, 'TENANT-B-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12)),
  (current_setting('labcore_test.visit_a_draft')::uuid, current_setting('labcore_test.lab_a')::uuid,
    current_setting('labcore_test.patient_a')::uuid, 'TENANT-A-DRAFT-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12));

insert into public.order_items(id, lab_id, visit_id, service_id, price)
values
  (current_setting('labcore_test.order_a')::uuid, current_setting('labcore_test.lab_a')::uuid,
    current_setting('labcore_test.visit_a')::uuid, current_setting('labcore_test.service_a')::uuid, 0),
  (current_setting('labcore_test.order_b')::uuid, current_setting('labcore_test.lab_b')::uuid,
    current_setting('labcore_test.visit_b')::uuid, current_setting('labcore_test.service_b')::uuid, 0),
  (current_setting('labcore_test.order_a_draft')::uuid, current_setting('labcore_test.lab_a')::uuid,
    current_setting('labcore_test.visit_a_draft')::uuid, current_setting('labcore_test.service_a')::uuid, 0);

insert into public.report_results(
  id, lab_id, patient_id, order_item_id, result_text, status, published_at
)
values
  (current_setting('labcore_test.result_a')::uuid, current_setting('labcore_test.lab_a')::uuid,
    current_setting('labcore_test.patient_a')::uuid, current_setting('labcore_test.order_a')::uuid,
    'Fictional result A', 'published', now()),
  (current_setting('labcore_test.result_b')::uuid, current_setting('labcore_test.lab_b')::uuid,
    current_setting('labcore_test.patient_b')::uuid, current_setting('labcore_test.order_b')::uuid,
    'Fictional result B', 'published', now()),
  (current_setting('labcore_test.result_a_draft')::uuid, current_setting('labcore_test.lab_a')::uuid,
    current_setting('labcore_test.patient_a')::uuid, current_setting('labcore_test.order_a_draft')::uuid,
    'Unpublished fictional result', 'entered', null);

set local role authenticated;
do $$
begin
  perform set_config('request.jwt.claim.sub', current_setting('labcore_test.staff_a'), true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('labcore_test.staff_a'), 'role', 'authenticated')::text, true);
end;
$$;

select is(
  (select count(*)::integer from public.labs
   where id in (current_setting('labcore_test.lab_a')::uuid, current_setting('labcore_test.lab_b')::uuid)),
  1, 'Lab A staff can read only its own lab metadata'
);
select is(
  (select count(*)::integer from public.patients
   where id in (current_setting('labcore_test.patient_a')::uuid, current_setting('labcore_test.patient_b')::uuid)),
  1, 'Lab A staff can read only its own tenant patient'
);
select is(
  (select count(*)::integer from public.patients
   where id = current_setting('labcore_test.patient_b')::uuid),
  0, 'Lab A staff cannot read Lab B patient data'
);
select throws_ok(
  $sql$
    insert into public.patients(id, lab_id, patient_code, full_name)
    values (
      gen_random_uuid(),
      current_setting('labcore_test.lab_b')::uuid,
      'FORBIDDEN-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12),
      'Forbidden Cross-Tenant Patient'
    )
  $sql$,
  '42501',
  null,
  'Lab A staff cannot insert a patient into Lab B'
);
select throws_ok(
  $sql$
    insert into public.report_results(
      id, lab_id, patient_id, order_item_id, result_text, status, published_at
    )
    values (
      gen_random_uuid(),
      current_setting('labcore_test.lab_b')::uuid,
      current_setting('labcore_test.patient_b')::uuid,
      current_setting('labcore_test.order_b')::uuid,
      'Forbidden cross-tenant report',
      'published',
      now()
    )
  $sql$,
  '42501',
  null,
  'Lab A staff cannot insert a report into Lab B'
);

do $$
begin
  perform set_config('request.jwt.claim.sub', current_setting('labcore_test.staff_b'), true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('labcore_test.staff_b'), 'role', 'authenticated')::text, true);
end;
$$;

select is(
  (select count(*)::integer from public.patients
   where id = current_setting('labcore_test.patient_a')::uuid),
  0, 'Lab B staff cannot read Lab A patient data'
);
select throws_ok(
  $sql$
    insert into public.patients(id, lab_id, patient_code, full_name)
    values (
      gen_random_uuid(),
      current_setting('labcore_test.lab_a')::uuid,
      'FORBIDDEN-' || left(replace(current_setting('labcore_test.run_id'), '-', ''), 12),
      'Forbidden Reverse-Tenant Patient'
    )
  $sql$,
  '42501',
  null,
  'Lab B staff cannot insert a patient into Lab A'
);

do $$
begin
  perform set_config('request.jwt.claim.sub', current_setting('labcore_test.patient_user_a'), true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('labcore_test.patient_user_a'), 'role', 'authenticated')::text, true);
end;
$$;

select is(
  (select count(*)::integer from public.patients
   where id in (current_setting('labcore_test.patient_a')::uuid, current_setting('labcore_test.patient_b')::uuid)),
  1, 'Patient A can read only their own patient row'
);
select is(
  (select count(*)::integer from public.patients
   where id = current_setting('labcore_test.patient_b')::uuid),
  0, 'Patient A cannot read Patient B data'
);
select is(
  (select count(*)::integer from public.get_my_patient_reports()),
  1, 'Patient A receives only their published report'
);
select is(
  (select count(*)::integer from public.get_my_patient_reports()
   where report_id = current_setting('labcore_test.result_a_draft')::uuid),
  0, 'Patient A cannot see an unpublished result'
);
select is(
  (select count(*)::integer from public.get_my_patient_reports()
   where report_id = current_setting('labcore_test.result_b')::uuid),
  0, 'Patient A cannot see Lab B report data'
);

do $$
begin
  perform set_config('request.jwt.claim.sub', current_setting('labcore_test.patient_user_b'), true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('labcore_test.patient_user_b'), 'role', 'authenticated')::text, true);
end;
$$;

select is(
  (select count(*)::integer from public.get_my_patient_reports()),
  1, 'Patient B receives only their published report'
);
select is(
  (select count(*)::integer from public.get_my_patient_reports()
   where report_id = current_setting('labcore_test.result_a')::uuid),
  0, 'Patient B cannot see Lab A report data'
);

select * from finish();
rollback;
