create extension if not exists "pgcrypto";
create extension if not exists "btree_gist";

create table public.labs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, user_id)
);

create table public.patients (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_code text not null,
  full_name text not null,
  phone text,
  date_of_birth date,
  national_id_ciphertext text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lab_id, patient_code)
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null references public.patients(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled',
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.resources (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  name text not null,
  resource_type text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.resource_bookings (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  resource_id uuid not null references public.resources(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint resource_no_overlap exclude using gist (
    resource_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (active)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null references public.patients(id),
  status text not null default 'pending_review',
  file_path text,
  sha256 text,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.portal_tokens (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.labs(id) on delete cascade,
  patient_id uuid not null references public.patients(id),
  token_hash text not null unique,
  purpose text not null default 'activation',
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  lab_id uuid references public.labs(id),
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  before_redacted jsonb,
  after_redacted jsonb,
  ip text,
  user_agent text,
  reason text,
  created_at timestamptz not null default now()
);

create or replace function public.is_lab_member(target_lab uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.memberships
    where lab_id = target_lab
      and user_id = auth.uid()
      and active = true
  );
$$;

alter table public.labs enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.patients enable row level security;
alter table public.appointments enable row level security;
alter table public.resources enable row level security;
alter table public.resource_bookings enable row level security;
alter table public.reports enable row level security;
alter table public.portal_tokens enable row level security;
alter table public.audit_logs enable row level security;

create policy labs_member_select on public.labs for select using (public.is_lab_member(id));
create policy memberships_member_select on public.memberships for select using (public.is_lab_member(lab_id));
create policy memberships_member_insert on public.memberships for insert with check (public.is_lab_member(lab_id));

create policy patients_lab_access on public.patients for all using (public.is_lab_member(lab_id)) with check (public.is_lab_member(lab_id));
create policy appointments_lab_access on public.appointments for all using (public.is_lab_member(lab_id)) with check (public.is_lab_member(lab_id));
create policy resources_lab_access on public.resources for all using (public.is_lab_member(lab_id)) with check (public.is_lab_member(lab_id));
create policy bookings_lab_access on public.resource_bookings for all using (public.is_lab_member(lab_id)) with check (public.is_lab_member(lab_id));
create policy reports_lab_access on public.reports for all using (public.is_lab_member(lab_id)) with check (public.is_lab_member(lab_id));
create policy portal_lab_access on public.portal_tokens for all using (public.is_lab_member(lab_id)) with check (public.is_lab_member(lab_id));

create policy audit_insert on public.audit_logs for insert with check (
  lab_id is null or public.is_lab_member(lab_id)
);
