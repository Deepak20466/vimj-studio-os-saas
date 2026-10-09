#!/usr/bin/env bash
# Add the verified public frontend origin to an existing backend revision.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
SERVICE="vimj-backend"
FRONTEND_ORIGIN="${FRONTEND_ORIGIN:-}"
MOBILE_WEB_ORIGIN="${MOBILE_WEB_ORIGIN:-}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
need curl
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."
[[ "$FRONTEND_ORIGIN" =~ ^https://[^,]+$ ]] || die "Set FRONTEND_ORIGIN to the verified HTTPS frontend service origin."
[[ -z "$MOBILE_WEB_ORIGIN" || "$MOBILE_WEB_ORIGIN" =~ ^https://[^,]+$ ]] \
  || die "MOBILE_WEB_ORIGIN must be empty or a verified HTTPS origin."
frontend_url="$(gcloud run services describe vimj-frontend --project="$PROJECT_ID" --region="$REGION" \
  --format='value(status.url)' 2>/dev/null || true)"
[[ "$frontend_url" =~ ^https:// ]] || die "The final Cloud Run frontend service was not found."
[[ "$FRONTEND_ORIGIN" == "$frontend_url" ]] \
  || die "FRONTEND_ORIGIN must exactly match the final Cloud Run frontend URL: $frontend_url"
mobile_origin="$MOBILE_WEB_ORIGIN"
[[ -n "$mobile_origin" ]] || mobile_origin="$frontend_url"
[[ "$mobile_origin" == "$frontend_url" ]] \
  || die "MOBILE_WEB_ORIGIN must be empty or exactly the same final Cloud Run frontend URL."
python3 - "$FRONTEND_ORIGIN" "$mobile_origin" <<'PY'
from urllib.parse import urlparse
import sys

for origin in sys.argv[1:]:
    if not origin:
        continue
    parsed = urlparse(origin)
    if not parsed.hostname or "*" in origin or parsed.path not in {"", "/"} or parsed.query or parsed.fragment or parsed.username:
        raise SystemExit("CORS values must be HTTPS origins without paths, queries, or fragments.")
PY

service_url="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
  --format='value(status.url)' 2>/dev/null || true)"
[[ "$service_url" =~ ^https:// ]] || die "The existing backend Cloud Run service was not found."
service_image="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
  --format='value(spec.template.spec.containers[0].image)')"
[[ "$service_image" =~ @sha256:[0-9a-f]{64}$ ]] || die "Backend is not pinned to an immutable image digest."

[[ "${CLOUD_RUN_CORS_CHANGE_APPROVED:-}" == "YES" ]] || die "This change creates a backend revision; set CLOUD_RUN_CORS_CHANGE_APPROVED=YES after approval."
read -r -p 'Type APPROVE-UPDATE-CLOUD-RUN-CORS to add the verified origins: ' CORS_CONFIRM
[[ "$CORS_CONFIRM" == "APPROVE-UPDATE-CLOUD-RUN-CORS" ]] || die "CORS update cancelled; no revision was created."

gcloud run services update "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --update-env-vars="FRONTEND_ORIGIN=${FRONTEND_ORIGIN},MOBILE_WEB_ORIGIN=${mobile_origin}" \
  --quiet

service_config="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json)" \
  || die "Could not verify the backend CORS revision."
python3 - "$service_config" "$FRONTEND_ORIGIN" "$mobile_origin" <<'PY' \
  || die "Backend CORS configuration did not match the exact Cloud Run frontend origin."
import json
import sys

data = json.loads(sys.argv[1])
containers = data.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
env = {item["name"]: item.get("value", "") for item in (containers[0].get("env", []) if containers else [])}
expected_frontend, expected_mobile = sys.argv[2:]
if env.get("FRONTEND_ORIGIN") != expected_frontend or env.get("MOBILE_WEB_ORIGIN") != expected_mobile:
    raise SystemExit("CORS values do not match the verified frontend origin.")
if "*" in env.get("FRONTEND_ORIGIN", "") or "*" in env.get("MOBILE_WEB_ORIGIN", ""):
    raise SystemExit("Wildcard CORS is forbidden.")
scaling = data.get("spec", {}).get("template", {}).get("scaling", {})
annotations = {}
annotations.update(data.get("metadata", {}).get("annotations", {}))
annotations.update(data.get("spec", {}).get("template", {}).get("metadata", {}).get("annotations", {}))
minimums = [
    data.get("spec", {}).get("scaling", {}).get("minInstanceCount"),
    scaling.get("minInstanceCount"),
    annotations.get("autoscaling.knative.dev/minScale"),
    annotations.get("run.googleapis.com/minScale"),
]
if not any(value is not None for value in minimums):
    raise SystemExit("Backend minimum-instance setting could not be verified.")
if any(value is not None and str(value) not in {"0", ""} for value in minimums):
    raise SystemExit("Backend must retain scale-to-zero after the CORS update.")
print("Backend CORS configuration: PASS (exact frontend URL; no wildcard; scale-to-zero retained)")
PY

code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 20 "$service_url/health")" \
  || die "Backend health request failed after the CORS revision."
[[ "$code" == "200" ]] || die "Backend returned HTTP $code after the CORS revision."
printf 'BACKEND_URL=%s\n' "$service_url"
printf 'BACKEND_IMAGE=%s\n' "$service_image"
printf 'CORS_UPDATE=PASS (new revision retained the immutable backend image and returned HTTP 200)\n'
