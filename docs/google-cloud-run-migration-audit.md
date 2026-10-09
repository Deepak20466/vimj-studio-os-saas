# VIMJ Academy Cloud Run recovery audit

**Updated:** 2026-10-10
**Working branch:** `vimj-production-recovery`
**Production changes made from this workspace:** none. No Cloud Run deployment, database write/migration, credential rotation, scheduler switch, or GitHub release was performed.

## Current implementation

- Cloud Run targets Google Cloud project `vimj-academy`, region `asia-south1`, and the verified Supabase database. The blocked Render backend is not a target or fallback.
- The mobile native API default is a reserved `.invalid` HTTPS URL. Release workflow configuration must provide the verified Cloud Run HTTPS origin; Render and placeholder origins are rejected.
- The Cloud Run API is publicly invocable over HTTPS so native Flutter clients can reach it. FastAPI JWT and role checks protect business APIs, production API docs/OpenAPI are disabled, and the Cloud Run service uses pinned Secret Manager references and a dedicated runtime identity.
- Salary models, API routes, admin web/mobile forms, coach salary history/acknowledgment, validation, and scheduled reminders have been restored. Migration `0020` is additive and preserves a compatible existing table. Migration `0013` now fails closed on production or Supabase connections.
- Production jobs use one authenticated Cloud Scheduler HTTP tick each minute to enqueue due work into a Cloud Tasks queue. Both routes verify Google's signed OIDC token, expected audience, and dedicated service-account identity. PostgreSQL advisory locks and the additive `0021` execution ledger prevent concurrent runs of each job, reject stale task generations, and skip completed slots. Cloud Tasks retries task failures; the dispatcher re-enqueues only failed work after the bounded queue retry window. External SMS/WhatsApp delivery remains at-least-once if a process stops after a provider accepts a message but before the database records completion. All 11 jobs retain their Asia/Kolkata schedules while Cloud Run uses request-based CPU and zero minimum instances.
- Cloud Build scripts use a clean full commit SHA, produce immutable Artifact Registry tags, and do not pass application secrets to builds. Backend image checks compare source fingerprints, verify non-root execution, and reject baked secrets or Alembic startup files. Frontend deployment checks its compiled API origin.
- The Android release workflow verifies the HTTPS API URL, package/tag version, Flutter tests and analysis, existing signing certificate, and APK checksums. Signed builds require the production E2E input and approval in the protected `mobile-signing` environment; publication additionally requires approval in `mobile-release`. Target package: `1.26.33+69` / `mobile-v1.26.33`.

## Local verification

- Backend: 61 tests passed, including Cloud Scheduler/Cloud Tasks OIDC identity, Asia/Kolkata slot selection, deterministic task identity, retry generations, replay skips, migration safety, and existing API/RBAC/data safety coverage. Frontend lint/build passed. Flutter tests passed (35); Flutter analysis exited successfully with 0 errors/warnings and 194 informational notices. Cloud Shell Bash and embedded Python syntax checks, backend Python compilation, and `git diff --check` passed. The frontend build reports the existing 817 kB minified JavaScript chunk warning.
- Frontend: production build and ESLint passed. Vite reports the existing large JavaScript chunk warning.
- Flutter: 35 tests passed. Analysis exited 0 with 194 informational notices and no errors or warnings.
- Python `compileall`: passed for backend app, scripts, migrations, and tests.
- Bash syntax and `git diff --check` passed for the changed Cloud Shell scripts. This is local syntax validation, not a remote Cloud Build or Cloud Shell run.

## Cloud/production verification status

Cloud Shell checks were reported as completed by the operator, but their output and checked project/database/image identities were not included in this workspace. This audit therefore does not copy those results or treat the deployment gates as satisfied. Capture the exact checksums, object generation, image digest/fingerprint, schema revision/table counts, salary reconciliation outcome, prior scheduler shutdown, Cloud Scheduler identity/configuration, and Admin/Coach E2E evidence before setting any approval variables.

This workspace has no `gcloud` CLI/credentials, production database credentials, Docker daemon, production test accounts, or access to GitHub signing secret values. The independent backup, Cloud Run services, schema migrations, scheduler handoff, authenticated E2E, signed APK, and GitHub Release remain pending. GitHub signing secret names and protected environments exist, but `VIMJ_API_BASE_URL` is not configured because the Cloud Run API URL does not exist yet. No secret values are recorded here.

## Canonical procedure

Follow [the Cloud Run recovery and release runbook](cloud-run-private-deployment.md) for exact Cloud Shell commands and approval phrases. The detailed [production data-safety assessment](production-data-safety-assessment.md) documents the historical migration `0013` drop scope and recovery risks.
