create extension if not exists "btree_gist";

create table public.lab_settings (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null unique references public.labs(id) on delete cascade,
  currency char(3) not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  timezone text not null default 'UTC',
  date_format text not null default 'yyyy-MM-dd',
  language text not null default 'en',
  patient_code_prefix text not null default 'LN',
  invoice_code_prefix text not null default 'INV',
  require_mfa_for_admins boolean not null default true,
  allow_report_self_approval boolean not null default false,
  require_dual_approval boolean not null default false,
  allow_unassigned_doctor_queue boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.lab_branding (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null unique references public.labs(id) on delete cascade,
  logo_path text,
  primary_color text check (primary_color is null or primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.permission_catalog (
  permission_key text primary key,
  description text not null
);

create table public.role_default_permissions (
  role_key text not null,
  permission_key text not null references public.permission_catalog(permission_key) on delete cascade,
  primary key (role_key, permission_key)
);

create table public.roles_permissions (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  role_key text not null,
  permission_key text not null references public.permission_catalog(permission_key) on delete cascade,
  allowed boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, role_key, permission_key),
  check (role_key <> 'platform_admin')
);

insert into public.permission_catalog(permission_key, description) values
  ('patients.read', 'Read patient records'),
  ('patients.write', 'Register and update patients'),
  ('notes.clinical.read', 'Read restricted clinical notes'),
  ('notes.clinical.write', 'Create and update restricted clinical notes'),
  ('appointments.read', 'Read appointments'),
  ('appointments.manage', 'Create, reschedule, and cancel appointments'),
  ('scheduling.read', 'Read staff and resource availability'),
  ('scheduling.manage', 'Manage staff and resource availability'),
  ('services.read', 'Read the test and service catalogue'),
  ('services.manage', 'Manage tests and service catalogue'),
  ('orders.read', 'Read visits, orders, and sample status'),
  ('orders.manage', 'Manage visit, order, and sample processing'),
  ('orders.assign', 'Assign technicians and reporting doctors to orders'),
  ('billing.read', 'Read invoices and payments'),
  ('billing.manage', 'Manage invoices, payments, and receipts'),
  ('billing.discount', 'Apply discounts to invoices'),
  ('export.run', 'Request data exports'),
  ('support.access.manage', 'Grant and revoke time-limited support access'),
  ('reports.read', 'Read internal reports'),
  ('reports.upload', 'Upload and version reports'),
  ('reports.review', 'Review and approve reports'),
  ('reports.publish', 'Publish, withdraw, and correct reports'),
  ('notifications.read', 'Read notifications'),
  ('notifications.manage', 'Manage notifications and preferences'),
  ('settings.read', 'Read laboratory settings'),
  ('settings.manage', 'Manage laboratory settings'),
  ('staff.manage', 'Manage laboratory staff and memberships'),
  ('roles.manage', 'Manage role permissions'),
  ('audit.write', 'Append audit events'),
  ('audit.read', 'Read audit events'),
  ('analytics.read', 'Read laboratory analytics')
on conflict (permission_key) do nothing;

insert into public.role_default_permissions(role_key, permission_key)
select defaults.role_key, defaults.permission_key
from (values
  ('lab_admin','patients.read'),('lab_admin','patients.write'),
  ('lab_admin','notes.clinical.read'),('lab_admin','notes.clinical.write'),
  ('lab_admin','appointments.read'),('lab_admin','appointments.manage'),
  ('lab_admin','scheduling.read'),('lab_admin','scheduling.manage'),
  ('lab_admin','services.read'),('lab_admin','services.manage'),
  ('lab_admin','orders.read'),('lab_admin','orders.manage'),
  ('lab_admin','orders.assign'),
  ('lab_admin','billing.read'),('lab_admin','billing.manage'),
  ('lab_admin','billing.discount'),
  ('lab_admin','reports.read'),('lab_admin','reports.upload'),('lab_admin','reports.review'),('lab_admin','reports.publish'),
  ('lab_admin','notifications.read'),('lab_admin','notifications.manage'),
  ('lab_admin','settings.read'),('lab_admin','settings.manage'),
  ('lab_admin','staff.manage'),('lab_admin','roles.manage'),
  ('lab_admin','export.run'),('lab_admin','support.access.manage'),
  ('lab_admin','audit.write'),('lab_admin','audit.read'),('lab_admin','analytics.read'),
  ('receptionist','patients.read'),('receptionist','patients.write'),
  ('receptionist','appointments.read'),('receptionist','appointments.manage'),
  ('receptionist','scheduling.read'),('receptionist','services.read'),
  ('receptionist','orders.read'),('receptionist','orders.manage'),
  ('receptionist','billing.read'),('receptionist','billing.manage'),
  ('receptionist','notifications.read'),('receptionist','notifications.manage'),('receptionist','audit.write'),
  ('technician','patients.read'),('technician','appointments.read'),('technician','scheduling.read'),
  ('technician','services.read'),('technician','orders.read'),('technician','orders.manage'),
  ('technician','reports.read'),('technician','reports.upload'),
  ('technician','notifications.read'),('technician','notifications.manage'),('technician','audit.write'),
  ('reporting_doctor','patients.read'),('reporting_doctor','orders.read'),
  ('reporting_doctor','reports.read'),('reporting_doctor','reports.upload'),
  ('reporting_doctor','reports.review'),('reporting_doctor','reports.publish'),
  ('reporting_doctor','notifications.read'),('reporting_doctor','notifications.manage'),('reporting_doctor','audit.write'),
  ('billing_staff','patients.read'),('billing_staff','billing.read'),('billing_staff','billing.manage'),
  ('billing_staff','billing.discount'),
  ('billing_staff','notifications.read'),('billing_staff','notifications.manage'),('billing_staff','audit.write'),
  ('lab_manager','analytics.read'),('lab_manager','audit.write')
) as defaults(role_key, permission_key)
on conflict do nothing;

alter table public.patients add constraint patients_id_lab_unique unique (id, lab_id);

create table public.patient_accounts (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, patient_id),
  unique(lab_id, user_id),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete cascade
);

create table public.patient_contacts (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null,
  contact_type text not null check (contact_type in ('email','phone','emergency','address')),
  value text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete cascade
);

create table public.patient_notes (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null,
  author_id uuid not null references auth.users(id),
  note text not null,
  visibility text not null default 'clinical' check (visibility in ('clinical','administrative')),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete cascade
);

create table public.service_categories (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, name),
  unique(id, lab_id)
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  category_id uuid,
  code text not null,
  name text not null,
  description text,
  service_type text not null default 'laboratory'
    check (service_type in ('laboratory','xray','ultrasound','ecg','other')),
  price numeric(12,2) not null default 0 check (price >= 0),
  duration_minutes integer not null default 15 check (duration_minutes > 0),
  turnaround_minutes integer check (turnaround_minutes is null or turnaround_minutes > 0),
  preparation_instructions text,
  required_resource_type text,
  required_staff_role text,
  preparation_buffer_minutes integer not null default 0 check (preparation_buffer_minutes >= 0),
  active boolean not null default true,
  patient_visible boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, code),
  unique(id, lab_id),
  foreign key (category_id, lab_id) references public.service_categories(id, lab_id) on delete restrict
);

create table public.service_packages (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  code text not null,
  name text not null,
  price numeric(12,2) not null default 0 check (price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, code),
  unique(id, lab_id)
);

create table public.service_package_items (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  package_id uuid not null,
  service_id uuid not null,
  quantity integer not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(package_id, service_id),
  unique(id, lab_id),
  foreign key (package_id, lab_id) references public.service_packages(id, lab_id) on delete cascade,
  foreign key (service_id, lab_id) references public.services(id, lab_id) on delete restrict
);

create table public.working_hours (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  opens_at time not null,
  closes_at time not null,
  closed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (closed or opens_at < closes_at),
  unique(lab_id, weekday)
);

create table public.holidays_closures (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at < ends_at)
);

create table public.staff_shifts (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  staff_id uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled','leave','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at < ends_at)
);

create table public.staff_bookings (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  staff_id uuid not null references auth.users(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at < ends_at),
  constraint staff_no_overlap exclude using gist (
    staff_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (active)
);

create table public.slot_holds (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  resource_id uuid not null references public.resources(id) on delete cascade,
  patient_id uuid,
  held_by uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  status text not null default 'held' check (status in ('held','confirmed','released','expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at < ends_at),
  unique(id, lab_id),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete cascade,
  constraint slot_hold_no_overlap exclude using gist (
    resource_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status = 'held')
);

create table public.visits (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null,
  appointment_id uuid references public.appointments(id) on delete restrict,
  visit_code text not null,
  status text not null default 'registered'
    check (status in ('registered','in_progress','completed','cancelled')),
  registered_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, visit_code),
  unique(id, lab_id),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete restrict
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  visit_id uuid not null references public.visits(id) on delete cascade,
  service_id uuid not null,
  assigned_technician_id uuid references auth.users(id),
  assigned_doctor_id uuid references auth.users(id),
  status text not null default 'registered'
    check (status in ('registered','test_scheduled','sample_collected','in_progress',
      'awaiting_doctor_review','report_available','additional_information_required','cancelled')),
  price numeric(12,2) not null check (price >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id, lab_id),
  foreign key (service_id, lab_id) references public.services(id, lab_id) on delete restrict
);

create table public.samples (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id) on delete cascade,
  barcode text not null,
  collected_at timestamptz,
  collected_by uuid references auth.users(id),
  status text not null default 'pending' check (status in ('pending','collected','rejected','recollected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, barcode)
);

create table public.patient_code_counters (
  lab_id uuid not null references public.labs(id) on delete cascade,
  code_year integer not null,
  last_value bigint not null default 0,
  primary key (lab_id, code_year)
);

create table public.invoice_counters (
  lab_id uuid not null references public.labs(id) on delete cascade,
  code_year integer not null,
  last_value bigint not null default 0,
  primary key (lab_id, code_year)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null,
  visit_id uuid references public.visits(id) on delete restrict,
  invoice_number text not null,
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  discount_reason text,
  tax numeric(12,2) not null default 0 check (tax >= 0),
  total numeric(12,2) not null check (total >= 0),
  status text not null default 'open' check (status in ('open','partially_paid','paid','void','credited')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, invoice_number),
  unique(id, lab_id),
  check (discount <= subtotal),
  check (discount = 0 or length(trim(discount_reason)) > 0),
  check (total = subtotal - discount + tax),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete restrict
);

create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  order_item_id uuid references public.order_items(id) on delete restrict,
  description text not null,
  quantity integer not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (line_total = quantity * unit_price)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  method text not null check (method in ('cash','card','bank_transfer','mobile_wallet','other')),
  reference text,
  received_by uuid references auth.users(id),
  received_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references auth.users(id),
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id, lab_id),
  check (
    (voided_at is null and voided_by is null and void_reason is null)
    or (voided_at is not null and voided_by is not null and length(trim(void_reason)) > 0)
  )
);

create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  payment_id uuid references public.payments(id) on delete restrict,
  receipt_number text not null,
  reprint_count integer not null default 0 check (reprint_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, receipt_number)
);

alter table public.reports
  add column order_item_id uuid,
  add column uploader_id uuid references auth.users(id),
  add column assigned_doctor_id uuid references auth.users(id),
  add column title text,
  add column published_by uuid references auth.users(id),
  add constraint reports_status_check check (
    status in ('pending_review','in_review','changes_required','approved','published','withdrawn','superseded')
  ),
  add constraint reports_published_at_check check (
    status <> 'published' or published_at is not null
  ),
  add constraint reports_patient_lab_fk foreign key (patient_id, lab_id)
    references public.patients(id, lab_id) on delete restrict;

create table public.report_versions (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  file_path text not null,
  sha256 text not null check (sha256 ~ '^[0-9a-fA-F]{64}$'),
  file_size_bytes bigint not null check (file_size_bytes between 1 and 26214400),
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(report_id, version_number)
);

create table public.report_reviews (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id),
  decision text not null check (decision in ('changes_required','approved','rejected')),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.report_publications (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,
  version_id uuid not null references public.report_versions(id) on delete restrict,
  published_by uuid not null references auth.users(id),
  published_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index report_publications_one_active_idx
  on public.report_publications(report_id) where withdrawn_at is null;

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid,
  user_id uuid references auth.users(id) on delete cascade,
  event_type text not null,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (patient_id is not null or user_id is not null),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete cascade
);

create table public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid,
  user_id uuid references auth.users(id) on delete cascade,
  channel text not null check (channel in ('in_app','email','sms','whatsapp')),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (patient_id is not null or user_id is not null),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete cascade
);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  currency char(3) not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  monthly_price numeric(12,2) not null default 0 check (monthly_price >= 0),
  annual_price numeric(12,2) not null default 0 check (annual_price >= 0),
  limits jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  plan_id uuid not null references public.plans(id) on delete restrict,
  status text not null default 'trialing'
    check (status in ('trialing','active','past_due','paused','cancelled')),
  billing_interval text not null default 'monthly' check (billing_interval in ('monthly','annual')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  external_customer_ref text,
  external_subscription_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (current_period_end is null or current_period_start < current_period_end)
);

create unique index subscriptions_one_active_per_lab_idx
  on public.subscriptions(lab_id) where status in ('trialing','active','past_due','paused');

create table public.feature_flags (
  id uuid primary key default gen_random_uuid(),
  flag_key text not null,
  lab_id uuid references public.labs(id) on delete cascade,
  enabled boolean not null default false,
  configuration jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (flag_key, lab_id)
);

create table public.export_jobs (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  requested_by uuid not null references auth.users(id),
  export_type text not null check (export_type in ('patients','appointments','billing','audit','patient_data')),
  status text not null default 'queued' check (status in ('queued','running','completed','failed','expired')),
  filters jsonb not null default '{}'::jsonb,
  file_path text,
  expires_at timestamptz,
  failure_code text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.support_access_grants (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  granted_by uuid not null references auth.users(id),
  support_user_id uuid not null references auth.users(id),
  reason text not null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (granted_by <> support_user_id),
  check (expires_at > granted_at),
  check (expires_at <= granted_at + interval '24 hours'),
  check ((revoked_at is null and revoked_by is null) or (revoked_at is not null and revoked_by is not null))
);

create table public.notification_templates (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  event_type text not null,
  channel text not null check (channel in ('email','sms','whatsapp')),
  subject_template text,
  body_template text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, event_type, channel)
);

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  notification_id uuid,
  channel text not null check (channel in ('email','sms','whatsapp')),
  status text not null default 'queued' check (status in ('queued','sent','delivered','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  provider_reference text,
  failure_code text,
  next_attempt_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id, lab_id)
);

create table public.credit_notes (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  credit_number text not null,
  amount numeric(12,2) not null check (amount > 0),
  reason text not null,
  issued_by uuid not null references auth.users(id),
  issued_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, credit_number),
  unique(id, lab_id)
);

create table public.retention_settings (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null unique references public.labs(id) on delete cascade,
  retention_days integer not null default 2555 check (retention_days > 0),
  legal_hold_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.external_doctor_links (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid references public.labs(id) on delete cascade,
  doctor_user_id uuid not null references auth.users(id) on delete cascade,
  external_reference text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (lab_id, doctor_user_id)
);

create index patients_lab_name_idx on public.patients(lab_id, lower(full_name)) where deleted_at is null;
create index patients_lab_phone_idx on public.patients(lab_id, phone) where deleted_at is null;
create index appointments_lab_start_idx on public.appointments(lab_id, starts_at);
create index order_items_lab_status_idx on public.order_items(lab_id, status, created_at);
create index reports_lab_status_idx on public.reports(lab_id, status, created_at);
create index reports_patient_published_idx on public.reports(patient_id, published_at desc) where status = 'published';
create index invoices_lab_status_idx on public.invoices(lab_id, status, created_at);
create index payments_invoice_idx on public.payments(invoice_id, received_at);
create index notifications_patient_idx on public.notifications(patient_id, created_at desc);
create index portal_tokens_expiry_idx on public.portal_tokens(expires_at) where used_at is null and revoked_at is null;
create index audit_logs_lab_created_idx on public.audit_logs(lab_id, created_at desc);
create index export_jobs_lab_created_idx on public.export_jobs(lab_id, created_at desc);
create index notification_deliveries_retry_idx on public.notification_deliveries(status, next_attempt_at)
  where status in ('queued','failed');
create index support_access_active_idx on public.support_access_grants(lab_id, expires_at)
  where revoked_at is null;

alter table public.notifications add constraint notifications_id_lab_unique unique (id, lab_id);
alter table public.notification_deliveries add constraint notification_deliveries_notification_lab_fk
  foreign key (notification_id, lab_id) references public.notifications(id, lab_id) on delete restrict;
alter table public.credit_notes add constraint credit_notes_invoice_lab_fk
  foreign key (invoice_id, lab_id) references public.invoices(id, lab_id) on delete restrict;
alter table public.credit_notes add constraint credit_notes_issuer_membership_fk
  foreign key (lab_id, issued_by) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.portal_tokens add constraint portal_tokens_purpose_check
  check (purpose in ('activation','portal_entry','password_reset'));
alter table public.portal_tokens add constraint portal_tokens_hash_check
  check (token_hash ~ '^[0-9a-fA-F]{64}$');

alter table public.resources add constraint resources_id_lab_unique unique (id, lab_id);
alter table public.resource_bookings add constraint resource_bookings_resource_lab_fk
  foreign key (resource_id, lab_id) references public.resources(id, lab_id) on delete cascade;
alter table public.slot_holds add constraint slot_holds_resource_lab_fk
  foreign key (resource_id, lab_id) references public.resources(id, lab_id) on delete cascade;
alter table public.appointments add constraint appointments_id_lab_unique unique (id, lab_id);
alter table public.appointments add constraint appointments_time_order_check
  check (starts_at < ends_at);
alter table public.resource_bookings add constraint resource_bookings_appointment_lab_fk
  foreign key (appointment_id, lab_id) references public.appointments(id, lab_id) on delete restrict;
alter table public.resource_bookings
  add column slot_hold_id uuid,
  add constraint resource_bookings_hold_lab_fk
    foreign key (slot_hold_id, lab_id) references public.slot_holds(id, lab_id) on delete restrict;
create unique index resource_bookings_slot_hold_unique_idx
  on public.resource_bookings(slot_hold_id) where slot_hold_id is not null;
alter table public.portal_tokens add column updated_at timestamptz not null default now();
alter table public.visits add constraint visits_appointment_lab_fk
  foreign key (appointment_id, lab_id) references public.appointments(id, lab_id) on delete restrict;
alter table public.staff_shifts add constraint staff_shifts_membership_fk
  foreign key (lab_id, staff_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.staff_bookings add constraint staff_bookings_membership_fk
  foreign key (lab_id, staff_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.staff_bookings add constraint staff_bookings_appointment_lab_fk
  foreign key (appointment_id, lab_id) references public.appointments(id, lab_id) on delete restrict;
alter table public.order_items add constraint order_items_visit_lab_fk
  foreign key (visit_id, lab_id) references public.visits(id, lab_id) on delete cascade;
alter table public.order_items add constraint order_items_id_lab_unique unique (id, lab_id);
alter table public.order_items add constraint order_items_technician_membership_fk
  foreign key (lab_id, assigned_technician_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.order_items add constraint order_items_doctor_membership_fk
  foreign key (lab_id, assigned_doctor_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.patient_notes add constraint patient_notes_author_membership_fk
  foreign key (lab_id, author_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.samples add constraint samples_order_item_lab_fk
  foreign key (order_item_id, lab_id) references public.order_items(id, lab_id) on delete cascade;
alter table public.samples add constraint samples_collector_membership_fk
  foreign key (lab_id, collected_by) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.invoices add constraint invoices_visit_lab_fk
  foreign key (visit_id, lab_id) references public.visits(id, lab_id) on delete restrict;
alter table public.invoices add constraint invoices_creator_membership_fk
  foreign key (lab_id, created_by) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.invoice_items add constraint invoice_items_invoice_lab_fk
  foreign key (invoice_id, lab_id) references public.invoices(id, lab_id) on delete cascade;
alter table public.invoice_items add constraint invoice_items_order_item_lab_fk
  foreign key (order_item_id, lab_id) references public.order_items(id, lab_id) on delete restrict;
alter table public.payments add constraint payments_invoice_lab_fk
  foreign key (invoice_id, lab_id) references public.invoices(id, lab_id) on delete restrict;
alter table public.payments add constraint payments_receiver_membership_fk
  foreign key (lab_id, received_by) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.receipts add constraint receipts_invoice_lab_fk
  foreign key (invoice_id, lab_id) references public.invoices(id, lab_id) on delete restrict;
alter table public.receipts add constraint receipts_payment_lab_fk
  foreign key (payment_id, lab_id) references public.payments(id, lab_id) on delete restrict;
alter table public.reports add constraint reports_id_lab_unique unique (id, lab_id);
alter table public.reports add constraint reports_order_item_lab_fk
  foreign key (order_item_id, lab_id) references public.order_items(id, lab_id) on delete restrict;
alter table public.reports add constraint reports_doctor_membership_fk
  foreign key (lab_id, assigned_doctor_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.reports add constraint reports_uploader_membership_fk
  foreign key (lab_id, uploader_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.reports add constraint reports_publisher_membership_fk
  foreign key (lab_id, published_by) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.report_versions add constraint report_versions_report_lab_fk
  foreign key (report_id, lab_id) references public.reports(id, lab_id) on delete cascade;
alter table public.report_versions add constraint report_versions_uploader_membership_fk
  foreign key (lab_id, uploaded_by) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.report_reviews add constraint report_reviews_report_lab_fk
  foreign key (report_id, lab_id) references public.reports(id, lab_id) on delete cascade;
alter table public.report_reviews add constraint report_reviews_reviewer_membership_fk
  foreign key (lab_id, reviewer_id) references public.memberships(lab_id, user_id) on delete restrict;
alter table public.report_publications add constraint report_publications_report_lab_fk
  foreign key (report_id, lab_id) references public.reports(id, lab_id) on delete cascade;
alter table public.report_versions add constraint report_versions_id_lab_unique unique (id, lab_id);
alter table public.report_publications add constraint report_publications_version_lab_fk
  foreign key (version_id, lab_id) references public.report_versions(id, lab_id) on delete restrict;
alter table public.report_publications add constraint report_publications_publisher_membership_fk
  foreign key (lab_id, published_by) references public.memberships(lab_id, user_id) on delete restrict;

create or replace function public.is_patient_owner(target_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.patient_accounts pa
    where pa.patient_id = target_patient
      and pa.user_id = (select auth.uid())
      and pa.activated_at is not null
  );
$$;

create or replace function public.get_my_published_reports()
returns table (report_id uuid, title text, published_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.title, r.published_at
  from public.reports r
  where r.status = 'published'
    and r.published_at is not null
    and public.is_patient_owner(r.patient_id)
  order by r.published_at desc;
$$;

create or replace function public.is_lab_auditor(target_lab uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.lab_id = target_lab
      and m.user_id = (select auth.uid())
      and m.active
      and m.role in ('lab_admin','platform_admin')
  );
$$;

create or replace function public.has_lab_permission(target_lab uuid, target_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
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
    from public.memberships m
    where m.lab_id = target_lab
      and m.user_id = (select auth.uid())
      and m.active
    limit 1
  ), false);
$$;

create or replace function public.has_order_item_access(target_lab uuid, target_order_item uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.order_items oi
    join public.memberships m
      on m.lab_id = oi.lab_id
      and m.user_id = (select auth.uid())
      and m.active
    where oi.id = target_order_item
      and oi.lab_id = target_lab
      and public.has_lab_permission(target_lab, 'orders.read')
      and case m.role
        when 'reporting_doctor' then
          oi.assigned_doctor_id = (select auth.uid())
          or (
            oi.assigned_doctor_id is null
            and exists (
              select 1 from public.lab_settings settings
              where settings.lab_id = target_lab
                and settings.allow_unassigned_doctor_queue
            )
          )
        when 'technician' then oi.assigned_technician_id = (select auth.uid())
        else true
      end
  );
$$;

create or replace function public.has_report_access(target_lab uuid, target_report uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.reports r
    left join public.order_items oi
      on oi.id = r.order_item_id and oi.lab_id = r.lab_id
    join public.memberships m
      on m.lab_id = r.lab_id
      and m.user_id = (select auth.uid())
      and m.active
    where r.id = target_report
      and r.lab_id = target_lab
      and public.has_lab_permission(target_lab, 'reports.read')
      and case m.role
        when 'reporting_doctor' then
          coalesce(r.assigned_doctor_id, oi.assigned_doctor_id) = (select auth.uid())
          or (
            r.assigned_doctor_id is null
            and oi.assigned_doctor_id is null
            and exists (
              select 1 from public.lab_settings settings
              where settings.lab_id = target_lab
                and settings.allow_unassigned_doctor_queue
            )
          )
        when 'technician' then
          r.order_item_id is not null
          and public.has_order_item_access(target_lab, r.order_item_id)
        else true
      end
  );
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.guard_invoice()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  paid_total numeric(12,2);
  expected_status text;
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.created_by := auth.uid();
      if new.status <> 'open' then
        raise exception 'New invoices must start open' using errcode = '23514';
      end if;
      if new.discount > 0 and not public.has_lab_permission(new.lab_id, 'billing.discount') then
        raise exception 'Discount permission required' using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  if new.invoice_number is distinct from old.invoice_number
    or new.lab_id is distinct from old.lab_id
    or new.patient_id is distinct from old.patient_id
    or new.visit_id is distinct from old.visit_id
    or new.currency is distinct from old.currency
    or new.subtotal is distinct from old.subtotal
    or new.discount is distinct from old.discount
    or new.discount_reason is distinct from old.discount_reason
    or new.tax is distinct from old.tax
    or new.total is distinct from old.total
    or new.created_by is distinct from old.created_by then
    raise exception 'Issued invoice details are immutable' using errcode = '42501';
  end if;

  select coalesce(sum(p.amount), 0) into paid_total
  from public.payments p
  where p.invoice_id = old.id and p.voided_at is null;

  expected_status := case
    when paid_total >= old.total and paid_total > 0 then 'paid'
    when paid_total > 0 then 'partially_paid'
    else 'open'
  end;
  if auth.uid() is not null and new.status is distinct from expected_status then
    raise exception 'Invoice status must match recorded payments' using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.guard_order_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'registered' then
      raise exception 'New order items must start as registered' using errcode = '23514';
    end if;
    if auth.uid() is not null
      and (new.assigned_technician_id is not null or new.assigned_doctor_id is not null)
      and not public.has_lab_permission(new.lab_id, 'orders.assign') then
      raise exception 'Order assignment permission required' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.lab_id is distinct from old.lab_id
    or new.visit_id is distinct from old.visit_id
    or new.service_id is distinct from old.service_id
    or new.price is distinct from old.price
    or new.created_at is distinct from old.created_at then
    raise exception 'Order identity and price are immutable' using errcode = '42501';
  end if;

  if new.assigned_technician_id is distinct from old.assigned_technician_id
    or new.assigned_doctor_id is distinct from old.assigned_doctor_id then
    if not public.has_lab_permission(new.lab_id, 'orders.assign') then
      raise exception 'Order assignment permission required' using errcode = '42501';
    end if;
  end if;

  if new.status is distinct from old.status then
    if not public.has_lab_permission(new.lab_id, 'orders.manage') then
      raise exception 'Order processing permission required' using errcode = '42501';
    end if;
    if not (
      (old.status = 'registered' and new.status = 'test_scheduled')
      or (old.status = 'test_scheduled' and new.status = 'sample_collected')
      or (old.status = 'sample_collected' and new.status = 'in_progress')
      or (old.status = 'in_progress' and new.status in ('awaiting_doctor_review','additional_information_required'))
      or (old.status = 'awaiting_doctor_review' and new.status in ('additional_information_required','report_available'))
      or (old.status = 'additional_information_required' and new.status in ('sample_collected','in_progress'))
      or (old.status not in ('report_available','cancelled') and new.status = 'cancelled')
    ) then
      raise exception 'Invalid order status transition: % to %', old.status, new.status using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.guard_sample()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'pending' or new.collected_at is not null or new.collected_by is not null then
      raise exception 'New samples must begin pending without a collector' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.lab_id is distinct from old.lab_id
    or new.order_item_id is distinct from old.order_item_id
    or new.barcode is distinct from old.barcode
    or new.created_at is distinct from old.created_at then
    raise exception 'Sample identity is immutable' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'pending' and new.status in ('collected','rejected'))
      or (old.status = 'rejected' and new.status = 'recollected')
    ) then
      raise exception 'Invalid sample status transition: % to %', old.status, new.status using errcode = '23514';
    end if;
    if new.status in ('collected','recollected') then
      new.collected_at := coalesce(new.collected_at, now());
      new.collected_by := coalesce(auth.uid(), new.collected_by);
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_notification_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.lab_id is distinct from old.lab_id
    or new.patient_id is distinct from old.patient_id
    or new.user_id is distinct from old.user_id
    or new.event_type is distinct from old.event_type
    or new.message is distinct from old.message
    or new.created_at is distinct from old.created_at then
    raise exception 'Notification content and ownership are immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.guard_notification_preference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null
      and not public.has_lab_permission(new.lab_id, 'notifications.manage')
      and (new.patient_id is null
        or not public.is_patient_owner(new.patient_id)
        or (new.user_id is not null and new.user_id <> (select auth.uid()))) then
      raise exception 'Notification preference must belong to the signed-in patient' using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if auth.uid() is not null
      and not public.has_lab_permission(new.lab_id, 'notifications.manage')
      and (
        new.id is distinct from old.id
        or new.lab_id is distinct from old.lab_id
        or new.patient_id is distinct from old.patient_id
        or new.user_id is distinct from old.user_id
        or new.channel is distinct from old.channel
        or new.created_at is distinct from old.created_at
      ) then
      raise exception 'Only the notification preference value can be changed' using errcode = '42501';
    end if;
    return new;
  end if;

  if not public.has_lab_permission(old.lab_id, 'notifications.manage') then
    raise exception 'Only laboratory staff can remove notification preferences' using errcode = '42501';
  end if;
  return old;
end;
$$;

create or replace function public.guard_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  invoice_total numeric(12,2);
  invoice_status text;
  other_paid numeric(12,2);
begin
  if tg_op = 'INSERT' then
    select i.total, i.status into invoice_total, invoice_status
    from public.invoices i
    where i.id = new.invoice_id and i.lab_id = new.lab_id
    for update;

    if invoice_total is null or invoice_status in ('void','credited') then
      raise exception 'Invoice is unavailable for payment' using errcode = '23514';
    end if;
    if new.voided_at is not null then
      raise exception 'Create a payment before voiding it' using errcode = '23514';
    end if;
    select coalesce(sum(p.amount), 0) into other_paid
    from public.payments p
    where p.invoice_id = new.invoice_id and p.voided_at is null;

    if other_paid + new.amount > invoice_total then
      raise exception 'Payment exceeds the invoice balance' using errcode = '23514';
    end if;
    if auth.uid() is not null then
      new.received_by := auth.uid();
    end if;
    return new;
  end if;

  if new.invoice_id is distinct from old.invoice_id
    or new.lab_id is distinct from old.lab_id
    or new.amount is distinct from old.amount
    or new.method is distinct from old.method
    or new.reference is distinct from old.reference
    or new.received_by is distinct from old.received_by
    or new.received_at is distinct from old.received_at then
    raise exception 'Recorded payment details are immutable' using errcode = '42501';
  end if;

  if old.voided_at is not null or new.voided_at is null
    or new.void_reason is null or length(trim(new.void_reason)) = 0 then
    raise exception 'Voiding requires a reason and can only happen once' using errcode = '23514';
  end if;
  if auth.uid() is not null then
    new.voided_by := auth.uid();
  end if;
  return new;
end;
$$;

create or replace function public.guard_invoice_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  invoice_state text;
begin
  if tg_op = 'INSERT' then
    select i.status into invoice_state
    from public.invoices i
    where i.id = new.invoice_id and i.lab_id = new.lab_id
    for update;
    if invoice_state <> 'open' then
      raise exception 'Invoice items can only be added to an open invoice' using errcode = '23514';
    end if;
    return new;
  end if;

  raise exception 'Invoice items cannot be changed or deleted after issue' using errcode = '42501';
end;
$$;

create or replace function public.guard_support_access_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.granted_by := auth.uid();
    end if;
    if length(trim(new.reason)) = 0 or new.expires_at <= now()
      or new.expires_at > now() + interval '24 hours' then
      raise exception 'Support access requires a reason and may last at most 24 hours' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.lab_id is distinct from old.lab_id
    or new.support_user_id is distinct from old.support_user_id
    or new.granted_by is distinct from old.granted_by
    or new.reason is distinct from old.reason
    or new.granted_at is distinct from old.granted_at
    or new.expires_at is distinct from old.expires_at
    or old.revoked_at is not null or new.revoked_at is null then
    raise exception 'A support grant may only be revoked once' using errcode = '42501';
  end if;
  if auth.uid() is not null then
    new.revoked_by := auth.uid();
  end if;
  return new;
end;
$$;

create or replace function public.guard_credit_note()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  invoice_total numeric(12,2);
  credited_total numeric(12,2);
begin
  if auth.uid() is not null then
    new.issued_by := auth.uid();
  end if;
  if length(trim(new.reason)) = 0 then
    raise exception 'A credit note requires a reason' using errcode = '23514';
  end if;

  select i.total into invoice_total
  from public.invoices i
  where i.id = new.invoice_id and i.lab_id = new.lab_id
  for update;
  if invoice_total is null then
    raise exception 'Invoice not found for this laboratory' using errcode = '23503';
  end if;
  select coalesce(sum(c.amount), 0) into credited_total
  from public.credit_notes c
  where c.invoice_id = new.invoice_id;
  if credited_total + new.amount > invoice_total then
    raise exception 'Credit note exceeds the remaining invoice amount' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.refresh_invoice_payment_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_invoice uuid;
  current_total numeric(12,2);
  current_status text;
  paid_total numeric(12,2);
begin
  target_invoice := new.invoice_id;
  select i.total, i.status into current_total, current_status
  from public.invoices i where i.id = target_invoice;
  if current_total is null or current_status in ('void','credited') then
    return null;
  end if;

  select coalesce(sum(p.amount), 0) into paid_total
  from public.payments p
  where p.invoice_id = target_invoice and p.voided_at is null;

  update public.invoices
  set status = case
    when paid_total >= current_total and paid_total > 0 then 'paid'
    when paid_total > 0 then 'partially_paid'
    else 'open'
  end
  where id = target_invoice;
  return null;
end;
$$;

create or replace function public.guard_resource_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  confirmed_hold uuid;
begin
  if tg_op = 'UPDATE' and new.resource_id is distinct from old.resource_id then
    raise exception 'Change resources by releasing and creating a new booking' using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.resource_id::text, 0));
  update public.slot_holds
  set status = 'expired', updated_at = now()
  where resource_id = new.resource_id
    and status = 'held'
    and expires_at <= now();

  if new.active then
    if tg_op = 'INSERT' and new.slot_hold_id is not null then
      update public.slot_holds
      set status = 'confirmed', updated_at = now()
      where id = new.slot_hold_id
        and lab_id = new.lab_id
        and resource_id = new.resource_id
        and starts_at = new.starts_at
        and ends_at = new.ends_at
        and status = 'held'
        and expires_at > now()
        and (auth.uid() is null or held_by = auth.uid())
      returning id into confirmed_hold;

      if confirmed_hold is null then
        raise exception 'Slot hold is expired, unavailable, or belongs to another user' using errcode = '23P01';
      end if;
    elsif exists (
      select 1 from public.slot_holds h
      where h.resource_id = new.resource_id
        and h.status = 'held'
        and h.expires_at > now()
        and tstzrange(h.starts_at, h.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'Resource is held for another appointment' using errcode = '23P01';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.guard_slot_hold()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.resource_id is distinct from old.resource_id then
    raise exception 'Change resources by releasing and creating a new hold' using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.resource_id::text, 0));
  update public.slot_holds
  set status = 'expired', updated_at = now()
  where resource_id = new.resource_id
    and status = 'held'
    and expires_at <= now();

  if new.status = 'held' then
    if auth.uid() is not null then
      new.held_by := auth.uid();
    end if;
    new.expires_at := least(new.expires_at, now() + interval '5 minutes');
    if new.expires_at <= now() then
      raise exception 'Slot hold has expired' using errcode = '23514';
    end if;
    if exists (
      select 1 from public.resource_bookings booking
      where booking.resource_id = new.resource_id
        and booking.active
        and tstzrange(booking.starts_at, booking.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'Resource is already booked' using errcode = '23P01';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.next_patient_code(target_lab uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_year integer;
  next_value bigint;
  prefix text;
  timezone_name text;
begin
  if not public.is_lab_member(target_lab)
    and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Lab membership required' using errcode = '42501';
  end if;

  select coalesce(s.timezone, 'UTC'), coalesce(s.patient_code_prefix, 'LN')
  into timezone_name, prefix
  from public.lab_settings s where s.lab_id = target_lab;
  timezone_name := coalesce(timezone_name, 'UTC');
  current_year := extract(year from now() at time zone timezone_name)::integer;

  insert into public.patient_code_counters(lab_id, code_year, last_value)
  values (target_lab, current_year, 1)
  on conflict (lab_id, code_year)
  do update set last_value = public.patient_code_counters.last_value + 1
  returning last_value into next_value;

  return format('%s-%s-%s', coalesce(prefix, 'LN'), current_year, lpad(next_value::text, 6, '0'));
end;
$$;

create or replace function public.next_invoice_number(target_lab uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_year integer;
  next_value bigint;
  prefix text;
  timezone_name text;
begin
  if not public.is_lab_member(target_lab)
    and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Lab membership required' using errcode = '42501';
  end if;

  select coalesce(s.timezone, 'UTC'), coalesce(s.invoice_code_prefix, 'INV')
  into timezone_name, prefix
  from public.lab_settings s where s.lab_id = target_lab;
  timezone_name := coalesce(timezone_name, 'UTC');
  current_year := extract(year from now() at time zone timezone_name)::integer;

  insert into public.invoice_counters(lab_id, code_year, last_value)
  values (target_lab, current_year, 1)
  on conflict (lab_id, code_year)
  do update set last_value = public.invoice_counters.last_value + 1
  returning last_value into next_value;

  return format('%s-%s-%s', coalesce(prefix, 'INV'), current_year, lpad(next_value::text, 6, '0'));
end;
$$;

create or replace function public.assign_patient_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.patient_code, '') = '' then
    new.patient_code := public.next_patient_code(new.lab_id);
  end if;
  return new;
end;
$$;

create or replace function public.assign_invoice_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.invoice_number, '') = '' then
    new.invoice_number := public.next_invoice_number(new.lab_id);
  end if;
  return new;
end;
$$;

create or replace function public.expire_slot_holds()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_rows integer;
begin
  update public.slot_holds
  set status = 'expired', updated_at = now()
  where status = 'held' and expires_at <= now();
  get diagnostics changed_rows = row_count;
  return changed_rows;
end;
$$;

create or replace function public.consume_activation_token(token_digest text)
returns table (lab_id uuid, patient_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if token_digest !~ '^[0-9a-fA-F]{64}$' then
    return;
  end if;

  return query
  update public.portal_tokens token
  set used_at = now(), updated_at = now()
  where token.token_hash = lower(token_digest)
    and token.purpose = 'activation'
    and token.expires_at > now()
    and token.used_at is null
    and token.revoked_at is null
  returning token.lab_id, token.patient_id;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, full_name)
  values (new.id, nullif(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.enforce_report_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allow_self_approval boolean;
begin
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'pending_review' then
      raise exception 'New reports must begin in pending review' using errcode = '23514';
    end if;
    new.uploader_id := coalesce(auth.uid(), new.uploader_id);
    return new;
  end if;

  if new.uploader_id is distinct from old.uploader_id then
    raise exception 'Report uploader cannot be changed' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if new.status = 'in_review' and old.status = 'pending_review' then
      null;
    elsif new.status = 'pending_review'
      and old.status in ('changes_required','approved')
      and (new.file_path is distinct from old.file_path or new.sha256 is distinct from old.sha256) then
      if not public.has_lab_permission(new.lab_id, 'reports.upload') then
        raise exception 'Report upload permission required' using errcode = '42501';
      end if;
    elsif new.status = 'changes_required' and old.status = 'in_review' then
      if not public.has_lab_permission(new.lab_id, 'reports.review') then
        raise exception 'Report review permission required' using errcode = '42501';
      end if;
      if not exists (
        select 1 from public.report_reviews review
        where review.report_id = new.id
          and review.reviewer_id = auth.uid()
          and review.decision = 'changes_required'
      ) then
        raise exception 'Record the review decision before changing report status' using errcode = '23514';
      end if;
    elsif new.status = 'approved' and old.status = 'in_review' then
      if not public.has_lab_permission(new.lab_id, 'reports.review') then
        raise exception 'Report approval permission required' using errcode = '42501';
      end if;
      if not exists (
        select 1 from public.report_reviews review
        where review.report_id = new.id
          and review.reviewer_id = auth.uid()
          and review.decision = 'approved'
      ) then
        raise exception 'Record the approval decision before approving the report' using errcode = '23514';
      end if;
      select coalesce(s.allow_report_self_approval, false)
      into allow_self_approval
      from public.lab_settings s where s.lab_id = new.lab_id;
      if new.uploader_id = auth.uid() and not coalesce(allow_self_approval, false) then
        raise exception 'The report uploader cannot approve their own report' using errcode = '42501';
      end if;
      if exists (
        select 1 from public.lab_settings s
        where s.lab_id = new.lab_id and s.require_dual_approval
      ) and not exists (
        select 1 from public.report_reviews review
        where review.report_id = new.id
          and review.decision = 'approved'
          and review.reviewer_id <> auth.uid()
      ) then
        raise exception 'A second independent approval is required' using errcode = '42501';
      end if;
    elsif new.status = 'published' and old.status = 'approved' then
      if not public.has_lab_permission(new.lab_id, 'reports.publish') then
        raise exception 'Report publishing permission required' using errcode = '42501';
      end if;
      if not exists (
        select 1 from public.report_publications publication
        where publication.report_id = new.id
          and publication.published_by = auth.uid()
          and publication.withdrawn_at is null
      ) then
        raise exception 'Create a publication record before publishing the report' using errcode = '23514';
      end if;
      new.published_at := coalesce(new.published_at, now());
      new.published_by := auth.uid();
    elsif new.status in ('withdrawn','superseded') and old.status = 'published' then
      if not public.has_lab_permission(new.lab_id, 'reports.publish') then
        raise exception 'Report publishing permission required' using errcode = '42501';
      end if;
      if not exists (
        select 1 from public.report_publications publication
        where publication.report_id = new.id and publication.withdrawn_at is not null
      ) then
        raise exception 'Withdraw the active publication before changing report status' using errcode = '23514';
      end if;
    else
      raise exception 'Invalid report status transition: % to %', old.status, new.status using errcode = '23514';
    end if;
  end if;

  if (new.file_path is distinct from old.file_path or new.sha256 is distinct from old.sha256)
  then
    if not public.has_lab_permission(new.lab_id, 'reports.upload') then
      raise exception 'Report upload permission required' using errcode = '42501';
    end if;
    if old.status = 'published' or new.status <> 'pending_review' then
      raise exception 'A new report version must return to pending review' using errcode = '23514';
    end if;
  end if;

  if old.status = 'published' and new.status = 'published'
    and (new.published_at is distinct from old.published_at
      or new.published_by is distinct from old.published_by) then
    raise exception 'Published report details are immutable' using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.validate_report_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  related_patient uuid;
  expected_prefix text;
begin
  select r.patient_id into related_patient
  from public.reports r
  where r.id = new.report_id and r.lab_id = new.lab_id;

  if related_patient is null then
    raise exception 'Report does not belong to this laboratory' using errcode = '23503';
  end if;

  expected_prefix := format(
    '%s/%s/%s/v%s.',
    new.lab_id,
    related_patient,
    new.report_id,
    new.version_number
  );
  if left(new.file_path, length(expected_prefix)) <> expected_prefix
    or new.file_path !~* '\.(pdf|jpg|jpeg|png)$'
    or not (
      (new.mime_type = 'application/pdf' and new.file_path ~* '\.pdf$')
      or (new.mime_type = 'image/jpeg' and new.file_path ~* '\.(jpg|jpeg)$')
      or (new.mime_type = 'image/png' and new.file_path ~* '\.png$')
    ) then
    raise exception 'Report file path does not match the required tenant path' using errcode = '23514';
  end if;

  if auth.uid() is not null then
    new.uploaded_by := auth.uid();
  end if;
  return new;
end;
$$;

create or replace function public.validate_report_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_status text;
begin
  select r.status into current_status
  from public.reports r
  where r.id = new.report_id and r.lab_id = new.lab_id;

  if current_status <> 'in_review' then
    raise exception 'Report must be in review before a decision is recorded' using errcode = '23514';
  end if;
  if auth.uid() is not null then
    new.reviewer_id := auth.uid();
  end if;
  return new;
end;
$$;

create or replace function public.validate_report_publication()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_status text;
  version_report uuid;
begin
  if tg_op = 'INSERT' then
    select r.status into current_status
    from public.reports r
    where r.id = new.report_id and r.lab_id = new.lab_id;
    select v.report_id into version_report
    from public.report_versions v
    where v.id = new.version_id and v.lab_id = new.lab_id;

    if current_status <> 'approved' or version_report is distinct from new.report_id then
      raise exception 'Only an approved report version can be published' using errcode = '23514';
    end if;
    if auth.uid() is not null then
      new.published_by := auth.uid();
    end if;
  elsif tg_op = 'UPDATE' then
    select r.status into current_status
    from public.reports r
    where r.id = new.report_id and r.lab_id = new.lab_id;
    if new.report_id is distinct from old.report_id
      or new.version_id is distinct from old.version_id
      or new.lab_id is distinct from old.lab_id
      or new.published_by is distinct from old.published_by
      or new.published_at is distinct from old.published_at
      or current_status <> 'published'
      or old.withdrawn_at is not null
      or new.withdrawn_at is null then
      raise exception 'Only an active publication can be withdrawn' using errcode = '23514';
    end if;
    if auth.uid() is not null then
      new.withdrawn_at := now();
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.set_audit_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    new.actor_id := auth.uid();
  end if;
  return new;
end;
$$;

create trigger enforce_report_workflow
  before insert or update on public.reports
  for each row execute function public.enforce_report_workflow();
create trigger validate_report_version
  before insert on public.report_versions
  for each row execute function public.validate_report_version();
create trigger validate_report_review
  before insert on public.report_reviews
  for each row execute function public.validate_report_review();
create trigger validate_report_publication
  before insert or update on public.report_publications
  for each row execute function public.validate_report_publication();
create trigger set_audit_actor
  before insert on public.audit_logs
  for each row execute function public.set_audit_actor();

drop trigger if exists on_auth_user_created_labcore on auth.users;
create trigger on_auth_user_created_labcore
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

revoke all on function public.is_patient_owner(uuid) from public, anon;
revoke all on function public.get_my_published_reports() from public, anon;
revoke all on function public.is_lab_auditor(uuid) from public, anon;
revoke all on function public.is_lab_member(uuid) from public, anon;
revoke all on function public.has_lab_permission(uuid, text) from public, anon;
revoke all on function public.has_order_item_access(uuid, uuid) from public, anon;
revoke all on function public.has_report_access(uuid, uuid) from public, anon;
revoke all on function public.next_patient_code(uuid) from public, anon;
revoke all on function public.next_invoice_number(uuid) from public, anon;
revoke all on function public.assign_patient_code() from public, anon, authenticated;
revoke all on function public.assign_invoice_number() from public, anon, authenticated;
revoke all on function public.guard_invoice() from public, anon, authenticated;
revoke all on function public.guard_order_item() from public, anon, authenticated;
revoke all on function public.guard_sample() from public, anon, authenticated;
revoke all on function public.guard_notification_update() from public, anon, authenticated;
revoke all on function public.guard_notification_preference() from public, anon, authenticated;
revoke all on function public.guard_payment() from public, anon, authenticated;
revoke all on function public.guard_invoice_item() from public, anon, authenticated;
revoke all on function public.guard_support_access_grant() from public, anon, authenticated;
revoke all on function public.guard_credit_note() from public, anon, authenticated;
revoke all on function public.refresh_invoice_payment_status() from public, anon, authenticated;
revoke all on function public.expire_slot_holds() from public, anon, authenticated;
revoke all on function public.consume_activation_token(text) from public, anon, authenticated;
revoke all on function public.guard_resource_booking() from public, anon, authenticated;
revoke all on function public.guard_slot_hold() from public, anon, authenticated;
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.enforce_report_workflow() from public, anon, authenticated;
revoke all on function public.validate_report_version() from public, anon, authenticated;
revoke all on function public.validate_report_review() from public, anon, authenticated;
revoke all on function public.validate_report_publication() from public, anon, authenticated;
revoke all on function public.set_audit_actor() from public, anon, authenticated;
grant execute on function public.is_lab_member(uuid) to authenticated;
grant execute on function public.is_patient_owner(uuid) to authenticated;
grant execute on function public.get_my_published_reports() to authenticated;
grant execute on function public.is_lab_auditor(uuid) to authenticated;
grant execute on function public.has_lab_permission(uuid, text) to authenticated;
grant execute on function public.has_order_item_access(uuid, uuid) to authenticated;
grant execute on function public.has_report_access(uuid, uuid) to authenticated;
grant execute on function public.expire_slot_holds() to service_role;
grant execute on function public.consume_activation_token(text) to service_role;

alter table public.labs alter column slug set not null;
alter table public.appointments add constraint appointments_patient_lab_fk
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete restrict;
alter table public.portal_tokens add constraint portal_tokens_patient_lab_fk
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete cascade;

create trigger assign_patient_code
  before insert on public.patients
  for each row execute function public.assign_patient_code();
create trigger assign_invoice_number
  before insert on public.invoices
  for each row execute function public.assign_invoice_number();
create trigger guard_invoice_mutations
  before insert or update on public.invoices
  for each row execute function public.guard_invoice();
create trigger guard_order_item_mutations
  before update on public.order_items
  for each row execute function public.guard_order_item();
create trigger guard_sample_mutations
  before insert or update on public.samples
  for each row execute function public.guard_sample();
create trigger guard_notification_mutations
  before update on public.notifications
  for each row execute function public.guard_notification_update();
create trigger guard_notification_preference_mutations
  before insert or update or delete on public.notification_preferences
  for each row execute function public.guard_notification_preference();
create trigger guard_payment_mutations
  before insert or update on public.payments
  for each row execute function public.guard_payment();
create trigger guard_invoice_item_mutations
  before insert or update or delete on public.invoice_items
  for each row execute function public.guard_invoice_item();
create trigger guard_support_access_grant_mutations
  before insert or update on public.support_access_grants
  for each row execute function public.guard_support_access_grant();
create trigger guard_credit_note_mutations
  before insert on public.credit_notes
  for each row execute function public.guard_credit_note();
create trigger refresh_invoice_status_after_payment
  after insert or update on public.payments
  for each row execute function public.refresh_invoice_payment_status();
create trigger resource_booking_no_active_hold
  before insert or update on public.resource_bookings
  for each row execute function public.guard_resource_booking();
create trigger slot_hold_no_active_booking
  before insert or update on public.slot_holds
  for each row execute function public.guard_slot_hold();

do $$
declare
  table_name text;
  tenant_tables text[] := array[
    'lab_settings','lab_branding','patients','patient_contacts','patient_notes',
    'service_categories','services','service_packages','service_package_items',
    'resources','working_hours','holidays_closures','staff_shifts','staff_bookings',
    'appointments','resource_bookings','slot_holds','visits','order_items','samples',
    'invoices','invoice_items','payments','receipts','reports','report_versions',
    'report_reviews','report_publications','notifications','notification_preferences',
    'subscriptions','feature_flags','export_jobs','support_access_grants',
    'notification_templates','notification_deliveries','credit_notes','retention_settings',
    'external_doctor_links'
  ];
begin
  foreach table_name in array tenant_tables loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists lab_member_manage on public.%I', table_name);
    execute format(
      'create policy lab_member_manage on public.%I for all to authenticated using (public.is_lab_member(lab_id)) with check (public.is_lab_member(lab_id))',
      table_name
    );
  end loop;
end;
$$;

drop policy if exists patients_lab_access on public.patients;
drop policy if exists appointments_lab_access on public.appointments;
drop policy if exists resources_lab_access on public.resources;
drop policy if exists bookings_lab_access on public.resource_bookings;
drop policy if exists reports_lab_access on public.reports;
drop policy if exists portal_lab_access on public.portal_tokens;
drop policy if exists memberships_member_insert on public.memberships;
drop policy if exists audit_insert on public.audit_logs;

alter table public.patient_accounts enable row level security;
alter table public.patient_code_counters enable row level security;
alter table public.invoice_counters enable row level security;

create policy profile_self_read on public.profiles
  for select to authenticated using (
    id = (select auth.uid())
    or exists (
      select 1 from public.memberships m
      where m.user_id = profiles.id
        and (
          public.has_lab_permission(m.lab_id, 'scheduling.read')
          or public.has_lab_permission(m.lab_id, 'staff.manage')
        )
    )
  );
create policy profile_self_update on public.profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy membership_self_or_lab_read on public.memberships
  for select to authenticated using (
    user_id = (select auth.uid()) or public.is_lab_member(lab_id)
  );
grant select on public.memberships to authenticated;

create policy patient_account_read on public.patient_accounts
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'patients.read')
    or user_id = (select auth.uid())
  );
create policy portal_token_staff_read on public.portal_tokens
  for select to authenticated using (public.has_lab_permission(lab_id, 'patients.read'));

create policy patient_self_read on public.patients
  for select to authenticated using (public.is_patient_owner(id));
create policy patient_contact_self_read on public.patient_contacts
  for select to authenticated using (public.is_patient_owner(patient_id));
create policy patient_contact_self_update on public.patient_contacts
  for update to authenticated using (public.is_patient_owner(patient_id))
  with check (public.is_patient_owner(patient_id));

create policy patient_lab_read on public.labs
  for select to authenticated using (
    exists (
      select 1 from public.patient_accounts pa
      where pa.lab_id = labs.id and pa.user_id = (select auth.uid()) and pa.activated_at is not null
    )
  );
create policy patient_settings_read on public.lab_settings
  for select to authenticated using (
    exists (
      select 1 from public.patient_accounts pa
      where pa.lab_id = lab_settings.lab_id and pa.user_id = (select auth.uid()) and pa.activated_at is not null
    )
  );
create policy patient_branding_read on public.lab_branding
  for select to authenticated using (
    exists (
      select 1 from public.patient_accounts pa
      where pa.lab_id = lab_branding.lab_id and pa.user_id = (select auth.uid()) and pa.activated_at is not null
    )
  );
create policy patient_services_read on public.services
  for select to authenticated using (
    active and patient_visible and exists (
      select 1 from public.patient_accounts pa
      where pa.lab_id = services.lab_id and pa.user_id = (select auth.uid()) and pa.activated_at is not null
    )
  );

create policy patient_appointment_read on public.appointments
  for select to authenticated using (public.is_patient_owner(patient_id));
create policy patient_visit_read on public.visits
  for select to authenticated using (public.is_patient_owner(patient_id));
create policy patient_order_item_read on public.order_items
  for select to authenticated using (
    exists (
      select 1 from public.visits v
      where v.id = order_items.visit_id and public.is_patient_owner(v.patient_id)
    )
  );
create policy patient_invoice_read on public.invoices
  for select to authenticated using (public.is_patient_owner(patient_id));
create policy patient_invoice_item_read on public.invoice_items
  for select to authenticated using (
    exists (
      select 1 from public.invoices i
      where i.id = invoice_items.invoice_id and public.is_patient_owner(i.patient_id)
    )
  );
create policy patient_payment_read on public.payments
  for select to authenticated using (
    exists (
      select 1 from public.invoices i
      where i.id = payments.invoice_id and public.is_patient_owner(i.patient_id)
    )
  );
create policy patient_receipt_read on public.receipts
  for select to authenticated using (
    exists (
      select 1 from public.invoices i
      where i.id = receipts.invoice_id and public.is_patient_owner(i.patient_id)
    )
  );
create policy patient_notification_read on public.notifications
  for select to authenticated using (
    user_id = (select auth.uid())
    or (patient_id is not null and public.is_patient_owner(patient_id))
  );
create policy patient_notification_update_read_state on public.notifications
  for update to authenticated using (
    user_id = (select auth.uid())
    or (patient_id is not null and public.is_patient_owner(patient_id))
  ) with check (
    user_id = (select auth.uid())
    or (patient_id is not null and public.is_patient_owner(patient_id))
  );
drop policy if exists patient_notification_preferences_manage on public.notification_preferences;
create policy patient_notification_preferences_read on public.notification_preferences
  for select to authenticated using (
    user_id = (select auth.uid())
    or (patient_id is not null and public.is_patient_owner(patient_id))
  );
create policy patient_notification_preferences_insert on public.notification_preferences
  for insert to authenticated with check (
    patient_id is not null
    and public.is_patient_owner(patient_id)
    and (user_id is null or user_id = (select auth.uid()))
  );
create policy patient_notification_preferences_update on public.notification_preferences
  for update to authenticated using (
    user_id = (select auth.uid())
    or (patient_id is not null and public.is_patient_owner(patient_id))
  ) with check (
    user_id = (select auth.uid())
    or (patient_id is not null and public.is_patient_owner(patient_id))
  );

create policy audit_member_insert on public.audit_logs
  for insert to authenticated with check (
    lab_id is not null and public.has_lab_permission(lab_id, 'audit.write')
  );
create policy audit_admin_read on public.audit_logs
  for select to authenticated using (lab_id is not null and public.has_lab_permission(lab_id, 'audit.read'));

alter table public.permission_catalog enable row level security;
alter table public.role_default_permissions enable row level security;
alter table public.roles_permissions enable row level security;
create policy permission_catalog_authenticated_read on public.permission_catalog
  for select to authenticated using (true);
create policy default_permissions_authenticated_read on public.role_default_permissions
  for select to authenticated using (true);
create policy roles_permissions_admin_read on public.roles_permissions
  for select to authenticated using (public.has_lab_permission(lab_id, 'roles.manage'));
create policy roles_permissions_admin_insert on public.roles_permissions
  for insert to authenticated with check (public.has_lab_permission(lab_id, 'roles.manage'));
create policy roles_permissions_admin_update on public.roles_permissions
  for update to authenticated using (public.has_lab_permission(lab_id, 'roles.manage'))
  with check (public.has_lab_permission(lab_id, 'roles.manage'));
create policy roles_permissions_admin_delete on public.roles_permissions
  for delete to authenticated using (public.has_lab_permission(lab_id, 'roles.manage'));

do $$
declare
  permission_row record;
  policy_tables text[] := array[
    'lab_settings','lab_branding','patients','patient_contacts','patient_notes',
    'service_categories','services','service_packages','service_package_items',
    'resources','working_hours','holidays_closures','staff_shifts','staff_bookings',
    'appointments','resource_bookings','slot_holds','visits','order_items','samples',
    'invoices','invoice_items','payments','receipts','reports','report_versions',
    'report_reviews','report_publications','notifications','notification_preferences'
  ];
begin
  for permission_row in
    select * from (values
      ('lab_settings','settings.read','settings.manage','settings.manage'),
      ('lab_branding','settings.read','settings.manage','settings.manage'),
      ('patients','patients.read','patients.write','patients.write'),
      ('patient_contacts','patients.read','patients.write','patients.write'),
      ('patient_notes','notes.clinical.read','notes.clinical.write','notes.clinical.write'),
      ('service_categories','services.read','services.manage','services.manage'),
      ('services','services.read','services.manage','services.manage'),
      ('service_packages','services.read','services.manage','services.manage'),
      ('service_package_items','services.read','services.manage','services.manage'),
      ('resources','scheduling.read','scheduling.manage','scheduling.manage'),
      ('working_hours','scheduling.read','scheduling.manage','scheduling.manage'),
      ('holidays_closures','scheduling.read','scheduling.manage','scheduling.manage'),
      ('staff_shifts','scheduling.read','scheduling.manage','scheduling.manage'),
      ('staff_bookings','scheduling.read','scheduling.manage','scheduling.manage'),
      ('appointments','appointments.read','appointments.manage','appointments.manage'),
      ('resource_bookings','appointments.read','appointments.manage','appointments.manage'),
      ('slot_holds','appointments.read','appointments.manage','appointments.manage'),
      ('visits','orders.read','orders.manage','orders.manage'),
      ('order_items','orders.read','orders.manage','orders.manage'),
      ('samples','orders.read','orders.manage','orders.manage'),
      ('invoices','billing.read','billing.manage','billing.manage'),
      ('invoice_items','billing.read','billing.manage','billing.manage'),
      ('payments','billing.read','billing.manage','billing.manage'),
      ('receipts','billing.read','billing.manage','billing.manage'),
      ('reports','reports.read','reports.upload','reports.review'),
      ('report_versions','reports.read','reports.upload',null),
      ('report_reviews','reports.read','reports.review',null),
      ('report_publications','reports.read','reports.publish','reports.publish'),
      ('notifications','notifications.read','notifications.manage','notifications.manage'),
      ('notification_preferences','notifications.read','notifications.manage','notifications.manage')
      ,('subscriptions','settings.read',null,null)
      ,('feature_flags','settings.read',null,null)
      ,('export_jobs','export.run','export.run',null)
      ,('support_access_grants','support.access.manage','support.access.manage','support.access.manage')
      ,('notification_templates','settings.read','settings.manage','settings.manage')
      ,('notification_deliveries','notifications.read',null,null)
      ,('credit_notes','billing.read','billing.manage',null)
      ,('retention_settings','settings.read','settings.manage','settings.manage')
      ,('external_doctor_links','reports.read','settings.manage','settings.manage')
    ) as permission_map(table_name, read_permission, insert_permission, update_permission)
  loop
    if permission_row.table_name = any(policy_tables) then
      execute format('drop policy if exists lab_member_manage on public.%I', permission_row.table_name);
      execute format('drop policy if exists lab_member_read on public.%I', permission_row.table_name);
      execute format('drop policy if exists lab_member_insert on public.%I', permission_row.table_name);
      execute format('drop policy if exists lab_member_update on public.%I', permission_row.table_name);

      execute format(
        'create policy lab_member_read on public.%I for select to authenticated using (public.has_lab_permission(lab_id, %L))',
        permission_row.table_name, permission_row.read_permission
      );
      if permission_row.insert_permission is not null then
        execute format(
          'create policy lab_member_insert on public.%I for insert to authenticated with check (public.has_lab_permission(lab_id, %L))',
          permission_row.table_name, permission_row.insert_permission
        );
      end if;
      if permission_row.update_permission is not null then
        execute format(
          'create policy lab_member_update on public.%I for update to authenticated using (public.has_lab_permission(lab_id, %L)) with check (public.has_lab_permission(lab_id, %L))',
          permission_row.table_name, permission_row.update_permission, permission_row.update_permission
        );
      end if;
    end if;
  end loop;
end;
$$;

alter table public.plans enable row level security;
create policy active_plans_read on public.plans
  for select to authenticated using (active);

drop policy if exists lab_member_read on public.visits;
create policy visit_case_read on public.visits
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'orders.read')
    and exists (
      select 1 from public.order_items oi
      where oi.visit_id = visits.id
        and public.has_order_item_access(lab_id, oi.id)
    )
  );

drop policy if exists lab_member_read on public.order_items;
create policy order_item_assigned_read on public.order_items
  for select to authenticated using (public.has_order_item_access(lab_id, id));
drop policy if exists lab_member_update on public.order_items;
create policy order_item_assigned_update on public.order_items
  for update to authenticated using (
    public.has_order_item_access(lab_id, id)
    and public.has_lab_permission(lab_id, 'orders.manage')
  ) with check (
    public.has_order_item_access(lab_id, id)
    and public.has_lab_permission(lab_id, 'orders.manage')
  );

drop policy if exists lab_member_read on public.samples;
create policy sample_assigned_read on public.samples
  for select to authenticated using (public.has_order_item_access(lab_id, order_item_id));
drop policy if exists lab_member_insert on public.samples;
create policy sample_assigned_insert on public.samples
  for insert to authenticated with check (
    public.has_order_item_access(lab_id, order_item_id)
    and public.has_lab_permission(lab_id, 'orders.manage')
  );
drop policy if exists lab_member_update on public.samples;
create policy sample_assigned_update on public.samples
  for update to authenticated using (
    public.has_order_item_access(lab_id, order_item_id)
    and public.has_lab_permission(lab_id, 'orders.manage')
  ) with check (
    public.has_order_item_access(lab_id, order_item_id)
    and public.has_lab_permission(lab_id, 'orders.manage')
  );

drop policy if exists lab_member_read on public.reports;
create policy report_assigned_read on public.reports
  for select to authenticated using (public.has_report_access(lab_id, id));
drop policy if exists lab_member_insert on public.reports;
create policy report_assigned_insert on public.reports
  for insert to authenticated with check (
    public.has_lab_permission(lab_id, 'reports.upload')
    and order_item_id is not null
    and public.has_order_item_access(lab_id, order_item_id)
  );
drop policy if exists lab_member_update on public.reports;
drop policy if exists report_publish_update on public.reports;
drop policy if exists report_upload_update on public.reports;
create policy report_assigned_review_update on public.reports
  for update to authenticated using (
    public.has_lab_permission(lab_id, 'reports.review')
    and public.has_report_access(lab_id, id)
  ) with check (
    public.has_lab_permission(lab_id, 'reports.review')
    and public.has_report_access(lab_id, id)
  );
create policy report_assigned_publish_update on public.reports
  for update to authenticated using (
    public.has_lab_permission(lab_id, 'reports.publish')
    and public.has_report_access(lab_id, id)
  ) with check (
    public.has_lab_permission(lab_id, 'reports.publish')
    and public.has_report_access(lab_id, id)
  );
create policy report_assigned_upload_update on public.reports
  for update to authenticated using (
    public.has_lab_permission(lab_id, 'reports.upload')
    and public.has_report_access(lab_id, id)
  ) with check (
    public.has_lab_permission(lab_id, 'reports.upload')
    and public.has_report_access(lab_id, id)
  );

drop policy if exists lab_member_read on public.report_versions;
create policy report_version_assigned_read on public.report_versions
  for select to authenticated using (public.has_report_access(lab_id, report_id));
drop policy if exists lab_member_read on public.report_reviews;
create policy report_review_assigned_read on public.report_reviews
  for select to authenticated using (public.has_report_access(lab_id, report_id));
drop policy if exists lab_member_read on public.report_publications;
create policy report_publication_assigned_read on public.report_publications
  for select to authenticated using (public.has_report_access(lab_id, report_id));

drop policy if exists lab_member_insert on public.export_jobs;
drop policy if exists lab_member_read on public.export_jobs;
create policy export_job_insert_own on public.export_jobs
  for insert to authenticated with check (
    requested_by = (select auth.uid())
    and public.has_lab_permission(lab_id, 'export.run')
  );
create policy export_job_read_own on public.export_jobs
  for select to authenticated using (
    requested_by = (select auth.uid())
    and public.has_lab_permission(lab_id, 'export.run')
  );

drop policy if exists lab_member_insert on public.report_reviews;
drop policy if exists lab_member_update on public.report_reviews;

drop policy if exists lab_member_insert on public.report_versions;
create policy report_version_insert_by_uploader on public.report_versions
  for insert to authenticated with check (
    uploaded_by = (select auth.uid())
    and public.has_lab_permission(lab_id, 'reports.upload')
    and public.has_report_access(lab_id, report_id)
  );
drop policy if exists lab_member_insert on public.report_reviews;
create policy report_review_insert_by_reviewer on public.report_reviews
  for insert to authenticated with check (
    reviewer_id = (select auth.uid())
    and public.has_lab_permission(lab_id, 'reports.review')
    and public.has_report_access(lab_id, report_id)
  );
drop policy if exists lab_member_insert on public.report_publications;
create policy report_publication_insert_by_publisher on public.report_publications
  for insert to authenticated with check (
    published_by = (select auth.uid())
    and public.has_lab_permission(lab_id, 'reports.publish')
    and public.has_report_access(lab_id, report_id)
  );

do $$
declare
  target record;
begin
  for target in
    select table_schema, table_name
    from information_schema.columns
    where table_schema = 'public' and column_name = 'updated_at'
  loop
    execute format(
      'drop trigger if exists touch_updated_at on %I.%I',
      target.table_schema, target.table_name
    );
    execute format(
      'create trigger touch_updated_at before update on %I.%I for each row execute function public.touch_updated_at()',
      target.table_schema, target.table_name
    );
  end loop;
end;
$$;

create or replace function public.storage_lab_id(object_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when (storage.foldername(object_name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then ((storage.foldername(object_name))[1])::uuid
    else null
  end;
$$;

create or replace function public.storage_report_id(object_name text)
returns uuid
language sql
stable
set search_path = ''
as $$
  select case
    when (storage.foldername(object_name))[3] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then ((storage.foldername(object_name))[3])::uuid
    else null
  end;
$$;

revoke all on function public.storage_lab_id(text) from public, anon;
revoke all on function public.storage_report_id(text) from public, anon;
grant execute on function public.storage_lab_id(text) to authenticated;
grant execute on function public.storage_report_id(text) to authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values
  ('reports','reports',false,26214400,array['application/pdf','image/jpeg','image/png']),
  ('branding','branding',false,5242880,array['image/jpeg','image/png','image/webp']),
  ('attachments','attachments',false,26214400,array['application/pdf','image/jpeg','image/png'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists lab_private_storage_read on storage.objects;
drop policy if exists lab_private_storage_insert on storage.objects;
drop policy if exists lab_private_storage_delete on storage.objects;
create policy lab_private_storage_read on storage.objects
  for select to authenticated using (
    (bucket_id = 'reports' and public.has_report_access(
      public.storage_lab_id(name), public.storage_report_id(name)
    ))
    or (bucket_id = 'branding' and public.has_lab_permission(
      public.storage_lab_id(name), 'settings.read'
    ))
    or (bucket_id = 'attachments' and public.has_report_access(
      public.storage_lab_id(name), public.storage_report_id(name)
    ))
  );
create policy lab_private_storage_insert on storage.objects
  for insert to authenticated with check (
    (bucket_id = 'reports'
      and public.has_lab_permission(public.storage_lab_id(name), 'reports.upload')
      and public.has_report_access(public.storage_lab_id(name), public.storage_report_id(name)))
    or (bucket_id = 'branding' and public.has_lab_permission(
      public.storage_lab_id(name), 'settings.manage'
    ))
    or (bucket_id = 'attachments'
      and public.has_lab_permission(public.storage_lab_id(name), 'reports.upload')
      and public.has_report_access(public.storage_lab_id(name), public.storage_report_id(name)))
  );
create policy lab_private_storage_delete on storage.objects
  for delete to authenticated using (
    (bucket_id = 'reports'
      and public.has_lab_permission(public.storage_lab_id(name), 'reports.publish')
      and public.has_report_access(public.storage_lab_id(name), public.storage_report_id(name)))
    or (bucket_id = 'branding' and public.has_lab_permission(
      public.storage_lab_id(name), 'settings.manage'
    ))
    or (bucket_id = 'attachments'
      and public.has_lab_permission(public.storage_lab_id(name), 'reports.publish')
      and public.has_report_access(public.storage_lab_id(name), public.storage_report_id(name)))
  );
