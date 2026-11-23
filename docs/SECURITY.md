# Security baseline

- Supabase Auth and Postgres RLS are the backend trust boundary.
- The service-role key is server-only and must never appear in `NEXT_PUBLIC_*` variables or client bundles.
- Tenant-owned writes must pass `lab_id` membership checks.
- Report storage must remain private; downloads require permission re-checking and short-lived signed URLs.
- Audit records are append-only from the application role.
