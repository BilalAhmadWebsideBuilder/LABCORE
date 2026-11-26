# LabCore audit report

**Date:** 2026-11-26

**Scope:** Current Next.js 16/Supabase source, migrations 001–015, environment-file handling, seed data, tests, and the shared localhost login/workspace.

## Summary

- The existing teal LabCore mark is tracked at `public/brand/logo-mark-dark.svg`; the app favicon references it. No logo was replaced or renamed. The PWA manifest separately points to two PNG icons that are not present.
- `.env` and `.env.*` are ignored, with `.env.example` explicitly allowed. The tracked example contains variable names with blank values; no `.env` or `.env.local` file is tracked. A scan of repository history found no common Supabase secret-key/JWT-shaped values. `supabase/seed.sql` uses synthetic labs, patients, and tests, without login credentials.
- Static authorization review found no exploitable vulnerability in the reviewed tenant, page-grant, and report-access paths. It did identify three database-error paths that crash pages instead of returning a recoverable state (below).
- The workspace navigation and route definitions include the catalog, patient, billing, sample, report, scheduling, staff, inventory, analytics, and settings modules. The dashboard itself is minimal: one patient-count card and a patient-record shortcut.

## Browser observations

- `/login` shows the LabCore lockup, blue-gradient hero, staff/patient sign-in tabs, password visibility control, and a “Forgot password?” link.
- `/lab` shows the branded sidebar, workspace header, patient count, and patient-record shortcut. The browser console reports Next.js 16's unstable `Date.now()` prerender warning from `WorkspaceShell`.
- Opening the notification bell displays “Live alerts are not connected yet.” No low-stock alert is shown on the dashboard.
- The source HTML prototype referenced in the original request was not found in the repository, so pixel-by-pixel comparison against it was not possible.

## Findings, prioritized

1. **Availability:** unexpected `get_my_patient_reports` errors crash the patient portal; unexpected RPC/database errors crash report and invoice print pages. The security review found no data-exposure vulnerability in these paths.
2. **Broken account recovery:** forgot-password and reset-password pages are placeholders; users cannot recover or set a password through the app.
3. **Incomplete lab onboarding:** Create Lab creates lab metadata/settings but does not invite or add its first lab administrator.
4. **Incomplete alerts/dashboard:** the bell is static, and the dashboard has no inventory low-stock summary or alert state.
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
