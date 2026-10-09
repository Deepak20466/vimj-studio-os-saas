#!/usr/bin/env bash
# Read-only Cloud Run image verification: pin an Artifact Registry digest and
# compare the complete Python application source fingerprint with this checkout.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
IMAGE_PATH="asia-south1-docker.pkg.dev/vimj-academy/cloud-run-source-deploy/vimj-backend"
IMAGE_TAG="${IMAGE_TAG:-}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
need docker
[[ "$IMAGE_TAG" =~ ^[a-f0-9]{7,40}$ ]] || die "Set IMAGE_TAG to the immutable Cloud Build commit SHA tag."
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."

image_tag_ref="${IMAGE_PATH}:${IMAGE_TAG}"
image_digest="$(gcloud artifacts docker images describe "$image_tag_ref" \
  --project="$PROJECT_ID" --format='value(image_summary.digest)' 2>/dev/null || true)"
[[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "The immutable image digest could not be resolved."
image_ref="${IMAGE_PATH}@${image_digest}"

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../backend" && pwd)"
docker pull "$image_ref" >/dev/null
source_hash="$(python3 - "$backend_dir/app" <<'PY'
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
image_hash="$(docker run --rm --network=none --read-only --user=10001:10001 \
  --entrypoint python3 "$image_ref" -c '
import hashlib
import json
import os
import pathlib
import sys

if os.environ.get("ENV") != "production" or os.environ.get("SCHEDULER_ENABLED", "").lower() != "true":
    raise SystemExit("image lacks production or guarded scheduler settings")
if "DATABASE_URL" in os.environ or "JWT_SECRET_KEY" in os.environ:
    raise SystemExit("image contains a runtime secret environment variable")
root = pathlib.Path("/app")
if (root / "alembic").exists() or (root / "alembic.ini").exists():
    raise SystemExit("image unexpectedly contains Alembic migration files")
digest = hashlib.sha256()
files = sorted((root / "app").rglob("*.py")) + [root / "requirements.txt", root / "gunicorn_conf.py"]
for path in files:
    relative = path.relative_to(root).as_posix().encode("utf-8")
    digest.update(len(relative).to_bytes(4, "big"))
    digest.update(relative)
    digest.update(hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).digest())
print(digest.hexdigest())
')" || die "The immutable image runtime/source checks failed."
[[ "$source_hash" == "$image_hash" ]] || die "Image Python source fingerprint does not match this checkout."

image_identity="$(docker image inspect "$image_ref" --format '{{.Config.User}}|{{.Config.WorkingDir}}|{{json .Config.Cmd}}')"
python3 - "$image_identity" <<'PY'
import json
import sys

user, workdir, command_json = sys.argv[1].split("|", 2)
command = " ".join(json.loads(command_json or "[]"))
if user != "10001:10001" or workdir != "/app":
    raise SystemExit("ERROR: image must run as the non-root app user from /app.")
if "gunicorn" not in command or "app.main:app" not in command or "alembic" in command.lower():
    raise SystemExit("ERROR: image startup command is not the reviewed migration-free API command.")
PY

printf 'IMAGE_REF=%s\n' "$image_ref"
printf 'IMAGE_DIGEST=%s\n' "$image_digest"
printf 'PYTHON_SOURCE_SHA256=%s\n' "$source_hash"
printf 'IMAGE_FINGERPRINT=PASS (immutable digest, exact source, non-root, no baked secrets, no migrations)\n'
