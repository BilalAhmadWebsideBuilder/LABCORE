# Test plan

Run `npm run typecheck`, `npm run lint`, and `npm run build`.

Database verification uses pgTAP fixtures with two laboratories and two patients. Required and implemented cases cover cross-tenant lab/patient reads, staff cross-tenant patient/report writes, patient cross-patient reads, and published-only patient report visibility. Booking conflicts, activation-token expiry/revocation, and signed URL expiry remain separate setup decisions until Supabase local infrastructure is available.
