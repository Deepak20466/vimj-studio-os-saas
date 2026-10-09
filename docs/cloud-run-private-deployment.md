# VIMJ Academy Cloud Run recovery and release runbook

This runbook is the deployment path for `vimj-academy` in `asia-south1`. It uses the recovered Supabase database, Cloud Run, Flutter Android, and GitHub Releases; the old Render backend remains suspended. Both Cloud Run services use request-based CPU and zero minimum instances. One OIDC-authenticated Cloud Scheduler job sends a minute tick to the API, which enqueues work into an OIDC-authenticated Cloud Tasks queue for the existing 11 `Asia/Kolkata` jobs. No worker stays alive between requests.

**Current verified state (2026-10-10):** backup integrity and recovery database comparison were independently completed by the operator; the recovery project is `zpkplfcqiqlcxtwysxpu` at revision `0020`, and the separate restore project is `ewlclomeuwgnubvfryuj` at `0019`. The independent CMEK GCS backup remains unchanged. GitHub Actions CI run `38002063190` passed, and the immutable backend image from source commit `99fa4f8f81c3fe2a8e63af31f81b85c346da9817` is verified in Artifact Registry at digest `sha256:987116c1a9458156940a43b98a807043cd37fa864c3fd05ede2d13c77fa4b662`; Cloud Build ID was `d9e65aa4-4461-4d47-a7be-9502f484dd02`. CI validated both container build contexts, while the frontend production image still needs the backend URL at build time. No Cloud Run service, queue, Scheduler job, migration, or production database write has been created/applied. The database password is being rotated; do not read or use the old Secret Manager version. Continue only after the owner confirms rotation and the new Secret Manager version. The approved bootstrap begins with empty CORS origins, then sets both to the exact final frontend Cloud Run HTTPS origin. Wildcard CORS and custom domains are not allowed. Free Trial billing must remain unchanged.

## Required command environment

Run commands from a clean checkout of the reviewed `vimj-production-recovery` commit in Google Cloud Shell. Do not paste database URLs, passwords, JWT secrets, Twilio credentials, reset tokens, or keystore material into command arguments, terminal output, or Git. Set only the non-secret Supabase host/user/database/project-reference values obtained from the Supabase dashboard. Use the transaction pooler on port 6543 for API traffic and the session pooler on port 5432 for advisory locks, backup, and salary transfers.

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
export EXPECTED_BACKUP_PROJECT_ID='teak-backup-491013-m3'
export BACKUP_BUCKET_URI='gs://REPLACE_WITH_CROSS_PROJECT_CMEK_BUCKET/vimj-recovery'
export BACKUP_TRANSFER_APPROVED=YES
python3 deploy/cloud-run/backup-supabase-cloud-shell.py
```

The script resolves project IDs and numbers through Resource Manager, then requests the bucket's raw API representation so it can compare the bucket `projectNumber` with the expected backup project and confirm it differs from `vimj-academy`. It verifies `encryption.defaultKmsKeyName` from that raw bucket response. Record the script's `BACKUP_URI`, `BACKUP_SHA256`, and object generation. It checks the PostgreSQL archive, decodes its contents, copies to the independent bucket with a create-only generation precondition, downloads the object again, and compares its SHA-256 and size.

## Restore salary rows only when the audit proves they are missing

`0013` historically dropped payroll and other tables. The current source restores salary APIs, schemas, admin/coach UI, and salary reminders. Migration `0020` is additive; it preserves a compatible existing table and refuses to drop salary history on downgrade. Do not run it until the verified database comparison resolves salary history. The project owner reports that no salary records were ever entered; still verify the recovered and target ledgers before migration. If both are empty, set `SALARY_RECOVERY_STATUS=CONFIRMED_EMPTY` and do not run the salary row-transfer helper.

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

After the salary schema and any verified salary-row reconciliation are complete, add the durable scheduler execution ledger. This is an additive schema-only change; it does not alter existing business rows. It requires the same independent backup, exact database identity, read-only preflight, explicit approval, and typed confirmation:

```bash
export BACKUP_VERIFIED=YES
export BACKUP_URI='REPLACE_WITH_VERIFIED_BACKUP_URI'
export BACKUP_SHA256='REPLACE_WITH_VERIFIED_64_CHARACTER_SHA256'
export SCHEDULER_SCHEMA_APPROVED=YES
export DATABASE_URL_SECRET='vimj-prod-database-url'
export DATABASE_URL_SECRET_VERSION='REPLACE_WITH_REVIEWED_NUMERIC_SECRET_VERSION'
export EXPECTED_SUPABASE_HOST='REPLACE_WITH_TARGET_POOLER_HOST'
export EXPECTED_SUPABASE_USER='REPLACE_WITH_TARGET_DATABASE_USERNAME'
export EXPECTED_DATABASE_NAME='postgres'
python3 deploy/cloud-run/apply-scheduler-ledger-cloud-shell.py
```

The helper refuses any starting revision other than `0020`, verifies the immutable CMEK backup object and downloaded checksum, then applies only `0021`. Revision `0021` creates one new scheduler-only table, its index, and an integer task-attempt generation column. It does not alter existing tables or business rows; downgrade refuses to drop the new scheduler state. The helper verifies the resulting revision and table in a read-only postflight.

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

## Configure the scheduled-jobs queue

Before deploying the backend, configure the existing dedicated Cloud Run runtime identity, Cloud Scheduler identity, and task OIDC identity. The task OIDC identity can reuse the Cloud Scheduler service account. Cloud Tasks creates one small task per due job slot so slow notification work does not keep the every-minute Scheduler request open. The queue's maximum concurrency is five, dispatch rate is capped at ten per second, retries stop after five attempts and 30 minutes, and each task request has a 600-second deadline.

This gated setup can create the `vimj-scheduled-jobs` queue and add only queue-scoped `roles/cloudtasks.enqueuer` for the runtime identity plus service-account-scoped `roles/iam.serviceAccountUser` grants for task token creation. It will not enable APIs, create service accounts, delete or replace an existing queue, or add project-wide task permissions. If the queue already exists, its reviewed name, active state, limits, and retry policy must match before IAM is changed.

```bash
export RUNTIME_SERVICE_ACCOUNT='REPLACE_WITH_EXISTING_DEDICATED_RUNTIME_SERVICE_ACCOUNT_EMAIL'
export CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL='REPLACE_WITH_EXISTING_SCHEDULER_SERVICE_ACCOUNT_EMAIL'
export CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL="$CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL"
export CLOUD_TASKS_COST_APPROVED=YES
export CLOUD_TASKS_IAM_APPROVED=YES
bash deploy/cloud-run/setup-cloud-tasks-cloud-shell.sh
```

Type `APPROVE-CONFIGURE-CLOUD-TASKS` only after approving the queue and these narrowly scoped IAM grants. This queue has no always-on worker; Cloud Tasks is billed per API operation or push attempt, not for an idle queue.

## Deploy API and website only after explicit approval

The backend deployment requires the read-only inventory at schema revision `0021`, all 21 required current tables, review of recognized historical tables, verified salary reconciliation, pinned Secret Manager versions, direct secret-scoped Accessor grants, the existing dedicated runtime/task identities and queue, and separate public API/cost approvals. It sets minimum instances to zero, caps the service at one instance, keeps request-based CPU, and sets a 600-second maximum request timeout for Cloud Tasks. The in-process APScheduler is disabled in production. The service is publicly invokable for mobile/web clients; business endpoints remain protected by app JWT and Admin/Coach authorization. The internal scheduler and task routes separately validate Google's OIDC signature, expected audience, and exact service-account identity. Production docs/OpenAPI are disabled. The migration is a separate gated step and is never run during service deployment.

Before running the script, set the following reviewed, non-secret environment values. `ADMIN_RECOVERY_SECRET_NAME` must be the existing secret name or `NONE` only after confirming that break-glass recovery is disabled. If notifications are enabled, set all four existing Twilio secret names; do not create replacement credentials.

```bash
export IMAGE_TAG="$BUILD_COMMIT"
export EXPECTED_SUPABASE_HOST='REPLACE_WITH_TARGET_POOLER_HOST'
export EXPECTED_SUPABASE_USER='REPLACE_WITH_TARGET_DATABASE_USERNAME'
export EXPECTED_DATABASE_NAME='postgres'
export CORS_BOOTSTRAP=true
export CORS_BOOTSTRAP_APPROVED=YES
# Keep both origins empty for this first backend revision. Browser requests
# remain denied until the frontend URL exists and the exact-origin step below.
unset FRONTEND_ORIGIN MOBILE_WEB_ORIGIN
export NOTIFICATIONS_ENABLED='REPLACE_WITH_REVIEWED_TRUE_OR_FALSE'
export ADMIN_RECOVERY_SECRET_NAME='REPLACE_WITH_SECRET_NAME_OR_NONE'
export RUNTIME_SERVICE_ACCOUNT='REPLACE_WITH_DEDICATED_RUNTIME_SERVICE_ACCOUNT_EMAIL'
export CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL='REPLACE_WITH_EXISTING_SCHEDULER_SERVICE_ACCOUNT_EMAIL'
export CLOUD_TASKS_QUEUE_NAME='projects/vimj-academy/locations/asia-south1/queues/vimj-scheduled-jobs'
export CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL="$CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL"
export SAFETY_AUDIT_REVIEWED=YES
export BACKUP_URI='REPLACE_WITH_VERIFIED_BACKUP_URI'
export BACKUP_SHA256='REPLACE_WITH_VERIFIED_64_CHARACTER_SHA256'
export SALARY_DATA_RECONCILED=YES
export SCHEDULER_HANDOFF_APPROVED=YES
export CLOUD_RUN_COST_APPROVED=YES
export PUBLIC_MOBILE_API_APPROVED=YES
bash deploy/cloud-run/deploy-backend-cloud-shell.sh
```

Type `APPROVE-CLOUD-RUN-PRODUCTION` only after approving the public API and request-based charges, then type `APPROVE-CORS-BOOTSTRAP-NO-ORIGINS` for the deny-by-default browser CORS revision. The service URL is pinned as the OIDC audience. No wildcard or temporary public origin is used. This step does not create or activate Cloud Scheduler. Do not direct users to either service before the exact-origin CORS step and E2E verification.

Deploy the frontend from the matching full commit image SHA after verifying its compiled API origin:

```bash
export IMAGE_TAG="$BUILD_COMMIT"
export API_BASE_URL="$(gcloud run services describe vimj-backend --project=vimj-academy --region=asia-south1 --format='value(status.url)')"
export CLOUD_RUN_COST_APPROVED=YES
export PUBLIC_FRONTEND_APPROVED=YES
bash deploy/cloud-run/deploy-frontend-cloud-shell.sh
```

Type `APPROVE-CLOUD-RUN-FRONTEND` to create the public website. The script refuses to update an existing frontend service and verifies HTTP 200.

After frontend deployment, set the exact HTTPS URL reported by Cloud Run. The updater compares it with the deployed `vimj-frontend` service URL, rejects other origins/wildcards, and verifies the resulting backend revision and scale-to-zero settings:

```bash
export FRONTEND_ORIGIN="$(gcloud run services describe vimj-frontend --project=vimj-academy --region=asia-south1 --format='value(status.url)')"
export MOBILE_WEB_ORIGIN="$FRONTEND_ORIGIN"
export CLOUD_RUN_CORS_CHANGE_APPROVED=YES
bash deploy/cloud-run/update-backend-cors-cloud-shell.sh
```

Type `APPROVE-UPDATE-CLOUD-RUN-CORS`. This creates a new backend revision using the existing immutable image digest. The Cloud Scheduler job is still inactive at this stage.

After the backend/frontend read-only E2E checks pass, activate the single minute dispatcher. Confirm the old Render scheduler is suspended, API/notification behavior has been reviewed, and the pre-existing service account has the Cloud Scheduler service-agent Token Creator grant. The setup script will not create accounts, grant IAM, enable APIs, or replace an existing job.

```bash
export CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL='REPLACE_WITH_EXISTING_SCHEDULER_SERVICE_ACCOUNT_EMAIL'
export CLOUD_TASKS_QUEUE_NAME='projects/vimj-academy/locations/asia-south1/queues/vimj-scheduled-jobs'
export CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL="$CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL"
export SCHEDULER_HANDOFF_APPROVED=YES
export PRODUCTION_API_E2E_PASSED=YES
export CLOUD_SCHEDULER_COST_APPROVED=YES
export SCHEDULED_NOTIFICATIONS_APPROVED=YES
bash deploy/cloud-run/setup-cloud-scheduler-cloud-shell.sh
```

Type `APPROVE-ENABLE-CLOUD-SCHEDULER-JOBS` to create `vimj-minute-dispatch`. It runs every minute with timezone `Asia/Kolkata` and an OIDC token from the selected service account. The endpoint reads Cloud Scheduler's RFC3339 `X-CloudScheduler-ScheduleTime` header and quickly enqueues work. Seven jobs run every minute; the others run at 00:15 (batch session generation), 00:30 (overdue fees), 09:00 on the 10th (fee reminders), 09:05 on the 10th (salary notifications), and 21:00 daily (end-of-day report), all local time. The minute request has a 60-second deadline, one retry, and a 30-second retry window. Each queued task uses a deterministic name for its slot/generation, OIDC authentication, a 600-second dispatch deadline, and at most five Cloud Tasks attempts over 30 minutes. PostgreSQL session advisory locks serialize executions of the same job; the `scheduler_job_executions` ledger records task generations, skips completed slots, rejects stale duplicate generations, and re-enqueues failed or abandoned work after the queue retry window. Notification providers are external side effects; an abrupt process failure after a provider accepts a message but before the database records completion can still cause a duplicate on retry. Scheduler activation therefore needs approval of this at-least-once behavior.

One Scheduler resource is used instead of 11 because each tick evaluates all 11 CronTrigger definitions. The seven minute-based jobs produce about 302,400 task deliveries over a 30-day month, plus 43,200 short tick requests. Cloud Tasks has a shared-account free allowance of 1,000,000 billable operations; a task normally uses one create operation and one delivery attempt, leaving retries as the main factor that can exceed the allowance. Cloud Run has no warm-instance floor or always-allocated CPU. At one average billed second per minute-job task and 0.5 second per minute tick, 1 vCPU/1 GiB produces roughly $3.46/month of Cloud Run usage after the per-account free CPU allowance, plus $0-$0.10 for Cloud Scheduler depending on other jobs in the billing account. At five seconds per task, the same estimate is about $35.42/month. If the Cloud Run free allowance is already consumed elsewhere, those scenarios are about $8.72 and $40.78/month. These estimates exclude user API/frontend traffic, logging, network egress, Cloud Build, Cloud Tasks retries beyond the free allowance, and the Supabase plan; actual CPU time of each current job is not yet measured. Cloud Run request-based rates and free allowances vary by region and billing account, so review billing after a gated canary.

For later code releases, submit new immutable images with the same clean-checkout build commands, then update only the image on each existing service. The backend update checks that the current revision contains the authenticated dispatcher and preserves the pinned service-account/audience configuration. The scripts verify pinned production secrets/public policy, the matching frontend API origin, and the independent backup reference before asking for separate approvals. They preserve service settings and do not run migrations.

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

Before release, complete HTTPS Admin and Coach smoke checks against the deployed API/site using approved test accounts: login, `/auth/me`, student/coach roster reads, attendance/reports/fees/receipts, salary history, and session-photo viewing. Do not create, edit, approve, delete, acknowledge, or upload production records as a test. Confirm unauthenticated business API requests return 401, app docs/OpenAPI are unavailable in production, CORS matches the deployed frontend, the scheduled tick returns 200 with expected enqueued/skipped slots, and the queue delivers each canary task to the authenticated task route. Confirm the execution ledger advances and no old scheduler remains active. Use staging fixtures and mocked Twilio sends for scheduled-reminder behavior; production activation may send messages to live recipients.

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

The local backend suite passed (33 tests), frontend production build and lint passed, Flutter tests passed (35), Flutter analysis completed with no errors or warnings (194 informational notices), and Python compilation passed. GitHub Actions run `38002063190` also passed the backend, frontend, Flutter, deployment-asset, and container-build jobs. The backend image is in Artifact Registry and was verified against its immutable digest. Cloud Run services, database migration `0021`, Cloud Tasks queue, Scheduler activation, production Admin/Coach E2E, signed Android build, and release publication remain pending. The single prerequisite is confirmation that the Supabase database password has been rotated and the new full URL is stored in the existing Secret Manager secret as a new version; do not read/use the prior exposed version. After that, rerun the exact target/backup verification immediately before migration and stop if any identity, revision, backup generation/hash, billing, or cost gate differs. No local heavy SDK/build was performed.
