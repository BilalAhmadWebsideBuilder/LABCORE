# Security baseline

- Supabase Auth and Postgres RLS are the intended backend trust boundary.
- The service-role key is server-only and must never appear in `NEXT_PUBLIC_*` variables or client bundles.
- Staff sign-in uses Supabase SSR cookies; protected staff routes verify token claims and an active lab membership on the server.
- Tenant-owned reads and writes pass `lab_id` membership and role-permission checks.
- Global platform developers can create and list lab metadata only; they cannot access patient, clinical, or billing records. Developer accounts are explicitly allow-listed and must not also be assigned a lab membership.
- Lab administrators remain restricted to their own laboratory.
- Patient registration is performed by a permission-checking database RPC and writes a redacted audit event; patient list reads remain filtered by lab membership and RLS.
- Page grants and role permissions are both checked server-side and again by database helpers/RLS. Platform developers remain metadata-only and are not laboratory members.
- Catalog, billing, payment, sample, report, staff, settings, print-request, and archive/restore mutations use permission-checking RPCs. Tenant-row changes are recorded by a redacted audit trigger; the trigger records field names, not clinical or personal values.
- Appointment and weekly-hours writes use permission-checked RPCs. Appointment records are tenant-scoped, active overlapping appointments for a patient are rejected, and configured local working hours are enforced.
- Resource, resource-booking, and staff-shift mutations use `scheduling.manage`-checked RPCs; direct authenticated table writes are revoked. Active resource bookings and scheduled/leave shifts have database overlap protection, and row changes use the redacted audit trigger.
- Invoice print data requires `billing.read`; published-report print data requires `reports.read` and assigned-order access. Print endpoints return only the fields needed for the document and do not create or retain a PDF.
- Reagent stock balances change only through the inventory movement RPC. It locks the reagent row, validates the resulting balance, and records the signed movement and redacted audit event in the same transaction; authenticated users cannot write movement rows directly.
- Patient sign-in uses Supabase Auth. A second server-side check requires an activated patient-account mapping, and published report content is returned only through a security-definer RPC scoped to that user’s mapped patient records.
- Report file uploads require both report permissions and case assignment, validate magic bytes, and must receive a clean response from the configured trusted scanner before the private object is stored. Scanner errors fail closed. Attachment metadata registration is service-role-only and creates an audit event; downloads are assignment-checked and use signed URLs lasting 60 seconds.
- Retention controls store the lab’s policy and legal-hold state. The scheduled job only expires old holds and deletes expired portal-token records after a 30-day grace period, skipping labs on legal hold; it never purges clinical or audit records.
- Staff invitations use a Supabase Edge Function with a server-only service-role secret. The invited user receives an Auth email link; passwords are not stored or sent by the application.
- Patient report rows are visible only after publication; report file versions remain staff-only and must be fetched through a permission-checking server endpoint.
- Text result links store only a SHA-256 token digest, expire after 90 days, and expose only a minimal published report view. Treat the raw URL as a bearer credential and share it only with the intended patient.
- Membership creation and activation-token consumption are trusted-server operations.
- Report storage must remain private; downloads require permission re-checking and short-lived signed URLs.
- Audit records are append-only from the application role.

The SQL policies and staff sign-in are a foundation, not a production certification. Current result entry is plain text and does not provide clinical validation; print-to-PDF uses the user’s browser and saves no server-side PDF. Patient account provisioning/activation still requires an administrator workflow; the malware scanner service and Supabase managed backups must be configured and verified; clinical-data purge rules and full two-lab/two-patient integration tests remain incomplete. The analytics margin intentionally excludes reagent costs. Do not use real patient data until these gaps are addressed and a qualified security/clinical review is complete.
