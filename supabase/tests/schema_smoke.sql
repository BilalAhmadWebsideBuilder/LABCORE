do $$
declare
  missing_tables text;
begin
  select string_agg(required.table_name, ', ' order by required.table_name)
  into missing_tables
  from (values
    ('labs'), ('profiles'), ('memberships'), ('patients'), ('patient_accounts'),
    ('patient_contacts'), ('patient_notes'), ('lab_settings'), ('lab_branding'),
    ('permission_catalog'), ('role_default_permissions'), ('roles_permissions'),
    ('service_categories'), ('services'), ('service_packages'), ('service_package_items'),
    ('resources'), ('working_hours'), ('holidays_closures'), ('staff_shifts'),
    ('staff_bookings'), ('appointments'), ('resource_bookings'), ('slot_holds'),
    ('visits'), ('order_items'), ('samples'), ('patient_code_counters'),
    ('invoice_counters'), ('invoices'), ('invoice_items'), ('payments'), ('receipts'),
    ('reports'), ('report_versions'), ('report_reviews'), ('report_publications'),
    ('role_default_page_grants'), ('page_grants'), ('referring_doctors'),
    ('reagent_stock'), ('expenses'), ('print_requests'), ('report_results'),
    ('reagent_stock_movements'),
    ('report_result_files'),
    ('report_result_links'),
    ('portal_tokens'), ('notifications'), ('notification_preferences'), ('plans'),
    ('subscriptions'), ('feature_flags'), ('export_jobs'), ('support_access_grants'),
    ('notification_templates'), ('notification_deliveries'), ('credit_notes'),
    ('retention_settings'), ('external_doctor_links'), ('audit_logs')
  ) as required(table_name)
  left join pg_namespace n on n.nspname = 'public'
  left join pg_class c on c.relname = required.table_name and c.relnamespace = n.oid
  where c.oid is null or not c.relrowsecurity;

  if missing_tables is not null then
    raise exception 'Missing tables or RLS disabled: %', missing_tables;
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_lab_with_admin'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Atomic lab-with-administrator onboarding RPC is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'resource_no_overlap' and contype = 'x'
  ) then
    raise exception 'Resource booking overlap exclusion constraint is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'staff_no_overlap' and contype = 'x'
  ) then
    raise exception 'Staff booking overlap exclusion constraint is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'slot_hold_no_overlap' and contype = 'x'
  ) then
    raise exception 'Slot hold overlap exclusion constraint is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'appointment_patient_no_overlap' and contype = 'x'
  ) then
    raise exception 'Active appointment overlap constraint is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'staff_shifts_no_overlap' and contype = 'x'
  ) then
    raise exception 'Staff shift overlap constraint is missing';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_my_published_reports'
      and p.prosecdef
  ) then
    raise exception 'Patient-safe published report function is missing';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'reports'
      and cmd in ('SELECT','ALL')
      and qual ilike '%is_patient_owner%'
  ) then
    raise exception 'Patients must not query internal report columns directly';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'reports'
      and cmd in ('SELECT','ALL')
      and coalesce(qual, '') not ilike '%has_report_access%'
  ) then
    raise exception 'Report reads must be case-assignment scoped';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'order_items'
      and cmd in ('UPDATE','ALL')
      and (
        coalesce(qual, '') not ilike '%has_order_item_access%'
        or coalesce(with_check, '') not ilike '%has_order_item_access%'
      )
  ) then
    raise exception 'Order-item updates must be case-assignment scoped';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'lab_private_storage_read'
      and qual ilike '%storage_report_id%'
      and qual ilike '%has_report_access%'
  ) then
    raise exception 'Report Storage reads must be case-assignment scoped';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_preferences'
      and cmd in ('DELETE','ALL')
  ) then
    raise exception 'Notification preferences must not have broad delete access';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'patients'
      and policyname = 'lab_member_read'
      and qual ilike '%has_lab_permission%'
  ) then
    raise exception 'Role-based patient policy is missing';
  end if;

  if exists (
    select 1 from public.role_default_permissions
    where role_key = 'platform_admin'
      and permission_key in ('patients.read','reports.read','billing.read')
  ) then
    raise exception 'Platform admins must not have default patient-data permissions';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'memberships'
      and cmd in ('INSERT','UPDATE','DELETE','ALL')
  ) then
    raise exception 'Membership mutations must require a trusted server flow';
  end if;

  if not has_table_privilege('authenticated', 'public.memberships', 'SELECT') then
    raise exception 'Authenticated staff need SELECT privilege to verify their membership';
  end if;

  if not has_table_privilege('authenticated', 'public.labs', 'SELECT') then
    raise exception 'Authenticated users need SELECT privilege for their RLS-filtered lab metadata';
  end if;

  if not has_table_privilege('authenticated', 'public.profiles', 'SELECT') then
    raise exception 'Authenticated staff need SELECT privilege for their RLS-filtered profile';
  end if;

  if not has_table_privilege('authenticated', 'public.patients', 'SELECT') then
    raise exception 'Authenticated staff need SELECT privilege for RLS-filtered patient records';
  end if;

  if has_table_privilege('authenticated', 'public.patients', 'INSERT')
    or has_table_privilege('authenticated', 'public.patients', 'UPDATE')
    or has_table_privilege('authenticated', 'public.patients', 'DELETE')
  then
    raise exception 'Patient mutations must use trusted RPCs';
  end if;

  if has_table_privilege('authenticated', 'public.page_grants', 'INSERT')
    or has_table_privilege('authenticated', 'public.page_grants', 'UPDATE')
    or has_table_privilege('authenticated', 'public.page_grants', 'DELETE')
    or has_table_privilege('authenticated', 'public.referring_doctors', 'INSERT')
    or has_table_privilege('authenticated', 'public.reagent_stock', 'INSERT')
    or has_table_privilege('authenticated', 'public.expenses', 'INSERT')
    or has_table_privilege('authenticated', 'public.report_results', 'INSERT')
    or has_table_privilege('authenticated', 'public.resources', 'INSERT')
    or has_table_privilege('authenticated', 'public.resource_bookings', 'INSERT')
    or has_table_privilege('authenticated', 'public.staff_shifts', 'INSERT')
    or has_table_privilege('authenticated', 'public.reagent_stock_movements', 'INSERT')
  then
    raise exception 'Workspace mutations must use permission-checked RPCs';
  end if;

  if not exists (
    select 1 from public.role_default_page_grants
    where role_key = 'lab_admin' and page_key = 'manage_users'
  ) or not exists (
    select 1 from public.role_default_page_grants
    where role_key = 'technician' and page_key = 'samples'
  ) then
    raise exception 'Default page grants are incomplete';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'register_patient'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Trusted patient registration function is missing or exposed';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_lab_invoice'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'save_report_result'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_staff_access'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Operational RPCs must be authenticated and security-definer protected';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_public_report'
      and p.prosecdef
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Patient report links must use the limited public report function';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_lab_appointment'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'save_lab_working_hour'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Appointment and working-hour mutations must use authenticated RPCs';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_lab_resource'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_lab_resource_booking'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_lab_staff_shift'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Resource and staff scheduling writes must use authenticated RPCs';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_lab_invoice_print'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_lab_report_print'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Print data functions must be authenticated and security-definer protected';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'save_lab_reagent'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'record_lab_reagent_movement'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_lab_reagent_movements'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Inventory movement RPCs are missing or exposed';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'is_patient_portal_user'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_my_patient_reports'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Patient portal functions must be authenticated and security-definer protected';
  end if;

  if has_table_privilege('authenticated', 'public.report_result_files', 'INSERT')
    or has_table_privilege('authenticated', 'public.report_result_files', 'UPDATE')
    or has_table_privilege('authenticated', 'public.report_result_files', 'DELETE')
  then
    raise exception 'Report attachment registration must use the trusted scanner service';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'register_scanned_report_attachment'
      and p.prosecdef
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_lab_report_attachment_path'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Report attachment registration or download access is improperly exposed';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'save_lab_retention_policy'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'run_lab_retention_cleanup'
      and p.prosecdef
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Retention policy or trusted maintenance functions are missing';
  end if;

  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'reagent_stock'
      and t.tgname = 'reagent_stock_quantity_movement_guard'
      and not t.tgisinternal
  ) or not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'reagent_stock_movements'
      and t.tgname = 'audit_lab_row_change'
      and not t.tgisinternal
  ) then
    raise exception 'Inventory movement and audit triggers are missing';
  end if;

  if (
    select count(*) from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('services','service_categories','invoices','payments','samples',
        'report_results','expenses','referring_doctors','reagent_stock','page_grants')
      and t.tgname = 'audit_lab_row_change'
      and not t.tgisinternal
  ) <> 10 then
    raise exception 'Redacted audit triggers are missing from workspace tables';
  end if;

  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'platform_developers'
      and c.relrowsecurity
  ) then
    raise exception 'Platform developer allow-list must have RLS enabled';
  end if;

  if has_table_privilege('authenticated', 'public.platform_developers', 'SELECT') then
    raise exception 'Platform developer allow-list must not be directly readable';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'is_platform_developer'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Authenticated platform developer check function is missing or exposed';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_lab'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Trusted platform lab-creation function is missing or exposed';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'labs'
      and policyname = 'platform_developer_labs_read'
      and cmd = 'SELECT'
      and qual ilike '%is_platform_developer%'
  ) then
    raise exception 'Platform developers must be able to read lab metadata';
  end if;

  if has_table_privilege('authenticated', 'public.labs', 'INSERT')
    or has_table_privilege('authenticated', 'public.labs', 'UPDATE')
    or has_table_privilege('authenticated', 'public.labs', 'DELETE')
  then
    raise exception 'Laboratory creation and mutation must use the trusted RPC';
  end if;

  if has_table_privilege('anon', 'public.labs', 'SELECT') then
    raise exception 'Anonymous users must not read laboratory metadata';
  end if;

  if not has_table_privilege('authenticated', 'public.patient_accounts', 'SELECT') then
    raise exception 'Authenticated RLS checks need SELECT privilege on patient account links';
  end if;

  if has_table_privilege('anon', 'public.patient_accounts', 'SELECT') then
    raise exception 'Anonymous users must not read patient account links';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'patient_accounts'
      and policyname = 'patient_account_read'
      and cmd = 'SELECT'
      and qual ilike '%is_platform_developer%'
  ) then
    raise exception 'Patient account reads must exclude platform developers';
  end if;

  if pg_get_functiondef('public.is_lab_member(uuid)'::regprocedure) not ilike '%is_platform_developer%'
    or pg_get_functiondef('public.has_lab_permission(uuid,text)'::regprocedure) not ilike '%is_platform_developer%'
    or pg_get_functiondef('public.is_patient_owner(uuid)'::regprocedure) not ilike '%is_platform_developer%'
  then
    raise exception 'Platform developers must be excluded from all tenant and patient access helpers';
  end if;

  if pg_get_functiondef('public.has_lab_permission(uuid,text)'::regprocedure) not ilike '%has_lab_page_access%'
    or pg_get_functiondef('public.has_lab_page_access(uuid,text)'::regprocedure) not ilike '%is_platform_developer%'
  then
    raise exception 'Permission checks must enforce page grants and exclude platform developers';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename in ('patients', 'reports', 'invoices', 'payments')
      and (
        coalesce(qual, '') ilike '%is_platform_developer%'
        or coalesce(with_check, '') ilike '%is_platform_developer%'
      )
  ) then
    raise exception 'Platform developer policies must not grant clinical or billing access';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'memberships'
      and policyname = 'membership_self_or_lab_read'
      and cmd = 'SELECT'
  ) then
    raise exception 'Membership reads must be protected by the self-or-lab RLS policy';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'audit_logs'
      and cmd in ('UPDATE','DELETE','ALL')
  ) then
    raise exception 'Audit log mutation policy must not exist';
  end if;

  if (
    select count(*) from storage.buckets
    where id in ('reports','branding','attachments','report-attachments') and public = false
  ) <> 3 then
    raise exception 'Required private storage buckets are missing';
  end if;
end;
$$;
