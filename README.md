# LabCore

LabCore is a tenant-scoped laboratory operations application built with Next.js 16 and Supabase. It includes patient registration, test and sample workflows, billing, reports, scheduling, inventory, staff permissions, a patient portal, and audit logging. The existing teal-ring pulse logo, LabCore wordmark, and blue gradient visual identity are kept in the project.

Do not use real patient information until the system has been configured, tested, and independently reviewed for your clinical and privacy requirements.

## Requirements

- Node.js 20 or newer
- A Supabase project for deployed use
- Supabase CLI and Docker for local database integration tests

## Install and run

1. Install dependencies with `npm ci`.
2. Copy `.env.example` to `.env.local` and fill in the client-side Supabase URL and publishable/anon key. Keep `.env.local` private.
3. Apply the database migrations to the intended Supabase project in the order below. Do not apply migrations that are already recorded as applied.
4. For a development database only, apply `supabase/seed.sql`. It contains demo labs, tests, and fictional patients; never run it in production.
5. Start the app with `npm run dev`, then open `http://localhost:3000/login`.

The application environment reads `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (or `NEXT_PUBLIC_SUPABASE_ANON_KEY`). Never put a service-role key in a `NEXT_PUBLIC_*` variable or browser code.

## Database migration order

Apply migrations in this exact order for a fresh database:

1. `supabase/migrations/202611230001_labcore.sql`
2. `supabase/migrations/202611230002_core_workflows.sql`
3. `supabase/migrations/202611250003_platform_developer.sql`
4. `supabase/migrations/202611250004_patient_account_policy_privilege.sql`
5. `supabase/migrations/202611260005_patient_registration.sql`
6. `supabase/migrations/202611260006_workspace_access_and_modules.sql`
7. `supabase/migrations/202611260007_catalog_and_audit_workflows.sql`
8. `supabase/migrations/202611260008_operational_workflows.sql`
9. `supabase/migrations/202611260009_appointments_and_scheduling.sql`
10. `supabase/migrations/202611260010_resource_staff_scheduling.sql`
11. `supabase/migrations/202611260011_print_documents.sql`
12. `supabase/migrations/202611260012_reagent_stock_movements.sql`
13. `supabase/migrations/202611260013_patient_portal_signin.sql`
14. `supabase/migrations/202611260014_report_upload_scanning.sql`
15. `supabase/migrations/202611260015_retention_and_maintenance.sql`
16. `supabase/migrations/202611260016_lab_onboarding.sql`

See [`docs/DATABASE.md`](./docs/DATABASE.md) for migration notes, administrator setup, and the schema smoke test. Use synthetic data only in development and test projects.

## Deploy the three Edge Functions

Deploy functions from the repository root with the Supabase CLI. Set secrets in Supabase Function Secrets; do not commit them or copy them into the browser environment.

### Staff invitations

Deploy `supabase/functions/invite-lab-staff` with `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `APP_ORIGIN`. Configure Supabase Auth email/SMTP and the app redirect URL before sending invitations.

### Scanned report uploads

Deploy `supabase/functions/scan-report-upload` with the Supabase URL, anon key, service-role key, `APP_ORIGIN`, `MALWARE_SCANNER_URL`, and `MALWARE_SCANNER_API_KEY`. The scanner must be a trusted HTTPS service. Uploads fail closed until it returns a clean verdict.

### Retention cleanup

Deploy `supabase/functions/retention-cleanup` with `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and a high-entropy `RETENTION_JOB_SECRET`. Schedule a daily POST to `/functions/v1/retention-cleanup` with that secret in the `x-retention-job-secret` header. The function disables JWT verification in `supabase/config.toml` because this separate secret authenticates the scheduler; protect and rotate it like a credential.

## Backups and retention

Enable the automatic database backups and point-in-time recovery options available for your Supabase plan in the project dashboard. Record the backup frequency and recovery window, store permitted exports encrypted and access-restricted, and test a restore in a separate project.

The retention policy and cleanup are not a clinical-record deletion system. The scheduled job only expires old slot holds and removes sufficiently expired portal-token records; it honors legal holds and does not delete patient, report, invoice, or audit records. Have qualified privacy/legal staff approve any future clinical-data retention or deletion workflow.

## Tests and checks

For tenant-isolation integration tests, start the local Supabase stack with `npx supabase start`, then run `npm run test:integration`. The pgTAP test creates two labs, two lab administrators, and two activated patient accounts inside a transaction, checks cross-tenant access and published-report scoping, and rolls back its fixtures.

Run application checks with:

- `npm run lint`
- `npm run typecheck`
- `npm run build`

## Setup still required

- Configure Supabase Auth email delivery and deploy the invitation function.
- Configure and deploy a trusted malware scanner before enabling report uploads.
- Provision/activate patient accounts through the administrator workflow.
- Configure the trusted retention scheduler, managed backups, and a restore drill.
- Complete authenticated integration tests and an independent clinical/security review before production use.
