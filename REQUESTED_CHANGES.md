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

Coach student-photo removal (2026-10-06):
- Added a confirmed Delete Photo action to each coach student menu on mobile and a Remove Photo action beside Capture Photo on coach web.
- Added the authenticated student-photo DELETE API. Admins can remove any student's photo; coaches can remove photos only for students on their assigned activity rosters. Removing a photo preserves the student, attendance, and fee records.
- Regression coverage checks successful removal, missing-photo handling, and that a coach cannot remove a photo outside their roster.
- Android update: version 1.26.3+39. GitHub Actions run 37462527351 completed successfully and published all three ABI APKs at https://github.com/Deepak20466/attendance-management/releases/tag/mobile-v1.26.3.
- Verified the deployed backend OpenAPI includes `DELETE /students/{student_id}/photo`. Backend regression suite (8 tests), frontend lint and production build, Flutter analysis, Flutter widget test, and local split-ABI release build passed.

## 2026-10-07 Admin Attendance Layout and Login Responsiveness

- Student and Coach attendance list visibility controls sit beside their search fields. Collapsed lists retain a visible Show control, a count badge for matching records, and a section-specific tooltip.
- The shared mobile login already starts /health warm-up in the background, keeps its bounded timeout and retry, and opens the dashboard shell immediately after authentication. Render free-tier cold starts remain host-controlled.
- Release target: mobile version 1.26.16+52, tag mobile-v1.26.16, using .github/workflows/release-mobile.yml and the persistent Android signing key.
- Verification: all 24 Flutter tests passed; Dart analysis had 0 errors/warnings and 174 informational lints; local split-ABI release compilation passed for armeabi-v7a, arm64-v8a, and x86_64.
- Published from commit `7596400e03a5ed5a9ee4b8d5f5d0875cf7528d1b` by GitHub Actions run `37666207039`:
  https://github.com/Deepak20466/attendance-management/releases/tag/mobile-v1.26.16
- Published APK SHA-256: arm64-v8a `61746e803fa335ce9f86e41e971d7cf5f6f01eed435d2d2702e989ab378f2cf1`,
  armeabi-v7a `8e1a49165478e5365cccdb08556122ff70ed9ef2f047adc02270212f003b2938`,
  x86_64 `91d5670c4077002d10a127968cff009074447040216aef9a2d2ca3b3e1714267`.
  All assets match GitHub published digests and pass `apksigner verify`. All use
  certificate SHA-256 `7d128bae4a3851fe496175bbfd832733c83f4210de992403b4677554f32d7ea7`.
