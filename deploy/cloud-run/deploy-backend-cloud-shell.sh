#!/usr/bin/env bash
# Safe, gated deployment of the existing VIMJ backend image from Google Cloud Shell.
# This script never builds an image, creates a database, prints secret values,
# changes database state, or runs Alembic migrations. Secret bytes are held in memory
# only for validation and are passed to Cloud Run by Secret Manager reference.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
SERVICE="vimj-backend"
IMAGE_PATH="asia-south1-docker.pkg.dev/vimj-academy/cloud-run-source-deploy/vimj-backend"
IMAGE_TAG="${IMAGE_TAG:-}"
DB_URL_SECRET="${DB_URL_SECRET:-vimj-prod-database-url}"
JWT_SECRET_NAME="${JWT_SECRET_NAME:-vimj-prod-jwt-secret}"
EXPECTED_SUPABASE_HOST="${EXPECTED_SUPABASE_HOST:-}"
EXPECTED_SUPABASE_USER="${EXPECTED_SUPABASE_USER:-}"
EXPECTED_DATABASE_NAME="${EXPECTED_DATABASE_NAME:-}"
FRONTEND_ORIGIN="${FRONTEND_ORIGIN:-}"
MOBILE_WEB_ORIGIN="${MOBILE_WEB_ORIGIN:-}"
NOTIFICATIONS_ENABLED="${NOTIFICATIONS_ENABLED:-}"
TWILIO_ACCOUNT_SID_SECRET="${TWILIO_ACCOUNT_SID_SECRET:-}"
TWILIO_AUTH_TOKEN_SECRET="${TWILIO_AUTH_TOKEN_SECRET:-}"
TWILIO_SMS_FROM_SECRET="${TWILIO_SMS_FROM_SECRET:-}"
TWILIO_WHATSAPP_FROM_SECRET="${TWILIO_WHATSAPP_FROM_SECRET:-}"
ADMIN_RECOVERY_SECRET_NAME="${ADMIN_RECOVERY_SECRET_NAME:-}"
RUNTIME_SERVICE_ACCOUNT="${RUNTIME_SERVICE_ACCOUNT:-}"
CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL="${CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL:-}"
CLOUD_SCHEDULER_JOB_NAME="projects/${PROJECT_ID}/locations/${REGION}/jobs/vimj-minute-dispatch"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
need curl
need docker
[[ -n "$EXPECTED_SUPABASE_HOST" ]] || die "Set EXPECTED_SUPABASE_HOST from the production Supabase Connect panel."
[[ -n "$EXPECTED_SUPABASE_USER" ]] || die "Set EXPECTED_SUPABASE_USER from the production Supabase Connect panel."
[[ -n "$EXPECTED_DATABASE_NAME" ]] || die "Set EXPECTED_DATABASE_NAME from the production Supabase Connect panel."
[[ "$IMAGE_TAG" =~ ^[a-f0-9]{7,40}$ ]] || die "Set IMAGE_TAG to the immutable Cloud Build commit SHA tag; mutable tags are not accepted."
[[ "$FRONTEND_ORIGIN" =~ ^https://[^,]+$ ]] || die "Set FRONTEND_ORIGIN to the verified HTTPS Cloud Run frontend origin."
[[ -z "$MOBILE_WEB_ORIGIN" || "$MOBILE_WEB_ORIGIN" =~ ^https://[^,]+$ ]] || die "MOBILE_WEB_ORIGIN must be empty or a verified HTTPS origin."
python3 - "$FRONTEND_ORIGIN" "${MOBILE_WEB_ORIGIN:-$FRONTEND_ORIGIN}" <<'PY'
from urllib.parse import urlparse
import sys

for origin in sys.argv[1:]:
    parsed = urlparse(origin)
    if not parsed.hostname or parsed.path not in {"", "/"} or parsed.query or parsed.fragment or parsed.username:
        raise SystemExit("CORS values must be HTTPS origins without paths, credentials, queries, or fragments.")
PY
[[ "$NOTIFICATIONS_ENABLED" == "true" || "$NOTIFICATIONS_ENABLED" == "false" ]] \
  || die "Set NOTIFICATIONS_ENABLED to the reviewed production value true or false."
[[ -n "$ADMIN_RECOVERY_SECRET_NAME" ]] \
  || die "Set ADMIN_RECOVERY_SECRET_NAME to the existing Secret Manager secret name, or NONE after confirming recovery is disabled."
[[ -n "$RUNTIME_SERVICE_ACCOUNT" ]] \
  || die "Set RUNTIME_SERVICE_ACCOUNT to the reviewed dedicated Cloud Run service account."
[[ "$CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.iam\.gserviceaccount\.com$ ]] \
  || die "Set CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL to the pre-existing dedicated Cloud Scheduler service account."
[[ "$CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.iam\.gserviceaccount\.com$ ]] \
  || die "Set CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL to the pre-existing dedicated Cloud Scheduler service account."

ACTIVE_ACCOUNT="$(gcloud auth list --filter='status:ACTIVE' --format='value(account)' 2>/dev/null || true)"
[[ -n "$ACTIVE_ACCOUNT" ]] || die "No active gcloud account. Run: gcloud auth login"
CURRENT_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
[[ "$CURRENT_PROJECT" == "$PROJECT_ID" ]] || die "Set the active project to $PROJECT_ID, then rerun."

for api in run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com iam.googleapis.com; do
  api_state="$(gcloud services describe "$api" --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || true)"
  [[ "$api_state" == "ENABLED" ]] || die "Required API is not enabled: $api. This script will not enable APIs."
done

gcloud artifacts repositories describe cloud-run-source-deploy \
  --location="$REGION" --project="$PROJECT_ID" --format='value(name)' >/dev/null \
  || die "The existing Artifact Registry repository was not found or is inaccessible."

IMAGE_TAG_REF="${IMAGE_PATH}:${IMAGE_TAG}"
IMAGE_DIGEST="$(gcloud artifacts docker images describe "$IMAGE_TAG_REF" \
  --project="$PROJECT_ID" --format='value(image_summary.digest)' 2>/dev/null || true)"
[[ "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || die "Image tag was not found or did not resolve to a digest: $IMAGE_TAG_REF. List image tags and set IMAGE_TAG."
IMAGE_REF="${IMAGE_PATH}@${IMAGE_DIGEST}"
printf 'Artifact image exists; deployment will pin digest %s\n' "$IMAGE_DIGEST"

# Pull the exact immutable digest and compare all Python application sources
# with this checkout. Run only a read-only, network-isolated container to hash
# its source files; do not rebuild or pass runtime secrets to the image.
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../backend" && pwd)"
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet >/dev/null
docker pull "$IMAGE_REF" >/dev/null
SOURCE_CODE_HASH="$(python3 - "$BACKEND_DIR/app" <<'PY'
import hashlib
import pathlib
import sys

app_dir = pathlib.Path(sys.argv[1])
root = app_dir.parent
digest = hashlib.sha256()
files = sorted(app_dir.rglob("*.py")) + [root / "requirements.txt", root / "gunicorn_conf.py"]
for path in files:
    relative = path.relative_to(root).as_posix().encode("utf-8")
    digest.update(len(relative).to_bytes(4, "big"))
    digest.update(relative)
    digest.update(hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).digest())
print(digest.hexdigest())
PY
)"
IMAGE_CODE_HASH="$(docker run --rm --network=none --read-only --user=10001:10001 \
  --entrypoint python3 "$IMAGE_REF" -c '
import hashlib
import os
import pathlib
import sys

if os.environ.get("ENV") != "production" or os.environ.get("SCHEDULER_ENABLED", "").lower() != "false":
    raise SystemExit("image is missing production mode or has an always-on in-process scheduler")
if "DATABASE_URL" in os.environ or "JWT_SECRET_KEY" in os.environ:
    raise SystemExit("image contains a runtime secret environment variable")

root = pathlib.Path("/app")
app_dir = root / "app"
if (root / "alembic").exists() or (root / "alembic.ini").exists():
    raise SystemExit("image unexpectedly contains Alembic migration files")
digest = hashlib.sha256()
files = sorted(app_dir.rglob("*.py")) + [root / "requirements.txt", root / "gunicorn_conf.py"]
for path in files:
    relative = path.relative_to(root).as_posix().encode("utf-8")
    digest.update(len(relative).to_bytes(4, "big"))
    digest.update(relative)
    digest.update(hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).digest())
print(digest.hexdigest())
')" || die "Image source/runtime check failed; deployment was stopped without rebuilding."
[[ "$SOURCE_CODE_HASH" == "$IMAGE_CODE_HASH" ]] \
  || die "Artifact image Python sources do not match this checkout; deployment was stopped without rebuilding."

IMAGE_IDENTITY="$(docker image inspect "$IMAGE_REF" --format '{{.Config.User}}|{{.Config.WorkingDir}}|{{json .Config.Cmd}}')"
python3 - "$IMAGE_IDENTITY" <<'PY'
import json
import sys

user, working_dir, command_json = sys.argv[1].split("|", 2)
command = " ".join(json.loads(command_json or "[]"))
if user != "10001:10001":
    raise SystemExit("ERROR: image does not run as the expected non-root user.")
if working_dir != "/app" or "gunicorn" not in command or "app.main:app" not in command or "alembic" in command.lower():
    raise SystemExit("ERROR: image startup configuration does not match the reviewed Cloud Run command.")
print("Image source and startup configuration: PASS (exact Python-source match; non-root; scale-to-zero scheduler mode; no baked secrets)")
PY

# Refuse to update an existing service. This workflow is for the first parallel
# Cloud Run deployment and must not replace a service that appeared since review.
EXISTING_SERVICE="$(gcloud run services list --project="$PROJECT_ID" --region="$REGION" \
  --filter="metadata.name=$SERVICE" --format='value(metadata.name)')"
[[ -z "$EXISTING_SERVICE" ]] || die "Cloud Run service $SERVICE already exists; refusing to update it."

gcloud iam service-accounts describe "$RUNTIME_SERVICE_ACCOUNT" --project="$PROJECT_ID" \
  --format='value(email)' >/dev/null \
  || die "Runtime service account does not exist: $RUNTIME_SERVICE_ACCOUNT. Set RUNTIME_SERVICE_ACCOUNT to an existing account."

enabled_version() {
  local secret_name="$1" resource version
  resource="$(gcloud secrets versions list "$secret_name" --project="$PROJECT_ID" \
    --filter='state=ENABLED' --sort-by='~createTime' --limit=1 --format='value(name)' 2>/dev/null || true)"
  [[ -n "$resource" ]] || die "No enabled Secret Manager version found for $secret_name."
  version="${resource##*/}"
  [[ "$version" =~ ^[0-9]+$ ]] || die "Could not resolve a numeric enabled secret version for $secret_name."
  printf '%s' "$version"
}

append_secret_binding() {
  local env_name="$1" secret_name="$2" version policy
  [[ -n "$secret_name" ]] || die "Secret Manager name is required for $env_name."
  version="$(enabled_version "$secret_name")"
  policy="$(gcloud secrets get-iam-policy "$secret_name" --project="$PROJECT_ID" --format=json)" \
    || die "Could not read the secret-scoped IAM policy for $secret_name."
  python3 - "$RUNTIME_SERVICE_ACCOUNT" "$policy" "$secret_name" <<'PY'
import json
import sys

service_account, policy_json, secret_name = sys.argv[1:]
member = f"serviceAccount:{service_account}"
policy = json.loads(policy_json)
allowed = any(
    binding.get("role") == "roles/secretmanager.secretAccessor"
    and member in binding.get("members", [])
    and not binding.get("condition")
    for binding in policy.get("bindings", [])
)
if not allowed:
    raise SystemExit(f"ERROR: grant secret-scoped Secret Accessor on {secret_name} to the runtime service account.")
PY
  SECRET_BINDINGS+=",${env_name}=${secret_name}:${version}"
}

DB_URL_VERSION="$(enabled_version "$DB_URL_SECRET")"
JWT_SECRET_VERSION="$(enabled_version "$JWT_SECRET_NAME")"
SECRET_BINDINGS="DATABASE_URL=${DB_URL_SECRET}:${DB_URL_VERSION},JWT_SECRET_KEY=${JWT_SECRET_NAME}:${JWT_SECRET_VERSION}"
if [[ "$NOTIFICATIONS_ENABLED" == "true" ]]; then
  append_secret_binding TWILIO_ACCOUNT_SID "$TWILIO_ACCOUNT_SID_SECRET"
  append_secret_binding TWILIO_AUTH_TOKEN "$TWILIO_AUTH_TOKEN_SECRET"
  append_secret_binding TWILIO_SMS_FROM "$TWILIO_SMS_FROM_SECRET"
  append_secret_binding TWILIO_WHATSAPP_FROM "$TWILIO_WHATSAPP_FROM_SECRET"
else
  [[ -z "$TWILIO_ACCOUNT_SID_SECRET" ]] || append_secret_binding TWILIO_ACCOUNT_SID "$TWILIO_ACCOUNT_SID_SECRET"
  [[ -z "$TWILIO_AUTH_TOKEN_SECRET" ]] || append_secret_binding TWILIO_AUTH_TOKEN "$TWILIO_AUTH_TOKEN_SECRET"
  [[ -z "$TWILIO_SMS_FROM_SECRET" ]] || append_secret_binding TWILIO_SMS_FROM "$TWILIO_SMS_FROM_SECRET"
  [[ -z "$TWILIO_WHATSAPP_FROM_SECRET" ]] || append_secret_binding TWILIO_WHATSAPP_FROM "$TWILIO_WHATSAPP_FROM_SECRET"
fi
if [[ "$ADMIN_RECOVERY_SECRET_NAME" != "NONE" ]]; then
  append_secret_binding ADMIN_RECOVERY_SECRET "$ADMIN_RECOVERY_SECRET_NAME"
fi

# Require narrow, direct Secret Accessor grants for the Cloud Run runtime identity.
# No IAM policy is modified by this script.
DB_SECRET_IAM="$(gcloud secrets get-iam-policy "$DB_URL_SECRET" --project="$PROJECT_ID" --format=json)"
JWT_SECRET_IAM="$(gcloud secrets get-iam-policy "$JWT_SECRET_NAME" --project="$PROJECT_ID" --format=json)"
python3 - "$RUNTIME_SERVICE_ACCOUNT" "$DB_SECRET_IAM" "$JWT_SECRET_IAM" <<'PY'
import json
import sys

service_account, db_json, jwt_json = sys.argv[1:]
member = f"serviceAccount:{service_account}"

def direct_accessor(policy_json):
    policy = json.loads(policy_json)
    return any(
        binding.get("role") == "roles/secretmanager.secretAccessor"
        and member in binding.get("members", [])
        and not binding.get("condition")
        for binding in policy.get("bindings", [])
    )

db_ok = direct_accessor(db_json)
jwt_ok = direct_accessor(jwt_json)
missing = []
if not db_ok:
    missing.append("DB URL secret")
if not jwt_ok:
    missing.append("JWT secret")
if missing:
    print("ERROR: runtime service account lacks direct Secret Accessor access to " + ", ".join(missing), file=sys.stderr)
    print("Grant roles/secretmanager.secretAccessor on each named secret (not project-wide) to the runtime service account, then rerun.", file=sys.stderr)
    sys.exit(2)
print("Runtime Secret Manager access: PASS (secret-scoped Secret Accessor grants verified)")
PY

PREFLIGHT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vimj-cloudrun-preflight.XXXXXX")"
trap 'rm -rf -- "$PREFLIGHT_DIR"' EXIT
python3 -m venv "$PREFLIGHT_DIR/venv" || die "Could not create a temporary Python environment."
"$PREFLIGHT_DIR/venv/bin/pip" install --disable-pip-version-check --no-input --quiet \
  'SQLAlchemy==2.0.35' 'pydantic==2.9.2' 'pydantic-settings==2.5.2' 'psycopg2-binary==2.9.9' \
  || die "Could not install the pinned read-only PostgreSQL preflight dependencies in Cloud Shell."

"$PREFLIGHT_DIR/venv/bin/python" - "$PROJECT_ID" "$DB_URL_SECRET" "$DB_URL_VERSION" \
  "$JWT_SECRET_NAME" "$JWT_SECRET_VERSION" "$BACKEND_DIR" \
  "$EXPECTED_SUPABASE_HOST" "$EXPECTED_SUPABASE_USER" "$EXPECTED_DATABASE_NAME" <<'PY'
from __future__ import annotations

import os
import subprocess
import sys

(
    project_id, db_secret, db_version, jwt_secret, jwt_version, backend_dir,
    expected_host, expected_user, expected_database,
) = sys.argv[1:]

class PreflightError(Exception):
    """A safe-to-display preflight failure message."""

def read_secret(name: str, version: str) -> str:
    result = subprocess.run(
        ["gcloud", "secrets", "versions", "access", version,
         f"--secret={name}", f"--project={project_id}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        raise PreflightError(f"Could not read the enabled Secret Manager version for {name}")
    value = result.stdout.decode("utf-8").rstrip("\r\n")
    if not value:
        raise PreflightError(f"Secret Manager version is empty: {name}")
    return value

try:
    database_url = read_secret(db_secret, db_version)
    jwt_key = read_secret(jwt_secret, jwt_version)
    if jwt_key == "dev-secret-change-me" or len(jwt_key.encode("utf-8")) < 32:
        raise PreflightError("JWT secret is the development default or is shorter than 32 bytes")

    sys.path.insert(0, backend_dir)
    os.environ["DATABASE_URL"] = database_url
    os.environ["JWT_SECRET_KEY"] = jwt_key

    from sqlalchemy import inspect, text
    from sqlalchemy.engine import make_url
    from app.database import engine, normalize_database_url

    parsed = make_url(normalize_database_url(database_url))
    if parsed.get_backend_name() != "postgresql":
        raise PreflightError("DATABASE_URL is not PostgreSQL")
    if not (parsed.host or "").lower().endswith(".pooler.supabase.com") or parsed.port != 6543:
        raise PreflightError("DATABASE_URL must resolve to the Supabase transaction pooler on port 6543")
    if parsed.host.lower() != expected_host.lower():
        raise PreflightError("DATABASE_URL host does not match the configured production Supabase host")
    if parsed.username != expected_user or parsed.database != expected_database:
        raise PreflightError("DATABASE_URL user/database does not match the configured production database identity")

    expected_tables = {
        "academy_settings", "activities", "admin_attendance_list_visibility", "alembic_version",
        "audit_log", "batches", "classes", "coach_activities", "coach_attendance", "coach_leave",
        "fee_receipts", "fee_reminder_drafts", "notifications", "password_reset_tokens",
        "student_attendance", "student_enrollments", "student_fees", "user_details", "users",
        "coach_salary", "scheduler_job_executions",
    }
    preserved_legacy_tables = {
        "attendance_submissions", "chat_messages", "class_photos",
        "class_skip_reasons", "coach_swap",
    }
    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            connection.exec_driver_sql("SET TRANSACTION READ ONLY")
            status = connection.execute(text(
                "SELECT current_database() AS database_name, current_user AS database_user, "
                "current_setting('transaction_read_only') AS read_only, "
                "current_setting('server_version') AS server_version"
            )).one()
            if status.read_only != "on":
                raise PreflightError("PostgreSQL did not confirm a read-only transaction")
            # Supabase transaction-pooler usernames (postgres.<project-ref>) may
            # map to a server-side current_user that differs from the URL role.
            # The URL host/user are checked above; verify the connected database.
            if status.database_name != expected_database:
                raise PreflightError("connected PostgreSQL database does not match the configured production database")
            revisions = list(connection.execute(text("SELECT version_num FROM alembic_version")).scalars())
            if revisions != ["0021"]:
                raise PreflightError("database revision is not the expected 0021; no migration will be run")
            actual_tables = set(inspect(connection).get_table_names(schema="public"))
            missing = sorted(expected_tables - actual_tables)
            preserved_legacy = sorted(actual_tables & preserved_legacy_tables)
            extra = sorted(actual_tables - expected_tables - preserved_legacy_tables)
            if missing or extra:
                raise PreflightError("public table inventory differs from the expected 21-table schema")
            print("Secret values: PASS (present, valid format; values not displayed)")
            print("Production Supabase identity and transaction-pooler connection: PASS (read-only transaction)")
            print(f"PostgreSQL server version: {status.server_version}")
            print(f"Alembic revision: 0021; required current tables: 21/21; historical tables preserved: {len(preserved_legacy)}")
        finally:
            if transaction.is_active:
                transaction.rollback()
    engine.dispose()
except PreflightError as exc:
    print(f"ERROR: production preflight failed: {exc}", file=sys.stderr)
    sys.exit(2)
except Exception as exc:
    # Driver exceptions can include connection metadata; never display their text.
    print(f"ERROR: production preflight failed ({type(exc).__name__}); details suppressed to protect secrets.", file=sys.stderr)
    sys.exit(2)
PY

printf '\nRead-only preflight passed. This creates a public API with zero minimum instances; request-based Cloud Run charges apply during requests.\n'
printf 'The in-process scheduler stays disabled. One OIDC-authenticated Cloud Scheduler job invokes all 11 jobs only after its separate approval.\n'
printf 'The script will not create a database, change schema/data, run migrations, rotate credentials, or alter legacy/client routing.\n'
[[ "${SAFETY_AUDIT_REVIEWED:-}" == "YES" ]] \
  || die "Review the source/backup comparison first; then set SAFETY_AUDIT_REVIEWED=YES and rerun."
[[ -n "${BACKUP_URI:-}" ]] || die "Set BACKUP_URI to the independently stored and verified recovery archive."
[[ "${BACKUP_SHA256:-}" =~ ^[a-f0-9]{64}$ ]] || die "Set BACKUP_SHA256 to the independently stored and verified backup checksum."
BACKUP_METADATA="$(gcloud storage objects describe "$BACKUP_URI" --format=json 2>/dev/null)" \
  || die "Could not verify the independent backup object metadata."
python3 - "$BACKUP_METADATA" "$BACKUP_SHA256" "$EXPECTED_SUPABASE_HOST" "$EXPECTED_SUPABASE_USER" "$EXPECTED_DATABASE_NAME" <<'PY' \
  || die "Independent backup metadata validation failed."
import hashlib
import json
import sys

metadata_json, expected_sha, host, username, database = sys.argv[1:]
try:
    metadata = json.loads(metadata_json)
except Exception:
    raise SystemExit("ERROR: independent backup metadata was invalid.")
custom = metadata.get("metadata", {})
identity = hashlib.sha256(f"{host.lower()}|{username}|{database}".encode("utf-8")).hexdigest()
if custom.get("sha256") != expected_sha or custom.get("source_identity_sha256") != identity:
    raise SystemExit("ERROR: independent backup checksum/source identity does not match the target database.")
if not str(metadata.get("generation", "")) or not metadata.get("kmsKeyName"):
    raise SystemExit("ERROR: independent backup object lacks a generation or CMEK encryption.")
print("Independent backup reference: PASS (checksum, database identity, immutable generation, CMEK metadata)")
PY
[[ "${SALARY_DATA_RECONCILED:-}" == "YES" ]] || die "Reconcile historical coach_salary rows against the verified backup; then set SALARY_DATA_RECONCILED=YES."
[[ "${SCHEDULER_HANDOFF_APPROVED:-}" == "YES" ]] || die "Confirm the previous scheduler owner is stopped before Cloud Run starts; then set SCHEDULER_HANDOFF_APPROVED=YES."
[[ "${CLOUD_RUN_COST_APPROVED:-}" == "YES" ]] || die "Approve the public scale-to-zero Cloud Run service and request-based charges; then set CLOUD_RUN_COST_APPROVED=YES."
[[ "${PUBLIC_MOBILE_API_APPROVED:-}" == "YES" ]] || die "Approve public HTTPS invocation; app-issued JWT and role checks remain required for business routes."
read -r -p 'Type APPROVE-CLOUD-RUN-PRODUCTION to create the service: ' DEPLOY_CONFIRM
[[ "$DEPLOY_CONFIRM" == "APPROVE-CLOUD-RUN-PRODUCTION" ]] || die "Deployment was not approved; no Cloud Run service was created."

# Check again immediately before the only cloud-resource mutation.
EXISTING_SERVICE="$(gcloud run services list --project="$PROJECT_ID" --region="$REGION" \
  --filter="metadata.name=$SERVICE" --format='value(metadata.name)')"
[[ -z "$EXISTING_SERVICE" ]] || die "Cloud Run service $SERVICE appeared during preflight; refusing to update it."

gcloud run deploy "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$IMAGE_REF" \
  --port=8080 \
  --cpu=1 \
  --memory=1Gi \
  --concurrency=8 \
  --timeout=120s \
  --min=0 \
  --max=1 \
  --allow-unauthenticated \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" \
  --set-env-vars="ENV=production,SCHEDULER_ENABLED=false,NOTIFICATIONS_ENABLED=${NOTIFICATIONS_ENABLED},FRONTEND_ORIGIN=${FRONTEND_ORIGIN},MOBILE_WEB_ORIGIN=${MOBILE_WEB_ORIGIN:-$FRONTEND_ORIGIN},CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL=${CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL},CLOUD_SCHEDULER_JOB_NAME=${CLOUD_SCHEDULER_JOB_NAME}" \
  --set-secrets="$SECRET_BINDINGS" \
  --quiet

SERVICE_URL="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
  --format='value(status.url)')"
[[ "$SERVICE_URL" == https://* ]] || die "Cloud Run did not return an HTTPS service URL. Do not route clients to this service."

# The OIDC audience is the canonical Cloud Run URL, available after creation.
gcloud run services update "$SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" \
  --update-env-vars="CLOUD_SCHEDULER_OIDC_AUDIENCE=${SERVICE_URL}" \
  --quiet

SERVICE_CONFIG="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json)" \
  || die "Could not verify the deployed Cloud Run service settings."
python3 - "$SERVICE_CONFIG" "$SERVICE_URL" "$CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL" "$CLOUD_SCHEDULER_JOB_NAME" <<'PY' \
  || die "Cloud Run scale-to-zero or Cloud Scheduler identity settings failed verification."
import json
import sys

service, expected_url, expected_email, expected_job = sys.argv[1:]
data = json.loads(service)
spec = data.get("spec", {})
template = spec.get("template", {})
template_metadata = template.get("metadata", {})
service_metadata = data.get("metadata", {})
template_spec = template.get("spec", {})
containers = template_spec.get("containers", [])
env = {
    item["name"]: item.get("value", "")
    for item in (containers[0].get("env", []) if containers else [])
}
annotations = {}
annotations.update(service_metadata.get("annotations", {}))
annotations.update(template_metadata.get("annotations", {}))
scaling = {}
scaling.update(spec.get("scaling", {}))
scaling.update(template.get("scaling", {}))
min_values = [
    scaling.get("minInstanceCount"),
    annotations.get("autoscaling.knative.dev/minScale"),
    annotations.get("run.googleapis.com/minScale"),
]
if any(value is not None and str(value) not in {"0", ""} for value in min_values):
    raise SystemExit("Cloud Run must have zero minimum instances.")
if env.get("SCHEDULER_ENABLED", "").lower() != "false":
    raise SystemExit("Cloud Run must not run an in-process scheduler.")
if env.get("CLOUD_SCHEDULER_OIDC_AUDIENCE") != expected_url:
    raise SystemExit("Cloud Scheduler OIDC audience does not match the canonical service URL.")
if env.get("CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "").lower() != expected_email.lower():
    raise SystemExit("Cloud Scheduler service account does not match the reviewed identity.")
if env.get("CLOUD_SCHEDULER_JOB_NAME") != expected_job:
    raise SystemExit("Cloud Scheduler job name does not match the reviewed resource name.")
cpu_throttling = annotations.get("run.googleapis.com/cpu-throttling")
if cpu_throttling == "false":
    raise SystemExit("Cloud Run CPU is always allocated; request-based CPU is required for cost control.")
print("Cloud Run configuration: PASS (min instances 0; request-based CPU; scheduler identity pinned)")
PY

health_http="$(curl --silent --show-error --connect-timeout 10 --max-time 150 \
  --output /dev/null --write-out '%{http_code}' "$SERVICE_URL/health" || true)"
[[ "$health_http" == "200" ]] || die "Live /health returned HTTP ${health_http:-no response}; deployment is not verified. Inspect Cloud Run logs."
printf 'Live /health: PASS (HTTP 200)\n'

# This synthetic invalid login performs a DB-backed SELECT, never authenticates,
# and cannot write the successful-login audit row. Its response body is discarded.
probe_email="cloudrun-db-probe-$(date -u +%s)-$$@example.com"
login_http="$(curl --silent --show-error --connect-timeout 10 --max-time 150 \
  --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data "{\"email\":\"${probe_email}\",\"password\":\"invalid-deployment-probe\"}" \
  "$SERVICE_URL/auth/login" || true)"
[[ "$login_http" == "401" ]] || die "DB-backed invalid-login probe returned HTTP ${login_http:-no response}, expected 401; deployment is not verified. Inspect Cloud Run logs."
printf 'Database-backed /auth/login rejection: PASS (HTTP 401; no real credentials used)\n'

me_http="$(curl --silent --show-error --connect-timeout 10 --max-time 60 \
  --output /dev/null --write-out '%{http_code}' "$SERVICE_URL/auth/me" || true)"
[[ "$me_http" == "401" ]] || die "Unauthenticated /auth/me returned HTTP ${me_http:-no response}, expected 401."
printf 'Protected /auth/me behavior: PASS (HTTP 401 without a token)\n'

for endpoint in \
  "$SERVICE_URL/attendance/students" \
  "$SERVICE_URL/fees" \
  "$SERVICE_URL/reports?month=10&year=2026"; do
  api_http="$(curl --silent --show-error --connect-timeout 10 --max-time 60 \
    --output /dev/null --write-out '%{http_code}' "$endpoint" || true)"
  [[ "$api_http" == "401" ]] \
    || die "Protected read-only API returned HTTP ${api_http:-no response}, expected 401 without an app login token."
done
printf 'Attendance, fees, and reports routes: PASS (present and require an app login token; no records changed)\n'

# Summarize startup logs without printing log payloads, which can contain
# database connection details if the runtime fails unexpectedly.
LOGS_FILE="$PREFLIGHT_DIR/cloudrun-logs.json"
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE} AND resource.labels.location=${REGION}" \
  --project="$PROJECT_ID" --freshness=30m --limit=100 --format=json > "$LOGS_FILE" \
  || die "Could not read Cloud Run startup logs."
python3 - "$LOGS_FILE" <<'PY'
import json
import pathlib
import sys

entries = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
errors = [entry for entry in entries if entry.get("severity", "DEFAULT") in {"ERROR", "CRITICAL", "ALERT", "EMERGENCY"}]
def payload(entry):
    return " ".join(str(value) for value in (entry.get("textPayload", ""), entry.get("jsonPayload", {})))

started = any("Application startup complete" in payload(entry) for entry in entries)
if errors:
    raise SystemExit("ERROR: Cloud Run logs contain error-severity entries; payloads suppressed. Inspect logs in Cloud Console.")
if not started:
    raise SystemExit("ERROR: no FastAPI startup-complete log was found; inspect Cloud Run logs in Cloud Console.")
if any("Scheduler started with" in payload(entry) for entry in entries):
    raise SystemExit("ERROR: an in-process scheduler unexpectedly started on the scale-to-zero service.")
print(f"Cloud Run startup logs: PASS ({len(entries)} entries scanned; API started without in-process scheduler; no error-severity entries; payloads suppressed)")
PY

printf '\nDEPLOYMENT VERIFIED\nService: %s\nRegion: %s\nImage: %s\nBackend URL: %s\n' \
  "$SERVICE" "$REGION" "$IMAGE_REF" "$SERVICE_URL"
printf 'Public HTTPS access is enabled; non-public API operations require app-issued JWTs and role authorization.\n'
printf "The Cloud Scheduler endpoint verifies Google's OIDC signature, audience, service account, and job name; PostgreSQL locking and a durable run ledger prevent overlaps and replay duplicates.\n"
printf 'Interactive API docs are disabled in production; local OpenAPI authorization tests run before image build.\n'
printf 'Set the reviewed GitHub Actions variable VIMJ_API_BASE_URL to this URL before preparing a mobile release.\n'
