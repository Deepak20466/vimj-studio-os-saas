#!/usr/bin/env bash
# Create/configure the gated Cloud Tasks queue used by the scheduled job handlers.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
QUEUE_ID="vimj-scheduled-jobs"
QUEUE_NAME="projects/${PROJECT_ID}/locations/${REGION}/queues/${QUEUE_ID}"
RUNTIME_SERVICE_ACCOUNT="${RUNTIME_SERVICE_ACCOUNT:-}"
TASKS_SERVICE_ACCOUNT_EMAIL="${CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL:-${CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL:-}}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to ${PROJECT_ID}."
[[ "$RUNTIME_SERVICE_ACCOUNT" =~ ^[A-Za-z0-9._%+-]+@vimj-academy\.iam\.gserviceaccount\.com$ ]] \
  || die "Set RUNTIME_SERVICE_ACCOUNT to the existing dedicated Cloud Run service account."
[[ "$TASKS_SERVICE_ACCOUNT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@vimj-academy\.iam\.gserviceaccount\.com$ ]] \
  || die "Set CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL to an existing VIMJ service account used for task OIDC tokens."

for api in cloudtasks.googleapis.com iam.googleapis.com; do
  api_state="$(gcloud services describe "$api" --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || true)"
  [[ "$api_state" == "ENABLED" ]] || die "Required API is not enabled: $api. This script will not enable APIs."
done

gcloud iam service-accounts describe "$RUNTIME_SERVICE_ACCOUNT" --project="$PROJECT_ID" --format='value(email)' >/dev/null \
  || die "Cloud Run runtime service account does not exist."
gcloud iam service-accounts describe "$TASKS_SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" --format='value(email)' >/dev/null \
  || die "Cloud Tasks OIDC service account does not exist."
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
TASKS_AGENT="service-${PROJECT_NUMBER}@gcp-sa-cloudtasks.iam.gserviceaccount.com"
PROJECT_IAM="$(gcloud projects get-iam-policy "$PROJECT_ID" --format=json)" \
  || die "Could not inspect project IAM for the Cloud Tasks service agent."
python3 - "$PROJECT_IAM" "$TASKS_AGENT" <<'PY' \
  || die "Cloud Tasks service agent is not active; this script will not grant project-wide IAM roles."
import json
import sys

policy, agent = sys.argv[1:]
member = "serviceAccount:" + agent
data = json.loads(policy)
if not any(
    binding.get("role") == "roles/cloudtasks.serviceAgent" and member in binding.get("members", [])
    for binding in data.get("bindings", [])
):
    raise SystemExit("Cloud Tasks primary service agent lacks its Google-managed service-agent role.")
print("Cloud Tasks service agent: PASS (Google-managed service-agent role is present)")
PY

EXISTING_QUEUE=""
EXISTING_QUEUE_CONFIG=""
if gcloud tasks queues describe "$QUEUE_ID" --project="$PROJECT_ID" --location="$REGION" --format=json >/dev/null 2>&1; then
  EXISTING_QUEUE="YES"
  EXISTING_QUEUE_CONFIG="$(gcloud tasks queues describe "$QUEUE_ID" --project="$PROJECT_ID" --location="$REGION" --format=json)" \
    || die "Could not read the existing Cloud Tasks queue."
  python3 - "$EXISTING_QUEUE_CONFIG" "$QUEUE_NAME" <<'PY' \
    || die "An existing queue does not match the reviewed task retry and dispatch policy; no IAM policy was changed."
import json
import sys

data = json.loads(sys.argv[1])
if data.get("name") != sys.argv[2] or data.get("state") != "RUNNING":
    raise SystemExit("Existing queue must be the reviewed RUNNING queue.")
limits = data.get("rateLimits", {})
retry = data.get("retryConfig", {})
if limits.get("maxConcurrentDispatches") != 5 or limits.get("maxDispatchesPerSecond") != 10.0:
    raise SystemExit("Existing queue must have the reviewed concurrency 5 / 10 dispatches-per-second limits.")
if retry.get("maxAttempts") != 5 or retry.get("maxRetryDuration") != "1800s":
    raise SystemExit("Existing queue must have the reviewed five-attempt / 30-minute retry policy.")
print("Existing queue configuration: PASS (no queue changes requested)")
PY
fi

[[ "${CLOUD_TASKS_COST_APPROVED:-}" == "YES" ]] \
  || die "Approve the Cloud Tasks queue and per-operation charges before setup."
[[ "${CLOUD_TASKS_IAM_APPROVED:-}" == "YES" ]] \
  || die "Approve the queue-scoped enqueuer and service-account-scoped token permissions before setup."
read -r -p 'Type APPROVE-CONFIGURE-CLOUD-TASKS to configure the scheduled-jobs queue: ' APPROVAL
[[ "$APPROVAL" == "APPROVE-CONFIGURE-CLOUD-TASKS" ]] \
  || die "Cloud Tasks setup cancelled; no queue or IAM policy was changed."

if [[ -z "$EXISTING_QUEUE" ]]; then
  gcloud tasks queues create "$QUEUE_ID" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --max-dispatches-per-second=10 \
    --max-concurrent-dispatches=5 \
    --max-attempts=5 \
    --max-retry-duration=1800s \
    --min-backoff=10s \
    --max-backoff=120s \
    --max-doublings=3 \
    --quiet
fi

QUEUE_POLICY="$(gcloud tasks queues get-iam-policy "$QUEUE_ID" --project="$PROJECT_ID" --location="$REGION" --format=json)" \
  || die "Could not read the queue IAM policy."
python3 - "$QUEUE_POLICY" "$RUNTIME_SERVICE_ACCOUNT" <<'PY' \
  || gcloud tasks queues add-iam-policy-binding "$QUEUE_ID" \
       --project="vimj-academy" --location="asia-south1" \
       --member="serviceAccount:${RUNTIME_SERVICE_ACCOUNT}" --role="roles/cloudtasks.enqueuer" --quiet \
       || die "Could not grant queue-scoped Cloud Tasks Enqueuer to the runtime account."
import json
import sys

policy, runtime = sys.argv[1:]
member = "serviceAccount:" + runtime
allowed = any(
    binding.get("role") == "roles/cloudtasks.enqueuer"
    and member in binding.get("members", [])
    and not binding.get("condition")
    for binding in json.loads(policy).get("bindings", [])
)
if not allowed:
    raise SystemExit("Cloud Run runtime account lacks the queue-scoped Cloud Tasks Enqueuer grant.")
print("Runtime queue permission: PASS")
PY

QUEUE_POLICY="$(gcloud tasks queues get-iam-policy "$QUEUE_ID" --project="$PROJECT_ID" --location="$REGION" --format=json)" \
  || die "Could not read back the queue IAM policy."
python3 - "$QUEUE_POLICY" "$RUNTIME_SERVICE_ACCOUNT" <<'PY' \
  || die "Queue-scoped Cloud Tasks Enqueuer grant did not verify after setup."
import json
import sys

policy, runtime = sys.argv[1:]
member = "serviceAccount:" + runtime
if not any(
    binding.get("role") == "roles/cloudtasks.enqueuer"
    and member in binding.get("members", [])
    and not binding.get("condition")
    for binding in json.loads(policy).get("bindings", [])
):
    raise SystemExit("Queue-scoped Cloud Tasks Enqueuer grant did not read back.")
print("Queue IAM read-back: PASS")
PY

SERVICE_ACCOUNT_POLICY="$(gcloud iam service-accounts get-iam-policy "$TASKS_SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" --format=json)" \
  || die "Could not inspect the task OIDC service-account policy."
if ! python3 - "$SERVICE_ACCOUNT_POLICY" "$RUNTIME_SERVICE_ACCOUNT" "$TASKS_AGENT" <<'PY'
import json
import sys

policy, runtime, agent = sys.argv[1:]
bindings = json.loads(policy).get("bindings", [])
def has_user(member):
    return any(
        item.get("role") == "roles/iam.serviceAccountUser"
        and member in item.get("members", [])
        and not item.get("condition")
        for item in bindings
    )
if not has_user("serviceAccount:" + runtime) or not has_user("serviceAccount:" + agent):
    raise SystemExit("Runtime or Cloud Tasks service agent lacks service-account-scoped Service Account User permission.")
print("Task OIDC identity permissions: PASS")
PY
then
  gcloud iam service-accounts add-iam-policy-binding "$TASKS_SERVICE_ACCOUNT_EMAIL" \
    --project="vimj-academy" --member="serviceAccount:${RUNTIME_SERVICE_ACCOUNT}" \
    --role="roles/iam.serviceAccountUser" --quiet \
    || die "Could not grant the runtime account permission to attach the task OIDC identity."
  gcloud iam service-accounts add-iam-policy-binding "$TASKS_SERVICE_ACCOUNT_EMAIL" \
    --project="vimj-academy" --member="serviceAccount:${TASKS_AGENT}" \
    --role="roles/iam.serviceAccountUser" --quiet \
    || die "Could not grant the Cloud Tasks service agent permission to mint task OIDC tokens."
fi

SERVICE_ACCOUNT_POLICY="$(gcloud iam service-accounts get-iam-policy "$TASKS_SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" --format=json)" \
  || die "Could not read back the task OIDC service-account policy."
python3 - "$SERVICE_ACCOUNT_POLICY" "$RUNTIME_SERVICE_ACCOUNT" "$TASKS_AGENT" <<'PY' \
  || die "Task OIDC service-account permissions did not verify after setup."
import json
import sys

policy, runtime, agent = sys.argv[1:]
bindings = json.loads(policy).get("bindings", [])
def has_user(member):
    return any(
        item.get("role") == "roles/iam.serviceAccountUser"
        and member in item.get("members", [])
        and not item.get("condition")
        for item in bindings
    )
if not has_user("serviceAccount:" + runtime) or not has_user("serviceAccount:" + agent):
    raise SystemExit("Runtime or Cloud Tasks service agent grant did not read back.")
print("Task OIDC IAM read-back: PASS")
PY

QUEUE_CONFIG="$(gcloud tasks queues describe "$QUEUE_ID" --project="$PROJECT_ID" --location="$REGION" --format=json)" \
  || die "Could not verify the Cloud Tasks queue."
python3 - "$QUEUE_CONFIG" "$QUEUE_NAME" <<'PY' \
  || die "Cloud Tasks queue settings do not match the reviewed runtime limits."
import json
import sys

queue, expected_name = sys.argv[1:]
data = json.loads(queue)
if data.get("name") != expected_name or data.get("state") != "RUNNING":
    raise SystemExit("The scheduled-jobs queue name or state is incorrect.")
limits = data.get("rateLimits", {})
retry = data.get("retryConfig", {})
if limits.get("maxConcurrentDispatches") != 5 or limits.get("maxDispatchesPerSecond") != 10.0:
    raise SystemExit("Cloud Tasks dispatch limits do not match concurrency 5 / 10 dispatches per second.")
if retry.get("maxAttempts") != 5 or retry.get("maxRetryDuration") != "1800s":
    raise SystemExit("Cloud Tasks retry policy does not match five attempts / 30 minutes.")
print("Cloud Tasks queue: PASS (running; max 5 concurrent tasks; bounded retry policy)")
PY

printf 'CLOUD_TASKS_QUEUE=%s\nCLOUD_TASKS_SETUP=PASS\n' "$QUEUE_NAME"
