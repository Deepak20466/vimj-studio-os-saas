Implemented requested admin and coach dashboard changes (web and Flutter).

- Students: activity labels and enrollment-based activity filter.
- Fees: searchable student picker, separate product charge, total in lists and PDF/CSV receipts.
- Coach receipts: optional billing date alongside monthly billing; selected date sets the month/year.
- Reports: month selection, previous month, student attendance PDF, activity attendance PDF, and activity/overall revenue PDF. Available from Reports and Attendance.
- Revenue uses paid monthly fee records, including products; payments for students enrolled in multiple activities are split equally to avoid double counting. Unassigned payments are shown separately.
- Session photos: coach web upload after session; admin viewer in both session roster and class list. Existing mobile coach photo capture retained. Photo access remains authenticated.
- Coach student contact numbers returned by roster API, shown in web/mobile, and preserved when editing.

Database migration applied successfully to the configured PostgreSQL database:
    .venv/Scripts/python -m alembic upgrade head
Upgraded from 0016 to 0017. Verified with `alembic current`: 0017 (head).

Verification:
    backend: .venv/Scripts/python -m unittest discover -s tests -v
    frontend: npm run build
    mobile: flutter analyze --no-pub --no-fatal-infos
Migration chain also validated through Alembic offline SQL generation.

Release verification (2026-10-02):
- Backend regression tests: 5 passed.
- Web production build: passed (existing bundle-size advisory).
- Flutter analysis: no errors/warnings; 17 existing informational style/deprecation notices.
- Flutter startup widget test: passed.
- Android release build: three ABI APKs built successfully.
- App version: 1.22.0+22; verified package com.vimjstudio.vimj_attendance.
- APK signatures verified and matched the previous mobile-v1.21.0 signing certificate.
- Backend URL compiled into APKs: https://vimj-backend.onrender.com.
- Database revision verified: 0017 (head).
- Production backend rollout confirmed: OpenAPI exposes the new /reports endpoint.
- GitHub release: https://github.com/Deepak20466/attendance-management/releases/tag/mobile-v1.22.0

APK SHA-256 checksums:
- app-arm64-v8a-release.apk: 2e16168b60871678dba5d84d5390551ea65bc5922be1a36e718406e11df40caf
- app-armeabi-v7a-release.apk: bbe66349d3dc853951e085020b7035fedf921f3fcf7bf4f907d8fb1f2985f8e2
- app-x86_64-release.apk: 2061fd63a1d468a421559ddff8dccb6f09e947561399f14c3ad794219d19519a

Final release checks (2026-10-02):
- Feature commit: b7fe22fb4b7399d849327470d2b4e8bdf48cf61c, pushed to origin/master.
- Release tag: mobile-v1.22.0, points to the feature commit.
- Re-ran all 5 backend regression tests, the web production build, Flutter analysis, and the Flutter startup test: passed; existing informational notices remain.
- Rechecked the configured PostgreSQL database: 0017 (head).
- Verified all three APK signatures and the SHA-256 values above; the ARM64 signing certificate matches mobile-v1.21.0.
- Recommended download for most Android phones: app-arm64-v8a-release.apk from the release linked above.

## 2026-10-07 Admin Attendance Visibility Controls

- In the Flutter Admin Attendance screen, the Student Attendance “All Attendance
  Records” and Coach Attendance Hide controls now sit beside their search fields,
  making them visible before the lists. When a list is collapsed, its title keeps
  a visible Show control.
- Search text, filters, records, and the existing per-admin visibility
  preferences retain their behavior.
- Each compact Show/Hide control has a section-specific tooltip for clarity and
  accessibility.
- Collapsed sections show a compact count of records matching the retained
  search and filters; the count is hidden while its list is loading.
- Login starts the shared `/health` warm-up while credentials are entered and
  opens the Admin/Coach dashboard shell immediately after authentication. The
  existing bounded timeout and actionable cold-start message remain. Render's
  free-tier wake delay is controlled by the host.
- Release target: mobile version `1.26.16+52`, tag `mobile-v1.26.16`, through
  `.github/workflows/release-mobile.yml` using the persistent signing key.
  Never commit or share the signing key.
- Verification: all 24 Flutter tests passed; Dart analysis completed with 0
  errors/warnings and 174 informational lints; local split-ABI Android release
  compilation succeeded for armeabi-v7a, arm64-v8a, and x86_64.
- Published from commit `7596400e03a5ed5a9ee4b8d5f5d0875cf7528d1b` by GitHub
  Actions run `37666207039`:
  https://github.com/Deepak20466/attendance-management/releases/tag/mobile-v1.26.16
- Published APK SHA-256: arm64-v8a
  `61746e803fa335ce9f86e41e971d7cf5f6f01eed435d2d2702e989ab378f2cf1`,
  armeabi-v7a `8e1a49165478e5365cccdb08556122ff70ed9ef2f047adc02270212f003b2938`,
  x86_64 `91d5670c4077002d10a127968cff009074447040216aef9a2d2ca3b3e1714267`.
  All assets match GitHub's published digests and pass `apksigner verify`; all
  use the persistent signing certificate SHA-256
  `7d128bae4a3851fe496175bbfd832733c83f4210de992403b4677554f32d7ea7`.

## 2026-10-08 Sticky Search Across Mobile Dashboards

- Search bars for scrolling lists across the Admin and Coach mobile dashboards
  stay visible while their matching list scrolls, then release when that
  section ends. Search bars already fixed above their lists remain visible.
- Admin Attendance keeps the Student Attendance and Coach Attendance
  Hide/Show controls beside their searches. The calendar's selected-day search
  also stays with its student attendance section.
- The shared mobile startup begins the API health warm-up before reading the
  saved session, overlapping startup work to make login/dashboard entry feel
  faster. The existing bounded timeout and actionable cold-start messaging
  remain.
- Release: version `1.26.17+53`, tag `mobile-v1.26.17`; feature commit
  `db051543491464ce868ee87d7c7f56d44fbd604b`.
- Verification: all 24 Flutter tests passed; Flutter analysis completed with
  no errors or warnings (196 informational notices); local split-ABI Android
  release compilation succeeded for armeabi-v7a, arm64-v8a, and x86_64.
- GitHub Actions run `37670879596` completed successfully and published the
  signed APKs: https://github.com/Deepak20466/attendance-management/releases/tag/mobile-v1.26.17
- Published APK SHA-256: arm64-v8a
  `d3c77398c46f426e510bb084bb62d1479be602d0040c1463004aca08a3bdd712`,
  armeabi-v7a
  `da94c736a73f90e5b71250526f01d3654cf7fe4422cf0cb6494732a6fe281fea`,
  x86_64 `4c7f6e7f47e8f4062d2d05a1230884e9f86977ffbd2a6ad9716d0f4d2ce8bc92`.
  All match GitHub's asset digests, pass `apksigner verify`, and use the
  persistent signing certificate SHA-256
  `7d128bae4a3851fe496175bbfd832733c83f4210de992403b4677554f32d7ea7`.

## 2026-10-08 Attendance Search Pagination and Login Connection

- Admin Student Attendance and Coach Attendance lists now request the records
  in pages of up to 500 and search the full filtered history. Admin and Coach
  calendar views also retrieve every page for the selected month; Coach's
  selected-day attendance search remains scoped to that calendar day.
- The attendance API accepts `limit` (1-500) and `offset` on student and coach
  list endpoints. Defaults preserve the existing first-page response for older
  clients. No database migration is required.
- Login keeps the early splash/login health warm-up and no longer starts a
  second health request at submit time, reducing duplicate traffic alongside
  authentication. Render cold-start time is still controlled by the host.
- Release target: mobile version `1.26.18+54`, tag `mobile-v1.26.18`, through
  `.github/workflows/release-mobile.yml` using the persistent signing key.
  Never commit or share the signing key.
- Verification: all 11 backend regression tests passed; all 26 Flutter tests
  passed; Flutter analysis completed with no errors or warnings (196
  informational lints); local split-ABI release compilation succeeded for
  armeabi-v7a, arm64-v8a, and x86_64.
- Production OpenAPI confirms `limit` and `offset` are live on both attendance
  list endpoints.
- Published from commit `5591851f49637def07afb1d841b2e7b6d39ce12e` by GitHub
  Actions run `37673858999`:
  https://github.com/Deepak20466/attendance-management/releases/tag/mobile-v1.26.18
- Published APK SHA-256: arm64-v8a
  `df30bf2ed86c944d9872eceeacb434027dcfc44c37a2d066f7022da9e5d79980`,
  armeabi-v7a `6fa33386271df8110b1fc211489a3daf3ab6c3971d997613e3908704f61e66ea`,
  x86_64 `a3500726b655fbc71e4af23a6684d804ecc944753d9c07592313a9fa0ca28060`.
  All match GitHub's asset digests and pass `apksigner verify`; all use the
  persistent signing certificate SHA-256
  `7d128bae4a3851fe496175bbfd832733c83f4210de992403b4677554f32d7ea7`.

## 2026-10-08 Full Search and Faster Attendance History

- Admin Student Attendance and Coach Attendance now load the newest 500 records
  first and provide a Load Older action to page through the rest. This keeps a
  large history from delaying the initial list while preserving full-history
  access. Search and active server-supported filters match records across the
  full history; coach access remains scoped to the signed-in coach.
- Coach Attendance search keeps the selected-day mode and adds an All dates
  mode. All-dates search reaches the coach's full student-attendance history,
  shows each result date, and loads large match sets in pages on demand.
- Admin mobile Fees, Receipts, Leave, Session Photos, and Notifications now
  fetch all pages from their paginated APIs, removing the previous 500-record
  cutoff from those searchable sections. Page sizes are capped at 1,000 rows.
- Search requests are debounced and use normalized case-insensitive server-side
  matching, while retaining status, activity, approval, and date filters. No
  database migration is required.
- Release target: mobile version `1.26.19+55`, tag `mobile-v1.26.19`, through
  `.github/workflows/release-mobile.yml` using the persistent signing key.
  Never commit or share the signing key.
- Verification: all 12 backend regression tests and all 27 Flutter tests passed.
  Flutter analysis completed with no errors or warnings (192 informational
  notices); local split-ABI Android release compilation passed for
  armeabi-v7a, arm64-v8a, and x86_64. Production OpenAPI confirms search and
  pagination parameters are live on the attendance and capped list APIs.
- Published from commit `d4d0799ab6ae5a6d3362c12c386bd3cb505a384e` by GitHub
  Actions run `37678234806`:
  https://github.com/Deepak20466/attendance-management/releases/tag/mobile-v1.26.19
- Published APK SHA-256: arm64-v8a
  `36faf3b8554a1b88678e3781c4452cbe3c817bc56e4b8124c5e2f28b799b95c7`,
  armeabi-v7a `0be98fd778b7a516f4f3286416de7387734f406eb1587af7106f84ee963a4d91`,
  x86_64 `fd8eb153156f5cf24a2bf537bc0fc13db7a5ef3fa75de3f747634e00328edcb0`.
  All match GitHub's published digests, pass `apksigner verify`, and use the
  persistent signing certificate SHA-256
  `7d128bae4a3851fe496175bbfd832733c83f4210de992403b4677554f32d7ea7`.

## 2026-10-09 Cloud Run Recovery and Signed Android Release Preparation

- Use Google Cloud Run project `vimj-academy`, Supabase recovery, Flutter Android, and GitHub Releases. Do not use the blocked Render backend.
- Native mobile API defaults to a reserved `.invalid` URL; release workflow requires verified HTTPS `VIMJ_API_BASE_URL`. Production signing cannot fall back to the debug key.
- Restored coach salary model/API/admin and coach web/mobile workflows. Migration `0020` is additive, and production/Supabase migration `0013` is blocked. Salary rows can be transferred only from a verified recovery source into an empty target after exact fingerprint checks and explicit approval.
- Cloud Run scheduler uses a held PostgreSQL advisory lock, one instance, and always-allocated CPU. Scheduler activation requires confirmation that the previous owner has stopped. API and frontend deployment, CORS revision, and secret bindings are explicitly gated.
- Release target: mobile `1.26.33+69`, tag `mobile-v1.26.33`. Do not sign/publish until approved Cloud Run Admin/Coach E2E passes.
- Local verification: backend 33 tests; frontend build/lint passed; Flutter 35 tests; Flutter analysis exit 0 with 194 informational notices; Python compilation passed. Bash syntax passed for all 10 Cloud Shell scripts.
- Cloud Shell checks were reported complete by the operator, but their output was not supplied in this workspace. This update does not mark their gates as satisfied. No Cloud, database, release, or signing-key operation was performed.
- Exact commands and approvals: `docs/cloud-run-private-deployment.md`.
