# Test plan

Run `npm run typecheck`, `npm run lint`, and `npm run build`.

Database verification should use pgTAP or SQL scripts with two laboratories and two patients. Required cases cover cross-tenant reads/writes, cross-patient report access, booking conflicts, published-only patient report visibility, and signed URL expiry.
