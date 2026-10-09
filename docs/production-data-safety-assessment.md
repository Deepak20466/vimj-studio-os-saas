# Historical VIMJ production data safety assessment (pre-recovery changes)

This is the source-level safety audit written before the current Cloud Run recovery
implementation. Its status table and deployment recommendations describe that earlier
checkout. For current scripts, approval gates, salary recovery, and release steps, use
the [current Cloud Run recovery audit](google-cloud-run-migration-audit.md) and
[recovery runbook](cloud-run-private-deployment.md). The migration `0013` table-drop
inventory below remains relevant to historical data recovery.

**Assessment date:** 2026-10-09
**Repository source:** `master`, commit `2e839da3c8a7a571e544ea166851879868e8f888` before local migration-preparation files.
**Database access:** none. No Supabase credential or original backup was available.
**Production actions:** none. No SQL was run, migration applied, record changed, environment variable changed, deploy performed, or APK published.

## Decision

**FAIL — do not migrate or run `alembic upgrade head` against production.** Migration `0013` explicitly drops seven historical tables and their contents. The live revision and whether these tables currently contain rows are **UNVERIFIED**, so there is no evidence that those records have already been safely preserved. The migration is not safe under the requirement to retain every production record.

The previously observed totals supplied for this review—136 users, 1,098 student attendance rows, 100 student fee rows, and 575 classes—are useful reference values only. They were not re-read from production. Those four totals do not reveal whether the seven legacy tables contain records.

## Critical checks

| Check | Status | Finding |
| --- | --- | --- |
| Exact tables dropped by source migration `0013` | **PASS** | Source contains seven `op.drop_table` calls, listed below. |
| Whether those tables have production rows | **UNVERIFIED** | No live read-only database connection or backup was available. Do not infer emptiness from their absence in current ORM models. |
| Whether the historical features/data remain available in current source | **FAIL / PARTIAL** | Six tables are absent from current ORM/API code. Coach leave is re-created in `0014` without restoring rows. Session photos have a newer, narrower representation that does not copy old table rows. |
| Current Alembic revision and live schema | **UNVERIFIED** | The current source head is `0019`; live `alembic_version` was not queried. |
| 19-table exact counts, row fingerprints, FKs, and orphan checks | **UNVERIFIED / PREPARED** | Read-only SQL is in `production-data-safety-readonly.sql`. It has not been executed. Exact scans can load the database; prefer the consistent-snapshot workflow below. |
| Application model/API schema match | **PASS in source inventory; UNVERIFIED in database** | Current source has 18 business tables plus `alembic_version`. The live columns, types, defaults, constraints, and indexes were not inspected. |
| Backup and isolated restore | **FAIL / NOT VERIFIED** | No verified backup artifact, SHA-256, or isolated restore evidence was available. |
| Cloud Run can avoid automatic destructive migrations | **PASS in prepared image; production status UNVERIFIED** | `backend/Dockerfile.cloudrun` omits Alembic migration files and has no migration startup command. Current `render.yaml` still has `alembic upgrade head` in its build command. |
| Existing APK API URL | **FAIL for direct hostname cutover** | Mobile source compiles `https://vimj-backend.onrender.com` as its production default. Existing APKs will not start calling a new Cloud Run URL. Keep Render reachable or validate an approved compatible proxy; no APK was changed. |
| Scheduler single-owner handoff | **FAIL / NOT READY** | Gunicorn starts four workers and each production worker starts an in-process scheduler. Cloud Run image disables its scheduler, preventing a second host from starting it by default, but this does not fix duplicate jobs among the current Render workers. |
| Permission boundary | **PASS** | This assessment only reviewed local source and wrote local audit documents. No SQL or production action was performed. |

## Migration `0013`: exact destructive scope

The upgrade order is exactly the following. `DROP TABLE` removes the table's rows, indexes, constraints, and table definition. It does not archive the rows.

| Dropped table | Historical contents/features from migration schema | Current source status and risk |
| --- | --- | --- |
| `class_photos` | Class/coach photo rows. Migration `0005` defined `class_id`, `coach_id`, `photo_path`, and timestamp; `0012` changed the path column to `bytea`. | `0012` does **not** copy rows into `classes`. `0016` adds `classes.group_photo`/upload time for the newer one-photo-per-class flow. Old multiple-photo rows/metadata are not represented by that newer field. Current upload/download API uses `classes.group_photo`. **Any old rows are lost if `0013` runs.** |
| `attendance_submissions` | Coach submission time, late flag/reason/status, and admin decision fields for a class. | No current model or API table reference. `0014` adds `student_attendance.approval_status`, with existing student attendance backfilled to `APPROVED`; it does not copy old submission or late-decision history. |
| `class_skip_reasons` | Class, coach, reason, timestamp for a class not conducted. | No current model/API equivalent found. Historical reason records are lost if present. |
| `chat_messages` | Admin/coach sender, message body, read status, timestamp. | Chat is explicitly removed in `0013`'s description and no current model/API reference was found. Message history is lost if present. |
| `coach_swap` | Original/covering coaches, class/batch/date, reason, status, initiator, decline reason, timestamp. | No current model/API reference found. The current class coach assignment does not retain the full swap/approval history. |
| `coach_salary` | Coach/month/year salary amount, notification time, acknowledgment date. | No current model/API reference found. This is historical financial/payroll data; its deletion requires explicit data-retention resolution even though the current UI does not expose it. |
| `coach_leave` | Coach leave dates/reason/status, admin decision and note. | **Current feature is used.** `0014` re-creates the same table structure after `0013`, but does not restore the old rows. Leave records made after `0014` can exist; pre-`0013` leave history is not restored by this migration chain. |

The seven schemas and drop statements are in [migration 0013](../backend/alembic/versions/0013_remove_leave_salary_swap_chat_compliance.py). `0014` documents the leave recreation and attendance approval backfill. `0016` documents the separate newer group-photo columns. Source review establishes the destructive behavior, but only a live table/count/fingerprint query can establish whether historical rows remain in the current database.

## Current application model/API expectation

The current SQLAlchemy models define these 18 business tables:

`academy_settings`, `activities`, `admin_attendance_list_visibility`, `audit_log`, `batches`, `classes`, `coach_activities`, `coach_attendance`, `coach_leave`, `fee_receipts`, `fee_reminder_drafts`, `notifications`, `password_reset_tokens`, `student_attendance`, `student_enrollments`, `student_fees`, `user_details`, and `users`.

`alembic_version` is the 19th expected public table; the latest repository revision is `0019`. These tables support custom user authentication/roles and profiles; student/coaching activity enrollment and rosters; batches and scheduled classes; student and coach attendance and approvals; fee ledger, receipts, products, reminders, and reports; leave; notifications; academy settings; audit history; reset tokens; and admin attendance-list preferences. Current API routers use these models for the Admin and Coach features. The six dropped tables other than leave/photos are not current model/API requirements, but any historical records in them remain in scope for the user's preservation requirement.

The app's expected schema is **not** proof of the live database schema. `alembic check` can compare supported ORM metadata differences without applying a migration; it does not validate historical row preservation and Alembic autogenerate has known comparison limits. Run it only with a read-only database identity after the SQL inventory and backup. Never substitute `alembic upgrade`, `stamp`, or a Render build for this check. [Alembic check/autogenerate behavior](https://alembic.sqlalchemy.org/en/latest/autogenerate.html)

## Prepared read-only SQL

The SQL audit file is [production-data-safety-readonly.sql](production-data-safety-readonly.sql). It:

- requires a caller-started PostgreSQL `READ ONLY` transaction and aborts if the transaction is not read-only;
- compares expected current table names against every public base table and separately reports the seven `0013` table names;
- reports all current Alembic revision rows;
- calculates exact row counts and deterministic SHA-256 row-set fingerprints for every public base table, including `bytea` values;
- lists columns, types, nullability, defaults, indexes, constraints, FK definitions, and validation state;
- counts rows that do not match each declared foreign key.

The exact counts, fingerprints, and orphan scans read every table and may consume database I/O. Do not run them during a busy period. Use the consistent snapshot workflow below so the live report and backup refer to the same database state. For a quick presence/revision check, run the first inventory/revision queries only.

### Secure PowerShell connection

Use the **Session pooler** host and username copied from the Supabase Dashboard's Connect panel, port `5432` (or a direct connection if the network and project support it). Do not use the transaction pooler for the long-lived audit/backup session. The password is entered only at psql's hidden prompt; it is not part of the command or connection string.

```powershell
$PoolerHost = Read-Host "Supabase Session pooler host from the Connect panel"
$PoolerUser = Read-Host "Supabase database user from the Connect panel"
psql --no-psqlrc --host $PoolerHost --port 5432 --username $PoolerUser --dbname postgres --password --set ON_ERROR_STOP=1
```

At the `psql` prompt, use a repeatable, read-only snapshot and execute the audit file:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT pg_export_snapshot();
\i 'C:/Users/K Deepak/Downloads/attendance-management-master/attendance-management-master/attendance-management-release-work/docs/production-data-safety-readonly.sql'
```

Record the snapshot identifier printed by `pg_export_snapshot()`. Keep this psql session and transaction open while the matching `pg_dump` runs; after the dump finishes, execute `ROLLBACK;`. An exported snapshot is available only while its exporting transaction remains open, and `pg_dump --snapshot` can use it for a consistent dump. [PostgreSQL snapshot support](https://www.postgresql.org/docs/current/functions-admin.html) [pg_dump `--snapshot`](https://www.postgresql.org/docs/current/app-pgdump.html)

If the audit is not being paired with a dump, instead enter `BEGIN TRANSACTION READ ONLY;`, run the SQL file, and then `ROLLBACK;`.

### Current-vs-previous count check

The exact count/fingerprint notices include `users`, `student_attendance`, `student_fees`, and `classes`. Compare those rows with the previously observed 136, 1,098, 100, and 575 values. A difference is not automatically corruption: production may have legitimately changed since the earlier observation. A match does not prove the seven legacy tables are empty or preserved.

Run the inventory first. If all current tables are present at revision `0019`, also compare revenue/fees and photo data with the same snapshot. These example checks are read-only:

```sql
SELECT status, count(*) AS rows,
       sum(amount) AS fee_amount,
       sum(product_amount) AS product_amount,
       sum(balance_amount) AS remaining_balance
FROM public.student_fees
GROUP BY status
ORDER BY status;

SELECT count(*) AS rows,
       sum(amount) AS receipt_amount,
       sum(product_amount) AS receipt_product_amount
FROM public.fee_receipts;

SELECT 'classes.group_photo' AS data_field,
       count(*) AS records,
       coalesce(sum(octet_length(group_photo)), 0) AS bytes
FROM public.classes
WHERE group_photo IS NOT NULL
UNION ALL
SELECT 'student_attendance.selfie_photo',
       count(*),
       coalesce(sum(octet_length(selfie_photo)), 0)
FROM public.student_attendance
WHERE selfie_photo IS NOT NULL
UNION ALL
SELECT 'user_details.profile_photo',
       count(*),
       coalesce(sum(octet_length(profile_photo)), 0)
FROM public.user_details
WHERE profile_photo IS NOT NULL;
```

The table fingerprints already cover every field. The photo query adds human-readable non-null counts and total byte sizes for comparison. Never print photo bytes or student/coach PII into a shared report.

## Backup and isolated restore procedure

**A verified backup is a hard precondition to migration.** Prefer a Supabase-managed backup/PITR restore into a separate isolated project when available. Supabase's automated backup availability depends on plan; a platform restore causes downtime on its target, so never choose the production project as the restore target. [Supabase backup options](https://supabase.com/docs/guides/platform/backups)

For a manual logical copy of the app's `public` schema, use a PostgreSQL client matching or newer than the server major version. The example uses the session pooler and password prompt; it writes only a local dump. This is an application-schema backup, not a full Supabase platform backup of managed `auth`, `storage`, or other platform schemas. Prefer the Supabase-managed full backup when those schemas/configurations are in scope. Do not use `PGPASSWORD`, include the password in a URI, or paste it into a command.

```powershell
$PoolerHost = Read-Host "Supabase Session pooler host from the Connect panel"
$PoolerUser = Read-Host "Supabase database user from the Connect panel"
$BackupDir = Join-Path $env:USERPROFILE "vimj-backups"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$Stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$DumpPath = Join-Path $BackupDir "vimj-public-$Stamp.dump"

# Run this while the snapshot transaction above is still open. Enter the
# snapshot identifier from pg_export_snapshot(); pg_dump prompts for password.
$SnapshotId = Read-Host "Exported PostgreSQL snapshot identifier"
pg_dump --host $PoolerHost --port 5432 --username $PoolerUser --dbname postgres `
  --format custom --schema public --snapshot $SnapshotId --password --file $DumpPath
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed; do not use this file as a backup" }

pg_restore --list $DumpPath | Set-Content "$DumpPath.toc.txt"
if ($LASTEXITCODE -ne 0) { throw "Archive validation failed" }
Get-FileHash -Algorithm SHA256 $DumpPath
```

Store the dump and its checksum on an encrypted, access-controlled volume, separately from the laptop/workspace. Keep the exporter psql transaction open until `pg_dump` completes, then `ROLLBACK;`. Do not use `pg_dump` through Supabase transaction mode (`6543`); use the exact Session pooler or supported direct connection from the dashboard. Supabase documents session mode at `5432` and transaction mode at `6543`. [Supabase connection modes](https://supabase.com/docs/guides/database/connecting-to-postgres)

Restore only into a **new, isolated, empty staging project/database**, never production. Confirm its `public` schema has no application tables before restoring. Do not use `--clean`, `--if-exists`, `--create`, `alembic upgrade`, or any command targeting the production host.

```powershell
$StageHost = Read-Host "Isolated staging project's Session pooler host"
$StageUser = Read-Host "Isolated staging project's database user"
pg_restore --host $StageHost --port 5432 --username $StageUser --dbname postgres `
  --no-owner --exit-on-error --single-transaction --password $DumpPath
if ($LASTEXITCODE -ne 0) { throw "Restore failed; preserve the dump and inspect the isolated target" }
```

Run the same read-only SQL audit on the isolated restore and compare the `AUDIT_TABLE` names, exact row counts, and SHA-256 fingerprints with the source snapshot report. Also compare the expected/actual table inventory, revision, FK orphan counts, columns, indexes, fee aggregates, and photo byte sizes. The dump checksum verifies the local archive file; the row-set fingerprints verify restored table contents. Preserve both results with the backup timestamp and source revision. If any expected table/fingerprint/count differs, stop; do not “fix” the source by reimporting over production.

If `pg_dump`/`pg_restore` are unavailable, do not install Docker for this procedure. Use Supabase Dashboard's supported backup download and restore to a separate project, or have the database administrator run the same snapshot/export workflow from an approved host with PostgreSQL client tools. The Supabase CLI dump workflow may require Docker; it is not required for the native `pg_dump` route. Do not share credentials or the dump file in chat.

## Safest Cloud Run deployment and migration boundary

1. Complete and sign off the source snapshot, backup checksum, isolated restore, 19-table inventory, all table fingerprints/counts, FK/orphan check, and schema/model comparison first.
2. Check the live revision. If it is `0012` or earlier, `alembic upgrade head` will execute `0013` and drop the seven tables. If it is `0014` or later, `0013` has already run in normal migration history; inspect the current leave rows and backup history because `0014` only recreated an empty leave table. Do not infer prior data from `alembic_version` alone.
3. Reconcile the production `DATABASE_URL`: current `render.yaml` provisions Render Postgres and its build command applies Alembic. The stated production database is Supabase, so confirm the live Render secret points to Supabase before making any change. The prepared Cloud Run image excludes Alembic and has no migration command. Do not run migrations as a Cloud Build or container startup step.
4. First deploy/test only against the isolated restored staging database. Keep staging notifications and its scheduler disabled. Test APIs, Admin/Coach data loading, and photo/report/fee history against that copy.
5. In a separately approved production window, deploy the API against the **existing** Supabase database using the verified transaction-pooler URL and unchanged JWT secret. This is a code-host move, not a database migration: no schema mutation, reset, reimport, or database replacement is needed when the schema already matches.
6. Preserve `https://vimj-backend.onrender.com` for existing APKs. A direct Cloud Run URL switch breaks installed APKs; keep Render serving them or validate an approved compatible proxy before changing that hostname. Do not publish a new APK as part of this plan.
7. Keep `SCHEDULER_ENABLED=false` on Cloud Run. That prevents Cloud Run from adding another scheduler while Render remains owner. Before moving any schedules, implement durable run/event idempotency, stop and drain Render scheduled execution, confirm it is stopped, and only then enable exactly one new owner. `NOTIFICATIONS_ENABLED=false` only suppresses Twilio sends; `push_inapp` still writes in-app notification rows. Current Gunicorn has four workers, each with its own in-process APScheduler; `replace_existing=True` is only per scheduler process and is not a distributed lock.
8. Switch React/web traffic only after staging parity and read-only production health/API checks pass. Keep rollback as a frontend route back to Render; both APIs must continue sharing the same Supabase data. Never restore the pre-cutover backup over new writes.

Cloud Scheduler uses at-least-once delivery, so it cannot by itself guarantee one execution. Do not enable Cloud Scheduler against non-idempotent reminder/job endpoints. [Cloud Scheduler delivery behavior](https://docs.cloud.google.com/scheduler/docs/overview)

## Exact local commands for later read-only checks

From a repository checkout, the ORM comparison command is:

```powershell
Set-Location .\attendance-management-release-work\backend
python -m alembic -c alembic.ini check
```

Before that command, set `DATABASE_URL` in the current process using your approved local secret manager/secure environment mechanism and use a database identity with read-only privileges. Do not put the URL/password in the command line, shell history, `.env` committed to the repo, or output. Alembic's `check` compares metadata and does not generate a revision or apply one; it still connects to the database. Never run `python -m alembic upgrade head` for this audit.

## Release gate

**Migration status: NOT SAFE TO PROCEED.** Clear this only after:

- the actual live database URL and Alembic revision are confirmed;
- every one of the seven legacy tables is counted and its retention/recovery disposition is explicit;
- a fresh backup has a recorded SHA-256 and an isolated restore matches the source snapshot fingerprints/counts;
- the live schema matches source `0019` or a separately reviewed, data-preserving schema plan is approved;
- Admin/Coach staging and historical report/photo checks pass;
- the APK hostname and scheduler single-owner/idempotency plans are verified;
- explicit approval is given for any production environment, routing, or cloud-cost changes.
