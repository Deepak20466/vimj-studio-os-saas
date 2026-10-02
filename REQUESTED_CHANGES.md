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
