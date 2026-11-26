# LabCore audit report

**Date:** 2026-11-26

**Scope:** Current Next.js 16/Supabase source, migrations 001–015, environment-file handling, seed data, tests, and the shared localhost login/workspace.

## Summary

- The existing teal LabCore mark is tracked at `public/brand/logo-mark-dark.svg`; the app favicon, Apple touch icon, login, patient portal, and workspace use the existing shared mark/wordmark. No logo was replaced or renamed. The PWA manifest now references the existing SVG instead of missing PNG files.
- `.env` and `.env.*` are ignored, with `.env.example` explicitly allowed. The tracked example contains variable names with blank values; no `.env` or `.env.local` file is tracked. A scan of repository history found no common Supabase secret-key/JWT-shaped values. `supabase/seed.sql` uses synthetic labs, patients, and tests, without login credentials.
- Static authorization review found no exploitable vulnerability in the reviewed tenant, page-grant, and report-access paths. It did identify three database-error paths that crash pages instead of returning a recoverable state (below).
- The workspace navigation and route definitions include the catalog, patient, billing, sample, report, scheduling, staff, inventory, analytics, and settings modules. The dashboard itself is minimal: one patient-count card and a patient-record shortcut.

## Browser observations

- `/login` shows the LabCore lockup, blue-gradient hero, staff/patient sign-in tabs, password visibility control, and a “Forgot password?” link.
- `/lab` shows the branded sidebar, workspace header, patient count, and patient-record shortcut. The browser console reports Next.js 16's unstable `Date.now()` prerender warning from `WorkspaceShell`.
- Opening the notification bell now shows tenant-scoped low-stock reagent alerts; the dashboard includes the same low-stock count.
- The source HTML prototype referenced in the original request was not found in the repository, so pixel-by-pixel comparison against it was not possible.

## Findings, prioritized

1. **Availability — fixed:** unexpected `get_my_patient_reports` errors and report/invoice print database errors now render recoverable states. The security review found no data-exposure vulnerability in these paths.
2. **Broken account recovery — fixed:** forgot-password and reset-password now use Supabase Auth email reset and password update flows.
3. **Lab onboarding — fixed:** Create Lab can atomically add an existing Supabase Auth administrator as the lab admin.
4. **Alerts/dashboard — fixed:** the bell and dashboard now show tenant-scoped reagent low-stock counts.
5. **Theme consistency:** the shell persists a light/dark preference, but key login/form colors are hard-coded and do not consistently follow the app's `data-theme` tokens.
6. **Missing PWA assets:** `public/manifest.webmanifest` references missing `icon-192.png` and `icon-512.png`.
7. **Migration resilience:** some routes show `DatabaseSetupNotice`, while the dashboard and the print/report paths can throw on database failures instead of failing gracefully.
8. **Test execution gap:** `supabase/tests/tenant-isolation.test.sql` contains fictional two-lab/two-patient fixtures and 10 pgTAP assertions for tenant and published-report reads. It does not cover cross-tenant writes. `npm run test:integration` could not connect to local Postgres at `127.0.0.1:54322`; the local Supabase/Docker stack must be started to execute it. There is no `npm test` script.

## Baseline checks

- `npm run lint`: passed in the prior baseline run.
- `npm run typecheck`: passed during this audit.
- `npm run build`: passed in the prior baseline run.
- `npm run test:integration`: blocked because local Postgres is not running.

No existing migration was changed during this audit. Findings will be addressed in order, and any required schema changes will be new migrations beginning at `202611260016`.
