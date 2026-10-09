#!/usr/bin/env bash
# Build and push one immutable Cloud Run image from the exact clean checkout.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
ACTION="${1:-}"
API_BASE_URL="${API_BASE_URL:-}"
BUILD_COMMIT="${BUILD_COMMIT:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need git
need python3
[[ "$ACTION" == "backend" || "$ACTION" == "frontend" ]] || die "Usage: $0 backend|frontend"
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."

if [[ -z "$BUILD_COMMIT" ]]; then
  BUILD_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
fi
[[ "$BUILD_COMMIT" =~ ^[a-f0-9]{40}$ ]] || die "BUILD_COMMIT must be the full 40-character commit SHA."
[[ "$(git -C "$ROOT_DIR" rev-parse HEAD)" == "$BUILD_COMMIT" ]] \
  || die "The checked-out commit does not match BUILD_COMMIT."
[[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]] \
  || die "Commit and push the reviewed source first; Cloud Build refuses a dirty checkout."

for api in cloudbuild.googleapis.com artifactregistry.googleapis.com; do
  if ! gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' \
      | grep -Fxq "$api"; then
    die "Required API is not enabled or could not be verified: $api. This script will not enable APIs."
  fi
done

SUBSTITUTIONS="_IMAGE_TAG=${BUILD_COMMIT}"
CONFIG="${ROOT_DIR}/deploy/cloud-run/cloudbuild-backend.yaml"
if [[ "$ACTION" == "frontend" ]]; then
  [[ "${API_BASE_URL}" =~ ^https://[^,]+$ ]] || die "Set API_BASE_URL to the verified HTTPS Cloud Run API URL."
  python3 - "$API_BASE_URL" <<'PY'
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
if not parsed.hostname or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
    raise SystemExit("API_BASE_URL must be an HTTPS origin without a path, query, or fragment.")
if parsed.hostname.endswith("onrender.com") or parsed.hostname.endswith(".invalid"):
    raise SystemExit("The frontend image cannot target Render or a placeholder API.")
PY
  CONFIG="${ROOT_DIR}/deploy/cloud-run/cloudbuild-frontend.yaml"
  SUBSTITUTIONS+=",_API_BASE_URL=${API_BASE_URL}"
fi

[[ "${CLOUD_BUILD_APPROVED:-}" == "YES" ]] \
  || die "Cloud Build uploads source, pushes an image, and incurs charges; set CLOUD_BUILD_APPROVED=YES after approval."
read -r -p "Type APPROVE-CLOUD-BUILD-${ACTION^^} to build and push the immutable image: " BUILD_CONFIRM
[[ "$BUILD_CONFIRM" == "APPROVE-CLOUD-BUILD-${ACTION^^}" ]] || die "Build cancelled; Cloud Build was not submitted."

gcloud builds submit "$ROOT_DIR" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --config="$CONFIG" \
  --substitutions="$SUBSTITUTIONS" \
  --quiet

printf 'BUILD_COMMIT=%s\n' "$BUILD_COMMIT"
printf 'IMAGE_TAG=%s\n' "$BUILD_COMMIT"
printf 'BUILD_RESULT=PASS (%s image pushed to the existing Artifact Registry repository)\n' "$ACTION"
