# LabCore completion progress

## Completed

- Baseline audit saved in `docs/AUDIT-REPORT.md` and committed as `6262b67`.
- Static authorization review found no exploitable vulnerability in the reviewed scope.
- Added recoverable error states for the patient report portal and report/invoice print pages.
- Made the dashboard show a clear setup/error state instead of throwing on database access failures, and enforce the dashboard page grant.
- Added an optional isolated Next.js build directory so production builds can be checked without sharing the running development server's `.next` directory.
- Replaced placeholder forgot/reset password screens with Supabase Auth reset-link and password-update flows.
- Added tenant-scoped low-stock reagents to the dashboard and workspace notification menu.
- Updated PWA branding to reuse the existing tracked LabCore SVG and documented migration 016.
- Expanded the pgTAP tenant suite to 14 assertions, including staff read/write isolation in both laboratory directions and patient published-report isolation.

## Current validation

- `npm run lint`: passed for the recoverable-error task.
- `npm run typecheck`: passed for the recoverable-error task.
- `npm run build` with `LABCORE_NEXT_DIST_DIR=.next-build`: passed for the recoverable-error task.
- `npm run test:integration`: previously blocked because local Postgres at `127.0.0.1:54322` is not running.

## Remaining

1. Run Docker/local Supabase and execute the expanded 14-assertion pgTAP tenant-isolation tests.
2. Complete final route smoke review and visual consistency checks while preserving the existing logo.
3. Run the final lint, typecheck, build, test attempt, secret scan, and Git status review.
4. Commit and push the final test/documentation updates to `main`.

No existing migration has been edited. Any required schema changes start at `202611260016`.
