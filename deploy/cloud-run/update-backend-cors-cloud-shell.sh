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
python3 - "$FRONTEND_ORIGIN" "$MOBILE_WEB_ORIGIN" <<'PY'
from urllib.parse import urlparse
import sys

for origin in sys.argv[1:]:
    if not origin:
        continue
    parsed = urlparse(origin)
    if not parsed.hostname or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
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

mobile_origin="$MOBILE_WEB_ORIGIN"
[[ -n "$mobile_origin" ]] || mobile_origin="$FRONTEND_ORIGIN"
gcloud run services update "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --update-env-vars="FRONTEND_ORIGIN=${FRONTEND_ORIGIN},MOBILE_WEB_ORIGIN=${mobile_origin}" \
  --quiet

code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 20 "$service_url/health")" \
  || die "Backend health request failed after the CORS revision."
[[ "$code" == "200" ]] || die "Backend returned HTTP $code after the CORS revision."
printf 'BACKEND_URL=%s\n' "$service_url"
printf 'BACKEND_IMAGE=%s\n' "$service_image"
printf 'CORS_UPDATE=PASS (new revision retained the immutable backend image and returned HTTP 200)\n'
