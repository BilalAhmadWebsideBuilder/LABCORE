# LabCore

Accurate results. Trusted care.

## Setup

1. Install Node.js 20 or newer.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and set Supabase environment values. Keep `.env.local` private.
4. Apply the SQL setup in [`docs/DATABASE.md`](./docs/DATABASE.md) to your Supabase project. Do not run the seed against production.
5. Run `npm run dev`.

Open `/login`. Staff sign-in uses Supabase email/password credentials and active lab membership. Staff routes are `/lab`, `/doctor`, and `/platform`.

## Verification

- `npm run typecheck`
- `npm run lint`
- `npm run build`

## Demo safety

Never seed development credentials or fake patient data into production. The Supabase service-role key must remain server-only. Configure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in the root `.env.local`; never expose the service-role key.

Staff authentication and role-gated dashboard routes are connected. The platform dashboard manages lab metadata; lab and doctor dashboards remain sample data. Patient sign-in, password recovery, and live lab workflows are not implemented. Do not enter real patient information.
