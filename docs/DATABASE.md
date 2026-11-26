# Supabase database setup

The database is designed for Supabase Postgres and Supabase Auth/Storage. Apply the numbered migrations in order.

## Apply the migrations

In the Supabase dashboard, select the project you intend to use and open **SQL Editor**. For a fresh setup, apply the migrations in order:

1. If the original foundation migration has not been applied, run `supabase/migrations/202611230001_labcore.sql`.
2. Run `supabase/migrations/202611230002_core_workflows.sql`.
3. Run `supabase/migrations/202611250003_platform_developer.sql`.
4. Run `supabase/migrations/202611250004_patient_account_policy_privilege.sql`.
5. Run `supabase/migrations/202611260005_patient_registration.sql`.
6. Run `supabase/migrations/202611260006_workspace_access_and_modules.sql`.
7. Run `supabase/migrations/202611260007_catalog_and_audit_workflows.sql`.
8. Run `supabase/migrations/202611260008_operational_workflows.sql`.
9. Run `supabase/migrations/202611260009_appointments_and_scheduling.sql`.
10. Run `supabase/migrations/202611260010_resource_staff_scheduling.sql`.
11. Run `supabase/migrations/202611260011_print_documents.sql`.
12. Run `supabase/migrations/202611260012_reagent_stock_movements.sql`.
13. Run `supabase/migrations/202611260013_patient_portal_signin.sql`.
14. Run `supabase/migrations/202611260014_report_upload_scanning.sql`.
15. Run `supabase/migrations/202611260015_retention_and_maintenance.sql`.
16. Run `supabase/migrations/202611260016_lab_onboarding.sql`.
17. For a development project only, run `supabase/seed.sql`.
18. Run `supabase/tests/schema_smoke.sql`; it raises an error if core tables, RLS, booking exclusions, permission grants, audit hooks, or case-scoped report and Storage policies are missing.

Run each migration as one script, in order, and do not rerun migrations that have already been applied. Migrations `006`–`015` extend the existing schema; they do not replace the earlier foundation or patient registration migrations. Do not apply the seed to staging or production. The seed contains synthetic patients and deliberately does not create login credentials.

## Create the global developer account

Create or invite `bilalahmad.web.dev@gmail.com` under **Authentication → Users** in the Supabase dashboard. After the user exists, run this once in SQL Editor as the project owner:

```sql
insert into public.platform_developers (user_id)
select id
from auth.users
where lower(email) = lower('bilalahmad.web.dev@gmail.com')
on conflict (user_id) do nothing;
```

The developer account can create and list laboratories, but cannot read patient, clinical, or billing data. Do not add this account to `public.memberships`; keep laboratory administrators as separate, lab-scoped accounts. The platform dashboard creates each lab and its default settings in one transaction.

## Create the first laboratory administrator

Create a user using **Authentication → Users → Add user** in the Supabase dashboard. Copy that user's UUID and add a membership for one of the seeded labs (or your own lab) using the SQL Editor as the project owner:

```sql
insert into public.memberships (lab_id, user_id, role, active)
values ('YOUR_LAB_UUID', 'YOUR_AUTH_USER_UUID', 'lab_admin', true)
on conflict (lab_id, user_id) do update set role = excluded.role, active = true;
```

Do not expose database-owner or service-role credentials to the browser. Membership creation is intentionally not allowed through direct authenticated table writes; implement staff invitations in a trusted server action or Edge Function.

## New workspace modules

Migration `006` adds per-user page grants, role-default page access, role-aware permission enforcement, and tenant-scoped referring-doctor, reagent-stock, expense, print-request, and text-result tables. Existing memberships receive their role defaults; new memberships receive defaults from a trigger. The platform developer remains excluded from tenant data.

Migration `007` adds redacted row-change audit triggers and a permission-checked catalog RPC for departments, tests, referring doctors, reagents, and expenses. Direct writes to the test catalog are revoked from `authenticated`; use the RPC.

Migration `008` adds atomic visit/invoice/payment creation, sample status changes and order assignment, text result entry/review/publication, hashed report links, analytics, staff access updates, settings, print requests, archive/restore, and related permission checks. Migration `009` adds appointment creation/cancellation and weekly working-hour management, validates configured working hours, and prevents overlapping active appointments for one patient. Operational writes go through RPCs or the trusted staff-invitation Edge Function. Each tenant-row mutation is recorded by the audit trigger; patient registration and patient archive/restore use explicit redacted audit events.

Migration `010` adds permission-checked resource management and bookings, staff shift and leave scheduling, active-staff/resource listing, overlap protection for staff shifts, and revokes direct authenticated writes to scheduling tables. Resource bookings and staff shifts are audit-logged by the existing redacted row-change trigger.

Migration `011` adds read-only, permission-checked invoice and published-report print data RPCs. The app renders print views that users can print or save as PDF in their browser; it does not store generated PDF files.

Migration `012` adds an append-only reagent stock movement ledger and atomic balance updates. Quantity changes require a movement row in the same transaction; inventory metadata is saved separately from received, used, and adjustment entries.

Migration `013` adds patient-session verification and a patient-scoped published-result RPC. Patients sign in through Supabase Auth; the RPC returns only published results for activated patient-account mappings belonging to that signed-in user.

Migration `014` adds private report attachments with assigned-case access, a clean-scan-only registration RPC reserved for `service_role`, and a report attachment list/path RPC. Configure and deploy the `scan-report-upload` Edge Function before enabling uploads. It validates PDF/JPEG/PNG signatures and size, scans bytes before permanent storage, and fails closed if the scanner is unavailable. Configure `MALWARE_SCANNER_URL` and `MALWARE_SCANNER_API_KEY` as Edge Function secrets. The scanner endpoint must accept a raw binary POST with `Authorization: Bearer <key>` and `X-File-Mime-Type`, returning JSON `{ "status": "clean", "engine": "scanner name" }` only after a successful scan; `"infected"` rejects the file, and all other responses/errors reject without storing. Use a scanner service operated within your trusted environment; do not send patient files to an unapproved third party.

Migration `015` adds laboratory retention-policy management and a service-role maintenance RPC. The scheduled cleanup expires old slot holds and removes portal-token records expired for at least 30 days, except in legal-hold labs. It does not delete patient, report, invoice, or audit records. Retention days are policy metadata only; have qualified privacy/legal staff approve a deletion schedule before adding clinical-data purges.

Migration `016` adds `create_lab_with_admin`, an atomic platform-developer RPC that creates the laboratory, settings, lab administrator membership, default page grants, and an audit event. The administrator must already exist in Supabase Auth. It refuses platform developers and users who already have an active lab membership, preserving the application's single-laboratory sign-in model.

### Staff invitations

Deploy `supabase/functions/invite-lab-staff` and configure its Edge Function secrets in Supabase:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `APP_ORIGIN` (the exact public application origin, without a trailing slash)

The function validates the caller’s staff and role permissions, uses Supabase Auth’s email-invitation flow, and assigns the new user to the caller’s lab through an authenticated RPC. The service-role key must remain an Edge Function secret; never add it to `.env.local`, a `NEXT_PUBLIC_*` variable, the browser, or source control. Configure Supabase Auth SMTP and the `/reset-password` redirect URL before testing invitations. Invited users set their password through the Supabase Auth flow; the app never stores or emails a plaintext password.

Deploy `supabase/functions/scan-report-upload` separately and add `MALWARE_SCANNER_URL` and `MALWARE_SCANNER_API_KEY` to Edge Function secrets alongside the Supabase function environment. The configured scanner must be an HTTPS endpoint under your control, scan the complete binary body, and respond within 45 seconds. The permanent private bucket is written only after a clean verdict.

Deploy `supabase/functions/retention-cleanup` and set `RETENTION_JOB_SECRET` as a high-entropy Edge Function secret. Schedule a daily POST to `/functions/v1/retention-cleanup` with the `x-retention-job-secret` header. The function has JWT verification disabled only because the scheduler uses this separate secret; protect the secret as a credential and rotate it if exposed.

### Backups and recovery

Database backups are managed by the Supabase project and subscription, not by application migrations. In the Supabase dashboard, open the project’s database backup settings, enable the automatic backup/PITR options offered by the plan, and record the actual backup frequency, retention window, and recovery-point objective. Store any permitted backup exports in an encrypted, access-restricted location separate from the application project. Perform a restore drill into a separate test project before relying on backups. Do not export patient data to a personal device or an unapproved provider.

## What the schema enforces

- Tenant ownership on clinical and operational rows, membership-based role permissions, and row-level security.
- Patients can read only their own rows; published report metadata is returned through a column-limited RPC rather than direct access to internal report columns.
- Report review and publication transitions, uploader/approver separation by default, version metadata, SHA-256 shape, and a private report file path convention.
- Non-overlapping resource and staff bookings. Slot holds and resource bookings serialize on a per-resource transaction lock; confirmed bookings consume their hold.
- Per-lab, timezone-aware patient and invoice numbers assigned in the insert transaction.
- Single-use activation-token consumption is service-role-only; store a SHA-256 digest, never the raw token.
- Private Storage buckets for reports, branding, and attachments; authenticated staff policies are tenant- and permission-scoped.
- Report attachments are written by the trusted scanner function only after signature validation and a clean malware scan; staff downloads use 60-second signed URLs and assignment-aware access checks.
- Maintenance removes only expired portal-token records and slot holds; clinical records are never automatically purged by the default job.
- Append-only audit records for authenticated users (no update or delete policy).

Report objects and report-linked attachments must use the path `{lab_uuid}/{patient_uuid}/{report_uuid}/v{version}.{extension}` (for example, `.../v1.pdf`). The report and patient IDs must match the database records. Branding objects use `{lab_uuid}/...`. These path segments are part of the Storage authorization checks.

Staff email/password sign-in uses Supabase SSR cookies. Staff dashboard routes verify the signed-in user and active lab membership on the server. Uploads require the Edge Function and trusted scanner endpoint to be configured; do not treat signature checks alone as malware protection. Never use the service-role key in client code.

The workspace now includes tenant-scoped patient registration/search, service catalog, billing and payments, sample tracking, result review/publication, appointment and resource scheduling, staff shifts, invoice and published-report print-to-PDF views, patient sign-in and published-result access for activated patient accounts, malware-scanned report attachments, analytics, staff/page-grant management, expenses, inventory counts and movement history, referring doctors, settings, print requests, retention policy controls, and archive/restore. The result workflow currently stores plain text and exposes a 90-day bearer link; it is not a validated clinical reporting system. Patient-account provisioning/activation is still an administrator-managed setup step and not self-service. The scanner service and managed backup plan must be configured separately. Clinical data retention purge rules and full authenticated integration tests remain incomplete. Do not use real patient data until those workflows and independent security/clinical validation are complete.

## Slot-hold expiry

The `public.expire_slot_holds()` function is granted only to `service_role`. Configure a Supabase Cron job to invoke it periodically (for example, once per minute), or invoke it from a trusted scheduled Edge Function. Until that is configured, expired holds are cleaned up when another hold or resource booking for the same resource is attempted; they are not removed automatically while the lab is idle.

## Validation boundary

The SQL smoke test checks schema/security configuration, not end-to-end patient isolation. Before real patient data is used, add and run authenticated integration tests for two labs and two patients, role permissions, booking races, activation-token expiry/revocation, report publication, and signed-download expiry.
