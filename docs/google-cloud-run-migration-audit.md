# VIMJ Academy Cloud Run recovery audit

**Updated:** 2026-10-09
**Working branch:** `vimj-production-recovery`
**Production changes made from this workspace:** none. No Cloud Run deployment, database write/migration, credential rotation, scheduler switch, or GitHub release was performed.

## Current implementation

- Cloud Run targets Google Cloud project `vimj-academy`, region `asia-south1`, and the verified Supabase database. The blocked Render backend is not a target or fallback.
- The mobile native API default is a reserved `.invalid` HTTPS URL. Release workflow configuration must provide the verified Cloud Run HTTPS origin; Render and placeholder origins are rejected.
- The Cloud Run API is publicly invocable over HTTPS so native Flutter clients can reach it. FastAPI JWT and role checks protect business APIs, production API docs/OpenAPI are disabled, and the Cloud Run service uses pinned Secret Manager references and a dedicated runtime identity.
- Salary models, API routes, admin web/mobile forms, coach salary history/acknowledgment, validation, and scheduled reminders have been restored. Migration `0020` is additive and preserves a compatible existing table. Migration `0013` now fails closed on production or Supabase connections.
- Scheduled jobs are enabled only after the approved owner handoff. A held PostgreSQL session advisory lock limits Cloud Run to one job owner across instances/revisions. The Cloud Run service is capped at one instance with CPU always allocated so APScheduler remains active. Twilio notification behavior is retained only when the reviewed existing configuration and secret references are supplied.
- Cloud Build scripts use a clean full commit SHA, produce immutable Artifact Registry tags, and do not pass application secrets to builds. Backend image checks compare source fingerprints, verify non-root execution, and reject baked secrets or Alembic startup files. Frontend deployment checks its compiled API origin.
- The Android release workflow verifies the HTTPS API URL, package/tag version, Flutter tests and analysis, existing signing certificate, and APK checksums. Signed builds require the production E2E input and approval in the protected `mobile-signing` environment; publication additionally requires approval in `mobile-release`. Target package: `1.26.33+69` / `mobile-v1.26.33`.

## Local verification

- Backend: 33 tests passed, including salary API/RBAC, public API security, scheduler ownership, and destructive migration protection.
- Frontend: production build and ESLint passed. Vite reports the existing large JavaScript chunk warning.
- Flutter: 35 tests passed. Analyzer result is recorded after its current run completes.
- Python `compileall`: passed for backend app, scripts, migrations, and tests.
- Bash syntax passed for all 10 Cloud Shell scripts; embedded Python, Cloud Build YAML, and GitHub Actions YAML parsed successfully. This is local syntax validation, not a remote Cloud Build or Cloud Shell run.

## Cloud/production verification status

Cloud Shell checks were reported as completed by the operator, but their output and checked project/database/image identities were not included in this workspace. This audit therefore does not copy those results or treat the deployment gates as satisfied. Capture the exact checksums, object generation, image digest/fingerprint, schema revision/table counts, salary reconciliation outcome, scheduler owner state, and Admin/Coach E2E evidence before setting any approval variables.

This workspace has no Cloud Run credentials, database credentials, Docker daemon, production test accounts, or GitHub signing secrets. The independent backup, Cloud Run services, schema migration, scheduler handoff, authenticated E2E, signed APK, and GitHub Release remain pending. No secret values are recorded here.

## Canonical procedure

Follow [the Cloud Run recovery and release runbook](cloud-run-private-deployment.md) for exact Cloud Shell commands and approval phrases. The detailed [production data-safety assessment](production-data-safety-assessment.md) documents the historical migration `0013` drop scope and recovery risks.
