# VIMJ Academy Cloud Run recovery and release runbook

This runbook is the current deployment path for `vimj-academy` in `asia-south1`. It targets Cloud Run, the verified Supabase recovery database, Flutter Android, and GitHub Releases. It does not use the blocked Render backend. All scripts are approval-gated; none has been run against Google Cloud or Supabase from this workspace.

## Required command environment

Run commands from a clean checkout of the reviewed `cloud-run-safety-audit` commit in Google Cloud Shell. Do not paste database URLs, passwords, JWT secrets, Twilio credentials, reset tokens, or keystore material into command arguments, terminal output, or Git. Set only the non-secret Supabase host/user/database/project-reference values obtained from the Supabase dashboard. Use the transaction pooler on port 6543 for the API and the session pooler on port 5432 for backup and salary transfers.

```bash
gcloud auth login
gcloud config set project vimj-academy
gcloud config get-value project
git status --short
git rev-parse HEAD
```

The checkout must be clean. Cloud Build uses the exact full Git commit SHA as its image tag and refuses dirty worktrees.

## Read-only database comparison and independent backup

If the completed Cloud Shell audit has not already been recorded for the exact recovery and restore Supabase project references, run:

```bash
export EXPECTED_RECOVERY_REF='REPLACE_WITH_RECOVERY_PROJECT_REF'
export EXPECTED_RESTORE_REF='REPLACE_WITH_RESTORE_PROJECT_REF'
bash deploy/cloud-run/audit-supabase-databases-cloud-shell.sh
```

The script reads the recovery connection from Secret Manager, requests the other URL with hidden input, and prints table counts/revisions only. Review `coach_salary` and all seven historical tables before continuing. If any feature or record set is missing from the intended target, stop and reconcile it from the verified recovery source; counts alone are not proof of equality.

A fresh encrypted backup is required before any schema/data write. Use a pre-existing GCS bucket in a different Google Cloud project with a default Cloud KMS key. The script will not create a bucket, print credentials, or overwrite an object.

```bash
export DATABASE_URL_SECRET='vimj-prod-database-url'
export DATABASE_URL_SECRET_VERSION='REPLACE_WITH_REVIEWED_NUMERIC_SECRET_VERSION'
export EXPECTED_SUPABASE_HOST='REPLACE_WITH_SESSION_OR_TRANSACTION_POOLER_HOST'
export EXPECTED_SUPABASE_USER='REPLACE_WITH_DATABASE_USERNAME'
export EXPECTED_DATABASE_NAME='postgres'
export BACKUP_BUCKET_URI='gs://REPLACE_WITH_CROSS_PROJECT_CMEK_BUCKET/vimj-recovery'
export BACKUP_TRANSFER_APPROVED=YES
python3 deploy/cloud-run/backup-supabase-cloud-shell.py
```

Record the script's `BACKUP_URI`, `BACKUP_SHA256`, and object generation. It checks the PostgreSQL archive, decodes its contents, copies to the independent bucket with a create-only generation precondition, downloads the object again, and compares its SHA-256 and size.

## Restore salary rows only when the audit proves they are missing

`0013` historically dropped payroll and other tables. The current source restores salary APIs, schemas, admin/coach UI, and salary reminders. Migration `0020` is additive; it will preserve a compatible existing table and refuses to drop salary history on downgrade. It must not run until the verified database comparison shows whether payroll rows already exist or need recovery.

Before running migration `0020`, set `SALARY_RECOVERY_STATUS` from the audited evidence:

- `PRESERVED_EXISTING` if the target table and rows already match the verified source.
- `RESTORE_PENDING` if the table/rows must be recovered from the other Supabase project.
- `CONFIRMED_EMPTY` only if the recovery evidence confirms there were no salary rows.

```bash
export BACKUP_URI='REPLACE_WITH_VERIFIED_BACKUP_URI'
export BACKUP_SHA256='REPLACE_WITH_VERIFIED_64_CHARACTER_SHA256'
export BACKUP_VERIFIED=YES
export SALARY_MIGRATION_APPROVED=YES
export SALARY_RECOVERY_STATUS='RESTORE_PENDING'
export DATABASE_URL_SECRET='vimj-prod-database-url'
export DATABASE_URL_SECRET_VERSION='REPLACE_WITH_REVIEWED_NUMERIC_SECRET_VERSION'
export EXPECTED_SUPABASE_HOST='REPLACE_WITH_TARGET_POOLER_HOST'
export EXPECTED_SUPABASE_USER='REPLACE_WITH_TARGET_DATABASE_USERNAME'
export EXPECTED_DATABASE_NAME='postgres'
python3 deploy/cloud-run/apply-salary-migration-cloud-shell.py
```

The migration helper verifies the stored backup SHA, KMS key and generation, downloads and hashes the full backup again, checks the exact target identity and revision, then asks for `APPROVE-SALARY-MIGRATION-0020`. It applies only revision `0020` and performs a read-only postflight. If the source already has salary rows and the target ledger is empty, the row-transfer helper below is separately gated; it does not overwrite or delete rows.

```bash
export BACKUP_VERIFIED=YES
export BACKUP_URI='REPLACE_WITH_VERIFIED_BACKUP_URI'
export BACKUP_SHA256='REPLACE_WITH_VERIFIED_64_CHARACTER_SHA256'
export SALARY_ROWS_RESTORE_APPROVED=YES
export DATABASE_URL_SECRET='vimj-prod-database-url'
export DATABASE_URL_SECRET_VERSION='REPLACE_WITH_REVIEWED_NUMERIC_SECRET_VERSION'
export EXPECTED_SOURCE_SUPABASE_REF='REPLACE_WITH_SOURCE_PROJECT_REF'
export EXPECTED_TARGET_SUPABASE_REF='REPLACE_WITH_TARGET_PROJECT_REF'
python3 deploy/cloud-run/restore-salary-rows-cloud-shell.py
```

Enter the source session-pooler URL only at the hidden prompt. The script requires revision `0020`, exact compatible salary columns, no duplicate coach/month/year records, and an empty target ledger before it asks for `APPROVE-RESTORE-SALARY-ROWS`. It performs one atomic data-only restore, aligns the ID sequence, then compares exact row-set SHA-256 fingerprints. If the target is non-empty and differs, it stops for manual reconciliation. It never deletes target rows.

## Build and verify immutable images

Cloud Build uploads source and pushes an image, so each build requires its explicit approval variable and typed confirmation. The build script never uses Cloud Build substitutions for secrets.

```bash
export BUILD_COMMIT="$(git rev-parse HEAD)"
export CLOUD_BUILD_APPROVED=YES
bash deploy/cloud-run/build-cloud-run-image-cloud-shell.sh backend
export IMAGE_TAG="$BUILD_COMMIT"
bash deploy/cloud-run/verify-backend-image-cloud-shell.sh
```

The fingerprint helper prints the immutable Artifact Registry digest and Python-source fingerprint. It verifies the exact checkout, non-root image user, no baked runtime secrets, no Alembic files, and migration-free startup. Do not proceed if any value differs from the reviewed source.

After the backend service has an HTTPS URL, build the frontend image against that URL:

```bash
export API_BASE_URL="$(gcloud run services describe vimj-backend --project=vimj-academy --region=asia-south1 --format='value(status.url)')"
export CLOUD_BUILD_APPROVED=YES
bash deploy/cloud-run/build-cloud-run-image-cloud-shell.sh frontend
```

Both build commands ask for `APPROVE-CLOUD-BUILD-BACKEND` or `APPROVE-CLOUD-BUILD-FRONTEND` respectively.

## Deploy API and website only after explicit approval

The backend deployment requires the read-only inventory at schema revision `0020`, all 20 required current tables, review of any recognized historical tables that remain present, verified salary reconciliation, pinned Secret Manager versions, direct secret-scoped Accessor grants, a dedicated runtime service account, confirmed old-scheduler shutdown, and separate public API/cost approvals. It enables the PostgreSQL advisory-lock scheduler only after the owner handoff is approved. It deploys public HTTPS invocation because Flutter clients cannot use Cloud Run IAM identity tokens; business endpoints remain protected by app JWT and Admin/Coach authorization. Production docs/OpenAPI are disabled. No database migration or secret rotation runs during deployment.

Before running the script, set the following reviewed, non-secret environment values. `ADMIN_RECOVERY_SECRET_NAME` must be the existing secret name or `NONE` only after confirming that break-glass recovery is disabled. If notifications are enabled, set all four existing Twilio secret names; do not create replacement credentials.

```bash
export IMAGE_TAG="$BUILD_COMMIT"
export EXPECTED_SUPABASE_HOST='REPLACE_WITH_TARGET_POOLER_HOST'
export EXPECTED_SUPABASE_USER='REPLACE_WITH_TARGET_DATABASE_USERNAME'
export EXPECTED_DATABASE_NAME='postgres'
export FRONTEND_ORIGIN='https://REPLACE_WITH_VERIFIED_FRONTEND_ORIGIN'
export MOBILE_WEB_ORIGIN="$FRONTEND_ORIGIN"
export NOTIFICATIONS_ENABLED='REPLACE_WITH_REVIEWED_TRUE_OR_FALSE'
export ADMIN_RECOVERY_SECRET_NAME='REPLACE_WITH_SECRET_NAME_OR_NONE'
export RUNTIME_SERVICE_ACCOUNT='REPLACE_WITH_DEDICATED_RUNTIME_SERVICE_ACCOUNT_EMAIL'
export SAFETY_AUDIT_REVIEWED=YES
export BACKUP_URI='REPLACE_WITH_VERIFIED_BACKUP_URI'
export BACKUP_SHA256='REPLACE_WITH_VERIFIED_64_CHARACTER_SHA256'
export SALARY_DATA_RECONCILED=YES
export SCHEDULER_HANDOFF_APPROVED=YES
export CLOUD_RUN_COST_APPROVED=YES
export PUBLIC_MOBILE_API_APPROVED=YES
bash deploy/cloud-run/deploy-backend-cloud-shell.sh
```

Type `APPROVE-CLOUD-RUN-PRODUCTION` only after approving public API access, the always-on scheduler/cost, and the verified handoff. If the website origin is not known at initial API creation, use a reviewed temporary HTTPS origin; do not direct users to either service before the final CORS step and E2E verification.

Deploy the frontend from the matching full commit image SHA after verifying its compiled API origin:

```bash
export IMAGE_TAG="$BUILD_COMMIT"
export API_BASE_URL="$(gcloud run services describe vimj-backend --project=vimj-academy --region=asia-south1 --format='value(status.url)')"
export CLOUD_RUN_COST_APPROVED=YES
export PUBLIC_FRONTEND_APPROVED=YES
bash deploy/cloud-run/deploy-frontend-cloud-shell.sh
```

Type `APPROVE-CLOUD-RUN-FRONTEND` to create the public website. The script refuses to update an existing frontend service and verifies HTTP 200.

Then set the actual frontend origin reported by the deployment and allow the backend's CORS middleware to accept it:

```bash
export FRONTEND_ORIGIN='REPLACE_WITH_FRONTEND_URL_REPORTED_BY_DEPLOYMENT'
export MOBILE_WEB_ORIGIN="$FRONTEND_ORIGIN"
export CLOUD_RUN_CORS_CHANGE_APPROVED=YES
bash deploy/cloud-run/update-backend-cors-cloud-shell.sh
```

Type `APPROVE-UPDATE-CLOUD-RUN-CORS`. This creates a new backend revision using the existing immutable image digest; the advisory lock prevents overlapping Cloud Run revisions from simultaneously owning scheduled jobs.

For later code releases, submit new immutable images with the same clean-checkout build commands, then update only the image on each existing service. The backend update checks that the current revision already contains the PostgreSQL scheduler lock; if it does not, it stops for an explicit scheduler handoff. The scripts verify pinned production secrets/public policy, the matching frontend API origin, and the independent backup reference before asking for separate approvals. They preserve service settings and do not run migrations.

```bash
export IMAGE_TAG="$BUILD_COMMIT"
export EXPECTED_SUPABASE_HOST='REPLACE_WITH_TARGET_POOLER_HOST'
export EXPECTED_SUPABASE_USER='REPLACE_WITH_TARGET_DATABASE_USERNAME'
export EXPECTED_DATABASE_NAME='postgres'
export BACKUP_URI='REPLACE_WITH_VERIFIED_BACKUP_URI'
export BACKUP_SHA256='REPLACE_WITH_VERIFIED_64_CHARACTER_SHA256'
export BACKEND_UPDATE_APPROVED=YES
bash deploy/cloud-run/update-backend-cloud-shell.sh

export API_BASE_URL="$(gcloud run services describe vimj-backend --project=vimj-academy --region=asia-south1 --format='value(status.url)')"
export FRONTEND_UPDATE_APPROVED=YES
bash deploy/cloud-run/update-frontend-cloud-shell.sh
```

Type `APPROVE-UPDATE-CLOUD-RUN-BACKEND` and `APPROVE-UPDATE-CLOUD-RUN-FRONTEND` only after reviewing the verified image refs and backup evidence.

## End-to-end checks and Android release gate

Before release, complete HTTPS Admin and Coach smoke checks against the deployed API/site using approved test accounts: login, `/auth/me`, student/coach roster reads, attendance/reports/fees/receipts, salary history, and session-photo viewing. Do not create, edit, approve, delete, acknowledge, or upload production records as a test. Confirm unauthenticated business API requests return 401, app docs/OpenAPI are unavailable in production, CORS matches the deployed frontend, and logs report the scheduler owner lock. Save the verification evidence and confirm no old scheduler owner is still active.

The mobile API origin must be HTTPS and is passed at build time as `VIMJ_API_BASE_URL`. The default native API host is a reserved `.invalid` URL, so an unconfigured APK cannot silently call an old backend. The next package version is `1.26.33+69`, tag `mobile-v1.26.33`. Merge the reviewed workflow changes onto the repository default branch. Set the repository Actions variable `VIMJ_API_BASE_URL` to the verified Cloud Run HTTPS URL. Configure `mobile-signing` with required reviewers and the existing signing secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`); signing secrets must be scoped to this environment. Configure `mobile-release` with required reviewers. The signing environment approval gates keystore access; the release environment approval gates publication. After E2E and release approval:

```bash
git tag mobile-v1.26.33
git push origin mobile-v1.26.33
gh workflow run release-mobile.yml \
  --repo Deepak20466/attendance-management \
  --ref mobile-v1.26.33 \
  -f release_tag=mobile-v1.26.33 \
  -f production_e2e_verified=true \
  -f publish_release=true
```

The tag push runs verification only. The workflow dispatch creates signed split-ABI APKs with the persistent GitHub Actions keystore, checks the established certificate fingerprint and SHA-256 checksums, then creates the GitHub Release. The protected `mobile-signing` environment must approve keystore access and `mobile-release` must approve publication. If the end-to-end evidence is incomplete, leave both workflow booleans `false`; no signed release or publication will occur.

## Local verification already performed

The local backend suite passed (33 tests), frontend production build and lint passed, Flutter tests passed (35), Flutter analysis completed with no errors or warnings (194 informational notices), and Python compilation passed. This workspace does not have Google Cloud credentials, Docker, the production database, GitHub signing secrets, or production test accounts. Therefore Cloud Shell backup/deploy checks, staging/production E2E, Android signed build, and release publication remain unverified and have not been performed.
