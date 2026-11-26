alter table public.labs
  add column if not exists city text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists address text,
  add column if not exists logo_path text,
  add column if not exists receipt_format text not null default 'thermal_80mm'
    check (receipt_format in ('thermal_80mm','a4_lab_memo')),
  add column if not exists receipt_footer text;

alter table public.services
  add column if not exists fasting_required boolean not null default false,
  add column if not exists method text,
  add column if not exists normal_range text;

create table if not exists public.role_default_page_grants (
  role_key text not null,
  page_key text not null check (page_key in (
    'dashboard','test_billing','tests','departments','appointments','scheduling','samples','patients','reports',
    'invoice_history','referring_doctors','reagent_stock','expenses','analytics',
    'manage_users','print_requests','my_print_requests','settings','trash_bin','help'
  )),
  primary key (role_key, page_key)
);

create table if not exists public.page_grants (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  page_key text not null check (page_key in (
    'dashboard','test_billing','tests','departments','appointments','scheduling','samples','patients','reports',
    'invoice_history','referring_doctors','reagent_stock','expenses','analytics',
    'manage_users','print_requests','my_print_requests','settings','trash_bin','help'
  )),
  granted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (lab_id, user_id, page_key),
  foreign key (lab_id, user_id) references public.memberships(lab_id, user_id) on delete cascade
);

alter table public.role_default_page_grants
  drop constraint if exists role_default_page_grants_page_key_check;
alter table public.role_default_page_grants
  add constraint role_default_page_grants_page_key_check check (page_key in (
    'dashboard','test_billing','tests','departments','appointments','scheduling','samples','patients','reports',
    'invoice_history','referring_doctors','reagent_stock','expenses','analytics',
    'manage_users','print_requests','my_print_requests','settings','trash_bin','help'
  ));

alter table public.page_grants
  drop constraint if exists page_grants_page_key_check;
alter table public.page_grants
  add constraint page_grants_page_key_check check (page_key in (
    'dashboard','test_billing','tests','departments','appointments','scheduling','samples','patients','reports',
    'invoice_history','referring_doctors','reagent_stock','expenses','analytics',
    'manage_users','print_requests','my_print_requests','settings','trash_bin','help'
  ));

insert into public.role_default_page_grants(role_key, page_key)
select defaults.role_key, defaults.page_key
from (values
  ('lab_admin','dashboard'),('lab_admin','test_billing'),('lab_admin','tests'),
  ('lab_admin','departments'),('lab_admin','samples'),('lab_admin','patients'),
  ('lab_admin','appointments'),('lab_admin','scheduling'),
  ('lab_admin','reports'),('lab_admin','invoice_history'),('lab_admin','referring_doctors'),
  ('lab_admin','reagent_stock'),('lab_admin','expenses'),('lab_admin','analytics'),
  ('lab_admin','manage_users'),('lab_admin','print_requests'),('lab_admin','my_print_requests'),
  ('lab_admin','settings'),('lab_admin','trash_bin'),('lab_admin','help'),
  ('lab_manager','dashboard'),('lab_manager','tests'),('lab_manager','departments'),
  ('lab_manager','appointments'),('lab_manager','scheduling'),
  ('lab_manager','samples'),('lab_manager','reports'),('lab_manager','referring_doctors'),
  ('lab_manager','reagent_stock'),('lab_manager','help'),
  ('receptionist','dashboard'),('receptionist','test_billing'),('receptionist','patients'),
  ('receptionist','appointments'),
  ('receptionist','samples'),('receptionist','invoice_history'),
  ('receptionist','my_print_requests'),('receptionist','help'),
  ('technician','dashboard'),('technician','samples'),('technician','reports'),('technician','help'),
  ('billing_staff','dashboard'),('billing_staff','invoice_history'),('billing_staff','patients'),
  ('billing_staff','expenses'),('billing_staff','analytics'),('billing_staff','help'),
  ('reporting_doctor','dashboard'),('reporting_doctor','reports'),
  ('reporting_doctor','patients'),('reporting_doctor','help')
) as defaults(role_key, page_key)
on conflict do nothing;

insert into public.page_grants(lab_id, user_id, page_key)
select m.lab_id, m.user_id, d.page_key
from public.memberships m
join public.role_default_page_grants d on d.role_key = m.role
where m.active
on conflict (lab_id, user_id, page_key) do nothing;

insert into public.permission_catalog(permission_key, description) values
  ('doctors.read','Read referring doctor directory'),
  ('doctors.manage','Manage referring doctor directory'),
  ('inventory.read','Read reagent inventory'),
  ('inventory.manage','Manage reagent inventory'),
  ('expenses.read','Read expenses'),
  ('expenses.manage','Manage expenses'),
  ('print_requests.read','Read print requests'),
  ('print_requests.manage','Manage print requests')
on conflict (permission_key) do nothing;

insert into public.role_default_permissions(role_key, permission_key)
select defaults.role_key, defaults.permission_key
from (values
  ('lab_admin','doctors.read'),('lab_admin','doctors.manage'),
  ('lab_admin','inventory.read'),('lab_admin','inventory.manage'),
  ('lab_admin','expenses.read'),('lab_admin','expenses.manage'),
  ('lab_admin','print_requests.read'),('lab_admin','print_requests.manage'),
  ('lab_manager','services.read'),('lab_manager','services.manage'),
  ('lab_manager','orders.read'),('lab_manager','orders.manage'),
  ('lab_manager','appointments.read'),('lab_manager','appointments.manage'),
  ('lab_manager','scheduling.read'),('lab_manager','scheduling.manage'),
  ('lab_manager','reports.read'),('lab_manager','reports.upload'),
  ('lab_manager','doctors.read'),('lab_manager','doctors.manage'),
  ('lab_manager','inventory.read'),('lab_manager','inventory.manage'),
  ('lab_manager','notifications.read'),('lab_manager','audit.write'),
  ('billing_staff','expenses.read'),('billing_staff','expenses.manage'),
  ('billing_staff','analytics.read'),('billing_staff','billing.read'),
  ('billing_staff','billing.manage'),('billing_staff','patients.read'),
  ('receptionist','print_requests.read'),('receptionist','print_requests.manage'),
  ('receptionist','billing.discount'),
  ('technician','orders.read'),('technician','orders.manage'),
  ('technician','reports.read'),('technician','reports.upload')
) as defaults(role_key, permission_key)
on conflict do nothing;

insert into public.roles_permissions(lab_id, role_key, permission_key, allowed)
select m.lab_id, defaults.role_key, defaults.permission_key, true
from public.memberships m
join (values
  ('lab_manager','services.read'),('lab_manager','services.manage'),
  ('lab_manager','orders.read'),('lab_manager','orders.manage'),
  ('lab_manager','reports.read'),('lab_manager','reports.upload'),
  ('lab_manager','doctors.read'),('lab_manager','doctors.manage'),
  ('lab_manager','inventory.read'),('lab_manager','inventory.manage'),
  ('billing_staff','expenses.read'),('billing_staff','expenses.manage'),
  ('billing_staff','analytics.read')
) as defaults(role_key, permission_key) on defaults.role_key = m.role
on conflict (lab_id, role_key, permission_key)
do update set allowed = excluded.allowed, updated_at = now();

create table if not exists public.referring_doctors (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  full_name text not null,
  clinic text,
  phone text,
  email text,
  specialty text,
  commission_percent numeric(5,2) not null default 0
    check (commission_percent between 0 and 100),
  address text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, lab_id)
);

create table if not exists public.reagent_stock (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  name text not null,
  quantity numeric(12,2) not null default 0 check (quantity >= 0),
  reorder_level numeric(12,2) not null default 0 check (reorder_level >= 0),
  expiry_date date,
  supplier text,
  batch_number text,
  unit_price numeric(12,2) not null default 0 check (unit_price >= 0),
  storage text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, lab_id)
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  expense_date date not null default current_date,
  category text not null,
  note text not null,
  amount numeric(12,2) not null check (amount > 0),
  paid_via text not null check (paid_via in ('cash','bank_transfer','card','other')),
  receipt_number text,
  created_by uuid references auth.users(id),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, lab_id)
);

create table if not exists public.print_requests (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  requested_by uuid not null references auth.users(id),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','completed')),
  decision_reason text,
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (invoice_id, lab_id) references public.invoices(id, lab_id)
);

create table if not exists public.report_results (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null,
  order_item_id uuid not null,
  result_text text not null default '',
  status text not null default 'awaiting_result'
    check (status in ('awaiting_result','entered','changes_required','approved','published')),
  entered_by uuid references auth.users(id),
  reviewed_by uuid references auth.users(id),
  published_by uuid references auth.users(id),
  entered_at timestamptz,
  reviewed_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lab_id, order_item_id),
  unique (id, lab_id),
  foreign key (patient_id, lab_id) references public.patients(id, lab_id) on delete restrict,
  foreign key (order_item_id, lab_id) references public.order_items(id, lab_id) on delete cascade
);

create table if not exists public.report_result_links (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  report_result_id uuid not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (report_result_id, lab_id)
    references public.report_results(id, lab_id) on delete cascade
);

create or replace function public.has_lab_page_access(target_lab uuid, target_page text)
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
      join public.page_grants pg
        on pg.lab_id = m.lab_id and pg.user_id = m.user_id
      where m.lab_id = target_lab
        and m.user_id = (select auth.uid())
        and m.active
        and pg.page_key = target_page
    );
$$;

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
          when target_permission like 'orders.%' then
            public.has_lab_page_access(target_lab, 'samples')
            or public.has_lab_page_access(target_lab, 'test_billing')
          when target_permission like 'billing.%' then
            public.has_lab_page_access(target_lab, 'invoice_history')
            or public.has_lab_page_access(target_lab, 'test_billing')
          when target_permission like 'reports.%' then
            public.has_lab_page_access(target_lab, 'reports')
          when target_permission like 'appointments.%'
            or target_permission like 'scheduling.%' then
            public.has_lab_page_access(target_lab, 'dashboard')
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

create or replace function public.refresh_default_page_grants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.role is not distinct from old.role then
    return new;
  end if;

  delete from public.page_grants
  where lab_id = new.lab_id and user_id = new.user_id;

  if new.active then
    insert into public.page_grants(lab_id, user_id, page_key)
    select new.lab_id, new.user_id, d.page_key
    from public.role_default_page_grants d
    where d.role_key = new.role
    on conflict (lab_id, user_id, page_key) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists refresh_default_page_grants on public.memberships;
create trigger refresh_default_page_grants
  after insert or update of role, active on public.memberships
  for each row execute function public.refresh_default_page_grants();

alter table public.role_default_page_grants enable row level security;
alter table public.page_grants enable row level security;
alter table public.referring_doctors enable row level security;
alter table public.reagent_stock enable row level security;
alter table public.expenses enable row level security;
alter table public.print_requests enable row level security;
alter table public.report_results enable row level security;
alter table public.report_result_links enable row level security;

drop policy if exists page_grants_self_or_admin_read on public.page_grants;
create policy page_grants_self_or_admin_read on public.page_grants
  for select to authenticated using (
    user_id = (select auth.uid())
    or public.has_lab_permission(lab_id, 'staff.manage')
  );
drop policy if exists role_default_page_grants_read on public.role_default_page_grants;
create policy role_default_page_grants_read on public.role_default_page_grants
  for select to authenticated using (true);

drop policy if exists referring_doctors_lab_read on public.referring_doctors;
create policy referring_doctors_lab_read on public.referring_doctors
  for select to authenticated using (
    deleted_at is null and public.has_lab_permission(lab_id, 'doctors.read')
  );
drop policy if exists reagent_stock_lab_read on public.reagent_stock;
create policy reagent_stock_lab_read on public.reagent_stock
  for select to authenticated using (
    deleted_at is null and public.has_lab_permission(lab_id, 'inventory.read')
  );
drop policy if exists expenses_lab_read on public.expenses;
create policy expenses_lab_read on public.expenses
  for select to authenticated using (
    deleted_at is null and public.has_lab_permission(lab_id, 'expenses.read')
  );
drop policy if exists print_requests_lab_read on public.print_requests;
create policy print_requests_lab_read on public.print_requests
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'print_requests.read')
    and (
      public.has_lab_permission(lab_id, 'staff.manage')
      or requested_by = (select auth.uid())
    )
  );
drop policy if exists report_results_lab_read on public.report_results;
create policy report_results_lab_read on public.report_results
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'reports.read')
  );
drop policy if exists report_result_links_lab_read on public.report_result_links;
create policy report_result_links_lab_read on public.report_result_links
  for select to authenticated using (
    public.has_lab_permission(lab_id, 'reports.publish')
  );

grant select on public.role_default_page_grants, public.page_grants,
  public.referring_doctors, public.reagent_stock, public.expenses,
  public.print_requests, public.report_results, public.report_result_links
  to authenticated;

revoke all on public.role_default_page_grants from public, anon;
revoke insert, update, delete on public.page_grants, public.referring_doctors,
  public.reagent_stock, public.expenses, public.print_requests,
  public.report_results, public.report_result_links
  from public, anon, authenticated;

revoke all on function public.has_lab_page_access(uuid, text) from public, anon;
grant execute on function public.has_lab_page_access(uuid, text) to authenticated;
revoke all on function public.has_lab_permission(uuid, text) from public, anon;
grant execute on function public.has_lab_permission(uuid, text) to authenticated;
revoke all on function public.refresh_default_page_grants() from public, anon, authenticated;
