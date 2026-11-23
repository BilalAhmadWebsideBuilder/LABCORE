# LabCore

Accurate results. Trusted care.

## Setup

1. Install Node.js 20 or newer.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and set Supabase environment values.
4. Apply `supabase/migrations/202611230001_labcore.sql` to the development Supabase project.
5. Run `npm run dev`.

Open `/login`. Staff routes are `/lab`, `/doctor`, and `/platform`; patient preview is `/portal`.

## Verification

- `npm run typecheck`
- `npm run lint`
- `npm run build`

## Demo safety

Never seed development credentials or fake patient data into production. The Supabase service-role key must remain server-only.
