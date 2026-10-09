#!/usr/bin/env bash
# Create a reviewed frontend revision while preserving its current public policy.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
SERVICE="vimj-frontend"
IMAGE_PATH="asia-south1-docker.pkg.dev/vimj-academy/cloud-run-source-deploy/vimj-frontend"
IMAGE_TAG="${IMAGE_TAG:-}"
API_BASE_URL="${API_BASE_URL:-}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
need docker
need curl
[[ "$IMAGE_TAG" =~ ^[a-f0-9]{40}$ ]] || die "Set IMAGE_TAG to the full immutable commit SHA."
[[ "$API_BASE_URL" =~ ^https://[^,]+$ ]] || die "Set API_BASE_URL to the verified HTTPS backend origin."
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."
python3 - "$API_BASE_URL" <<'PY'
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
if not parsed.hostname or parsed.path not in {"", "/"} or parsed.query or parsed.fragment or parsed.username:
    raise SystemExit("API_BASE_URL must be an HTTPS origin without paths, credentials, queries, or fragments.")
if parsed.hostname.endswith("onrender.com") or parsed.hostname.endswith(".invalid"):
    raise SystemExit("Blocked or placeholder API origin.")
PY

tag_ref="${IMAGE_PATH}:${IMAGE_TAG}"
digest="$(gcloud artifacts docker images describe "$tag_ref" --project="$PROJECT_ID" \
  --format='value(image_summary.digest)' 2>/dev/null || true)"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "The immutable frontend image digest could not be resolved."
image_ref="${IMAGE_PATH}@${digest}"
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet >/dev/null
docker pull "$image_ref" >/dev/null
docker run --rm --network=none --read-only --entrypoint sh "$image_ref" -c \
  "grep -R -F -- '$API_BASE_URL' /usr/share/nginx/html/assets >/dev/null" \
  || die "The frontend image is not built for the verified API URL."
docker run --rm --network=none --read-only --entrypoint sh "$image_ref" -c \
  "if grep -R -E 'onrender\\.com|api-base-url-required\\.invalid' /usr/share/nginx/html/assets >/dev/null; then exit 1; fi" \
  || die "The frontend image contains a blocked Render or placeholder API origin."

service_url="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
  --format='value(status.url)' 2>/dev/null || true)"
[[ "$service_url" == https://* ]] || die "The existing frontend service was not found."
if gcloud run services get-iam-policy "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json \
  | python3 -c 'import json,sys; p=json.load(sys.stdin); raise SystemExit(0 if any(b.get("role")=="roles/run.invoker" and "allUsers" in b.get("members",[]) for b in p.get("bindings",[])) else 1)'; then
  :
else
  die "Existing frontend is not publicly invokable; refusing to change its IAM policy."
fi

[[ "${FRONTEND_UPDATE_APPROVED:-}" == "YES" ]] || die "Approve the frontend revision by setting FRONTEND_UPDATE_APPROVED=YES."
read -r -p 'Type APPROVE-UPDATE-CLOUD-RUN-FRONTEND to update only the frontend image: ' UPDATE_CONFIRM
[[ "$UPDATE_CONFIRM" == "APPROVE-UPDATE-CLOUD-RUN-FRONTEND" ]] || die "Update cancelled; no revision was created."

gcloud run services update "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$image_ref" \
  --quiet

http_code="$(curl --silent --show-error --connect-timeout 10 --max-time 30 \
  --output /dev/null --write-out '%{http_code}' "$service_url/" || true)"
[[ "$http_code" == "200" ]] || die "Updated frontend returned HTTP ${http_code:-no response}, expected 200."
printf 'FRONTEND_UPDATE=PASS\nIMAGE_REF=%s\nFRONTEND_URL=%s\n' "$image_ref" "$service_url"
printf 'Only the image changed; public access policy and other service settings were preserved.\n'
