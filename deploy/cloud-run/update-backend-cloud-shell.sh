#!/usr/bin/env bash
# Create a reviewed backend revision while preserving service settings/secrets.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
SERVICE="vimj-backend"
IMAGE_PATH="asia-south1-docker.pkg.dev/vimj-academy/cloud-run-source-deploy/vimj-backend"
IMAGE_TAG="${IMAGE_TAG:-}"
EXPECTED_SUPABASE_HOST="${EXPECTED_SUPABASE_HOST:-}"
EXPECTED_SUPABASE_USER="${EXPECTED_SUPABASE_USER:-}"
EXPECTED_DATABASE_NAME="${EXPECTED_DATABASE_NAME:-}"
BACKUP_URI="${BACKUP_URI:-}"
BACKUP_SHA256="${BACKUP_SHA256:-}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
need curl
need docker
[[ "$IMAGE_TAG" =~ ^[a-f0-9]{40}$ ]] || die "Set IMAGE_TAG to the full immutable commit SHA."
[[ -n "$EXPECTED_SUPABASE_HOST" && -n "$EXPECTED_SUPABASE_USER" && -n "$EXPECTED_DATABASE_NAME" ]] \
  || die "Set the reviewed Supabase host/user/database identity values."
[[ -n "$BACKUP_URI" && "$BACKUP_SHA256" =~ ^[a-f0-9]{64}$ ]] \
  || die "Set the verified independent BACKUP_URI and BACKUP_SHA256."
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."

IMAGE_TAG="$IMAGE_TAG" bash "$(dirname "${BASH_SOURCE[0]}")/verify-backend-image-cloud-shell.sh" \
  || die "The backend image/source fingerprint failed; no revision was created."
IMAGE_DIGEST="$(gcloud artifacts docker images describe "${IMAGE_PATH}:${IMAGE_TAG}" \
  --project="$PROJECT_ID" --format='value(image_summary.digest)' 2>/dev/null || true)"
[[ "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || die "The immutable backend image digest could not be resolved."
IMAGE_REF="${IMAGE_PATH}@${IMAGE_DIGEST}"

BACKUP_METADATA="$(gcloud storage objects describe "$BACKUP_URI" --format=json 2>/dev/null)" \
  || die "Could not verify independent backup metadata."
python3 - "$BACKUP_METADATA" "$BACKUP_SHA256" "$EXPECTED_SUPABASE_HOST" "$EXPECTED_SUPABASE_USER" "$EXPECTED_DATABASE_NAME" <<'PY'
import hashlib
import json
import sys

metadata_json, expected_sha, host, username, database = sys.argv[1:]
try:
    metadata = json.loads(metadata_json)
except Exception:
    raise SystemExit("ERROR: independent backup metadata was invalid.")
custom = metadata.get("metadata", {})
identity = hashlib.sha256(f"{host.lower()}|{username}|{database}".encode()).hexdigest()
if custom.get("sha256") != expected_sha or custom.get("source_identity_sha256") != identity:
    raise SystemExit("ERROR: independent backup checksum/source identity did not match.")
if not str(metadata.get("generation", "")) or not metadata.get("kmsKeyName"):
    raise SystemExit("ERROR: independent backup lacks an immutable generation or CMEK.")
PY

SERVICE_JSON="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json 2>/dev/null)" \
  || die "The existing Cloud Run backend service could not be inspected."
IAM_JSON="$(gcloud run services get-iam-policy "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json 2>/dev/null)" \
  || die "Could not inspect the existing backend invocation policy."
python3 - "$SERVICE_JSON" "$IAM_JSON" <<'PY'
import json
import sys

try:
    service = json.loads(sys.argv[1])
    policy = json.loads(sys.argv[2])
except Exception:
    raise SystemExit("ERROR: existing Cloud Run configuration was invalid.")
spec = service.get("spec", {}).get("template", {}).get("spec", {})
containers = spec.get("containers", [])
env = {item.get("name"): item for item in (containers[0].get("env", []) if containers else [])}
for name in ("DATABASE_URL", "JWT_SECRET_KEY"):
    reference = env.get(name, {}).get("valueFrom", {}).get("secretKeyRef", {})
    if not reference.get("name") or not str(reference.get("key", "")).isdigit():
        raise SystemExit(f"ERROR: existing {name} is not bound to a pinned Secret Manager version.")
if env.get("ENV", {}).get("value") != "production" or env.get("SCHEDULER_ENABLED", {}).get("value", "").lower() != "false":
    raise SystemExit("ERROR: existing API is not in reviewed scale-to-zero mode.")
if not env.get("CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", {}).get("value") or not env.get("CLOUD_SCHEDULER_OIDC_AUDIENCE", {}).get("value"):
    raise SystemExit("ERROR: existing API lacks the authenticated Cloud Scheduler identity.")
public_invoker = any(
    binding.get("role") == "roles/run.invoker" and "allUsers" in binding.get("members", [])
    for binding in policy.get("bindings", [])
)
if not public_invoker:
    raise SystemExit("ERROR: existing API is not publicly invokable for native HTTPS clients.")
print("Existing service configuration: PASS (pinned secrets, production scale-to-zero mode, Cloud Scheduler identity, public HTTPS invocation)")
PY
[[ "$?" -eq 0 ]] || die "The existing backend service configuration did not pass review."

CURRENT_IMAGE="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
  --format='value(spec.template.spec.containers[0].image)')"
[[ "$CURRENT_IMAGE" =~ @sha256:[0-9a-f]{64}$ ]] \
  || die "The current backend revision is not pinned to an immutable image digest."
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet >/dev/null
docker pull "$CURRENT_IMAGE" >/dev/null
docker run --rm --network=none --read-only --user=10001:10001 --entrypoint python3 "$CURRENT_IMAGE" -c '
import pathlib
root = pathlib.Path("/app/app")
scheduler = (root / "services" / "cloud_scheduler.py").read_text(encoding="utf-8")
if "verify_oauth2_token" not in scheduler or "pg_try_advisory_lock" not in scheduler or "SchedulerJobExecution" not in scheduler:
    raise SystemExit("existing revision lacks authenticated Cloud Scheduler locking and replay protection")
print("Existing image Cloud Scheduler authentication/locking: PASS")
' || die "The existing revision lacks the authenticated Cloud Scheduler dispatcher; reconcile scheduler ownership before updating."

service_url="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"
[[ "$service_url" == https://* ]] || die "Existing backend URL is not HTTPS."
[[ "${BACKEND_UPDATE_APPROVED:-}" == "YES" ]] || die "Approve the new backend revision by setting BACKEND_UPDATE_APPROVED=YES."
read -r -p 'Type APPROVE-UPDATE-CLOUD-RUN-BACKEND to update only the backend image: ' UPDATE_CONFIRM
[[ "$UPDATE_CONFIRM" == "APPROVE-UPDATE-CLOUD-RUN-BACKEND" ]] || die "Update cancelled; no revision was created."

# Updating only the image preserves the existing service identity, secret refs,
# CORS values, public invocation setting, scaling, CPU, and scheduler settings.
gcloud run services update "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$IMAGE_REF" \
  --quiet

health_http="$(curl --silent --show-error --connect-timeout 10 --max-time 150 \
  --output /dev/null --write-out '%{http_code}' "$service_url/health" || true)"
[[ "$health_http" == "200" ]] || die "Updated backend health returned HTTP ${health_http:-no response}."
me_http="$(curl --silent --show-error --connect-timeout 10 --max-time 60 \
  --output /dev/null --write-out '%{http_code}' "$service_url/auth/me" || true)"
[[ "$me_http" == "401" ]] || die "Updated backend auth guard returned HTTP ${me_http:-no response}, expected 401."
docs_http="$(curl --silent --show-error --connect-timeout 10 --max-time 30 \
  --output /dev/null --write-out '%{http_code}' "$service_url/openapi.json" || true)"
[[ "$docs_http" == "404" ]] || die "Production OpenAPI returned HTTP ${docs_http:-no response}, expected 404."

printf 'BACKEND_UPDATE=PASS\nIMAGE_REF=%s\nBACKEND_URL=%s\n' "$IMAGE_REF" "$service_url"
printf 'Only the image changed; database schema, application data, credentials, and runtime service settings were not changed by this script.\n'
