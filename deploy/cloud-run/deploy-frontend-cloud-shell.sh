#!/usr/bin/env bash
# Deploy a prebuilt, immutable React frontend image as a public Cloud Run site.
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
[[ "$IMAGE_TAG" =~ ^[a-f0-9]{40}$ ]] || die "Set IMAGE_TAG to the full immutable source commit SHA."
[[ "$API_BASE_URL" =~ ^https://[^,]+$ ]] || die "Set API_BASE_URL to the verified HTTPS Cloud Run API origin."
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."
python3 - "$API_BASE_URL" <<'PY'
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
if not parsed.hostname or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
    raise SystemExit("API_BASE_URL must be an HTTPS origin without a path, query, or fragment.")
if parsed.hostname.endswith("onrender.com") or parsed.hostname.endswith(".invalid"):
    raise SystemExit("The frontend image cannot target Render or a placeholder API.")
PY

for api in run.googleapis.com artifactregistry.googleapis.com; do
  api_state="$(gcloud services describe "$api" --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || true)"
  [[ "$api_state" == "ENABLED" ]] || die "Required API is not enabled: $api. This script will not enable APIs."
done

tag_ref="${IMAGE_PATH}:${IMAGE_TAG}"
digest="$(gcloud artifacts docker images describe "$tag_ref" --project="$PROJECT_ID" \
  --format='value(image_summary.digest)' 2>/dev/null || true)"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "The immutable frontend image tag did not resolve to a digest."
image_ref="${IMAGE_PATH}@${digest}"
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet >/dev/null
docker pull "$image_ref" >/dev/null
docker run --rm --network=none --read-only --entrypoint sh "$image_ref" -c \
  "grep -R -F -- '$API_BASE_URL' /usr/share/nginx/html/assets >/dev/null" \
  || die "The frontend image does not contain the verified Cloud Run API origin."
docker run --rm --network=none --read-only --entrypoint sh "$image_ref" -c \
  "if grep -R -E 'onrender\\.com|api-base-url-required\\.invalid' /usr/share/nginx/html/assets >/dev/null; then exit 1; fi" \
  || die "The frontend image contains a blocked Render or placeholder API origin."

existing="$(gcloud run services list --project="$PROJECT_ID" --region="$REGION" \
  --filter="metadata.name=$SERVICE" --format='value(metadata.name)')"
[[ -z "$existing" ]] || die "Cloud Run service $SERVICE already exists; this first-deployment script will not update it."

[[ "${CLOUD_RUN_COST_APPROVED:-}" == "YES" ]] || die "Approve public frontend Cloud Run charges by setting CLOUD_RUN_COST_APPROVED=YES."
[[ "${PUBLIC_FRONTEND_APPROVED:-}" == "YES" ]] || die "Approve public unauthenticated website access by setting PUBLIC_FRONTEND_APPROVED=YES."
read -r -p 'Type APPROVE-CLOUD-RUN-FRONTEND to create the public site: ' DEPLOY_CONFIRM
[[ "$DEPLOY_CONFIRM" == "APPROVE-CLOUD-RUN-FRONTEND" ]] || die "Deployment cancelled; no Cloud Run service was created."

gcloud run deploy "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$image_ref" \
  --port=8080 \
  --cpu=1 \
  --memory=512Mi \
  --concurrency=80 \
  --min=0 \
  --max=3 \
  --timeout=30 \
  --allow-unauthenticated \
  --quiet

service_url="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
  --format='value(status.url)')"
[[ "$service_url" =~ ^https:// ]] || die "Cloud Run did not return an HTTPS frontend URL."
http_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 20 "$service_url/")" \
  || die "Frontend health request failed."
[[ "$http_code" == "200" ]] || die "Frontend returned HTTP $http_code instead of 200."
printf 'FRONTEND_URL=%s\n' "$service_url"
printf 'IMAGE_REF=%s\n' "$image_ref"
printf 'FRONTEND_DEPLOYMENT=PASS (HTTPS site returned HTTP 200; API URL and image digest verified)\n'
