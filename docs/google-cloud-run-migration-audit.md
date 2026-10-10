# VIMJ Academy Cloud Run recovery audit

**Updated:** 2026-10-10
**Working branch:** `vimj-production-recovery`

## Verified production state

- Google Cloud CLI connectivity and authenticated access work from the VS Code PowerShell terminal over IPv4. Project: `vimj-academy`; region: `asia-south1`.
- The only database URL read for this migration was Secret Manager version 3. Its URL identifies Recovery Supabase project `zpkplfcqiqlcxtwysxpu`, transaction pooler port 6543, database `postgres`. A read-only PostgreSQL 17.11 connection confirmed revision `0021`, all 21 required tables, and existing user rows: 1 Admin, 3 Coaches, and 132 Students. No credentials were changed.
- A verified CMEK backup from revision `0020` is at `gs://vimj-academy-recovery-backup-2026/vimj-recovery/vimj-public-3dd92844-f7a4-4d48-9c0d-0d78b6652de5.dump`, generation `1791594683450624`, SHA-256 `8c6f27a670f15cb176bf82a12250bca80517df4324cef2e0c895d94e7e011fe7`. The additive `0021` migration is already applied; it adds scheduler execution state and does not rewrite historical business records. Do not repeat the backup or migration.
- Secret Manager version 3 is ENABLED. The existing JWT secret version 1 is ENABLED. A random `ADMIN_RECOVERY_SECRET` is stored as version 1 of `vimj-prod-admin-recovery-secret`; the Cloud Run runtime service account has secret-scoped access. No old database-secret version was read.
- Cloud Tasks queue `vimj-scheduled-jobs` is RUNNING with concurrency 5, 10 dispatches per second, and a five-attempt/30-minute retry policy. Queue-scoped enqueuer and service-account-scoped OIDC grants are present.

## Live Cloud Run deployment

- Backend: `https://vimj-backend-eqwnplgd6q-el.a.run.app`, revision `vimj-backend-00004-hjs`, immutable image digest `sha256:93ec199239cc007b93823ed3b4ac169a0b520deeee546098b54a834ccb2683ec`. Service-level maximum is one instance; no minimum is set, so it scales to zero. Request-based CPU is used.
- Frontend: `https://vimj-frontend-eqwnplgd6q-el.a.run.app`, revision `vimj-frontend-00001-79m`, immutable image digest `sha256:4d9aae8f0ad980d60be77df4fd5e2ca31ae1e1b6d2468110557c19b2c1bcd2cf`. Service-level maximum is three instances; no minimum is set, so it scales to zero.
- Frontend production JavaScript was checked to contain the canonical Cloud Run backend URL and no Render or placeholder URL. Backend CORS allows only the exact frontend origin; its preflight returned HTTP 200. There is no wildcard CORS.
- Backend secrets are pinned to DB version 3, JWT version 1, and recovery version 1. `SCHEDULER_ENABLED=false` and `NOTIFICATIONS_ENABLED=false`. In-app notifications remain available. SMS/WhatsApp are disabled because Twilio credentials are unavailable. Monthly student fee reminders safely skip without changing `reminder_sent_at` until external delivery is configured.
- Backend checks passed: `/health` HTTP 200; a synthetic invalid login returned HTTP 401 through the database-backed path; protected auth, attendance, fees, and report routes returned HTTP 401 without a token; `/docs` returned HTTP 404. Startup logs contained no errors and no in-process scheduler.
- Cloud Scheduler job `vimj-minute-dispatch` has not yet been created. The backend code and Cloud Build tests include all 11 Asia/Kolkata job definitions, but production schedules are not active until Admin and Coach sign-ins are verified.

## Build and release verification

- Backend commit `ac7872216dc9966f1e8dfd683e6f4963cc1eef7d` passed 63 backend unit tests and compiled as Cloud Build `8e8fb59f-e367-4289-b020-602f0a6227e4`.
- Frontend commit `361616cd23767d44620fe054ad99972032b361d0` passed Cloud Build `3f78fc9b-cabd-4e27-afcc-d531424d593c`, including lint and production build. Cloud Build configuration was fixed to validate substituted inputs.
- GitHub Actions variable `VIMJ_API_BASE_URL` is set and verified against the canonical backend URL. The mobile package version is `1.26.33+69`; the signed workflow requires the live Admin/Coach end-to-end check. No signed APK has been published yet.

## Remaining gate

The service has not been tested with the owner's existing passwords. Sign in to the frontend once as Admin and once as Coach, and confirm both dashboard shells load. Do not send passwords. After that, create and verify the authenticated Scheduler tick and run the approved signed Android release workflow. The old Render backend was deleted; no old Render credentials or Twilio values are available.

See [the Cloud Run recovery and release runbook](cloud-run-private-deployment.md) for deployment safety details. Do not rerun completed backup or database migration steps.
