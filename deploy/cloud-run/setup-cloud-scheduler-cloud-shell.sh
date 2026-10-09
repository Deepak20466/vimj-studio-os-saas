#!/usr/bin/env bash
# Create the single OIDC-authenticated minute tick after production gates pass.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
REGION="asia-south1"
SERVICE="vimj-backend"
JOB_ID="vimj-minute-dispatch"
JOB_NAME="projects/${PROJECT_ID}/locations/${REGION}/jobs/${JOB_ID}"
SERVICE_ACCOUNT_EMAIL="${CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL:-}"
CLOUD_TASKS_QUEUE_NAME="${CLOUD_TASKS_QUEUE_NAME:-projects/${PROJECT_ID}/locations/${REGION}/queues/vimj-scheduled-jobs}"
CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL="${CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL:-$SERVICE_ACCOUNT_EMAIL}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to ${PROJECT_ID}."
[[ "$SERVICE_ACCOUNT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.iam\.gserviceaccount\.com$ ]] \
  || die "Set CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL to the reviewed, pre-existing scheduler service account."
[[ "$CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.iam\.gserviceaccount\.com$ ]] \
  || die "Set CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL to the reviewed, pre-existing task OIDC service account."
[[ "$CLOUD_TASKS_QUEUE_NAME" == "projects/${PROJECT_ID}/locations/${REGION}/queues/"* ]] \
  || die "CLOUD_TASKS_QUEUE_NAME must be the reviewed queue in ${PROJECT_ID}/${REGION}."

enabled_apis="$(gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' 2>/dev/null)" \
  || die "Could not verify enabled APIs; this script will not enable APIs."
for api in cloudscheduler.googleapis.com cloudtasks.googleapis.com run.googleapis.com iam.googleapis.com; do
  if ! grep -Fxq "$api" <<<"$enabled_apis"; then
    die "Required API is not enabled or could not be verified: $api. This script will not enable APIs."
  fi
done

SERVICE_URL="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"
[[ "$SERVICE_URL" =~ ^https://[^/]+$ ]] || die "Backend service does not have a canonical HTTPS URL."
SERVICE_CONFIG="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json)" \
  || die "Could not inspect the backend service configuration."
TASKS_QUEUE_ID="${CLOUD_TASKS_QUEUE_NAME##*/}"
TASKS_QUEUE_CONFIG="$(gcloud tasks queues describe "$TASKS_QUEUE_ID" --project="$PROJECT_ID" --location="$REGION" --format=json)" \
  || die "Cloud Tasks queue is missing; run the separately gated queue setup first."
IAM_POLICY="$(gcloud run services get-iam-policy "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json)" \
  || die "Could not inspect the backend invocation policy."
python3 - "$SERVICE_CONFIG" "$IAM_POLICY" "$TASKS_QUEUE_CONFIG" "$SERVICE_URL" \
  "$SERVICE_ACCOUNT_EMAIL" "$JOB_NAME" "$CLOUD_TASKS_QUEUE_NAME" "$CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL" <<'PY' \
  || die "Backend scheduler configuration or public API invocation policy failed verification."
import json
import sys

service, policy, queue_json, expected_url, expected_email, expected_job, expected_queue, expected_tasks_email = sys.argv[1:]
data = json.loads(service)
spec = data.get("spec", {})
template = spec.get("template", {})
containers = template.get("spec", {}).get("containers", [])
env = {
    item["name"]: item.get("value", "")
    for item in (containers[0].get("env", []) if containers else [])
}
if env.get("ENV") != "production" or env.get("SCHEDULER_ENABLED", "").lower() != "false":
    raise SystemExit("Backend must be production mode with the in-process scheduler disabled.")
if env.get("CLOUD_SCHEDULER_OIDC_AUDIENCE") != expected_url:
    raise SystemExit("Backend OIDC audience does not match its canonical Cloud Run URL.")
if env.get("CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "").lower() != expected_email.lower():
    raise SystemExit("Backend is not configured for the reviewed Cloud Scheduler service account.")
if env.get("CLOUD_SCHEDULER_JOB_NAME") != expected_job:
    raise SystemExit("Backend job-name allowlist does not match the Cloud Scheduler resource.")
if env.get("CLOUD_TASKS_QUEUE_NAME") != expected_queue or env.get("CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL", "").lower() != expected_tasks_email.lower():
    raise SystemExit("Backend Cloud Tasks queue or OIDC service account does not match the reviewed resource.")
queue = json.loads(queue_json)
limits = queue.get("rateLimits", {})
retry = queue.get("retryConfig", {})
if queue.get("name") != expected_queue or queue.get("state") != "RUNNING":
    raise SystemExit("Cloud Tasks queue must be the reviewed RUNNING queue.")
if limits.get("maxConcurrentDispatches") != 5 or limits.get("maxDispatchesPerSecond") != 10.0:
    raise SystemExit("Cloud Tasks dispatch limits are not the reviewed bounded values.")
if retry.get("maxAttempts") != 5 or retry.get("maxRetryDuration") != "1800s":
    raise SystemExit("Cloud Tasks retry policy is not the reviewed bounded policy.")
public = any(
    binding.get("role") == "roles/run.invoker" and "allUsers" in binding.get("members", [])
    for binding in json.loads(policy).get("bindings", [])
)
if not public:
    raise SystemExit("The backend must already have the separately approved public API invocation policy.")
print("Backend configuration: PASS (public API gate, scale-to-zero mode, exact OIDC identity/audience/job name)")
PY

gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" --format='value(email)' >/dev/null \
  || die "The reviewed Cloud Scheduler service account does not exist; this script will not create one."
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
SCHEDULER_AGENT="service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
SERVICE_ACCOUNT_POLICY="$(gcloud iam service-accounts get-iam-policy "$SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" --format=json)" \
  || die "Could not inspect the Cloud Scheduler service-account policy."
python3 - "$SERVICE_ACCOUNT_POLICY" "$SCHEDULER_AGENT" <<'PY' \
  || die "Cloud Scheduler service-agent permission is missing; no IAM change was made."
import json
import sys

policy = json.loads(sys.argv[1])
member = "serviceAccount:" + sys.argv[2]
allowed = any(
    binding.get("role") == "roles/iam.serviceAccountTokenCreator" and member in binding.get("members", [])
    for binding in policy.get("bindings", [])
)
if not allowed:
    raise SystemExit("Cloud Scheduler service agent lacks Token Creator on the selected service account.")
print("OIDC token-minting permission: PASS (pre-existing, service-account scoped grant)")
PY

gcloud scheduler jobs describe "$JOB_ID" --project="$PROJECT_ID" --location="$REGION" >/dev/null 2>&1 \
  && die "Cloud Scheduler job ${JOB_NAME} already exists; refusing to replace or reconfigure it."

[[ "${SCHEDULER_HANDOFF_APPROVED:-}" == "YES" ]] \
  || die "Confirm the old Render/background scheduler is suspended and set SCHEDULER_HANDOFF_APPROVED=YES."
[[ "${PRODUCTION_API_E2E_PASSED:-}" == "YES" ]] \
  || die "Complete and record the read-only Admin/Coach production API E2E checks first."
[[ "${CLOUD_SCHEDULER_COST_APPROVED:-}" == "YES" ]] \
  || die "Approve the Cloud Scheduler job and Cloud Run request charges first."
[[ "${SCHEDULED_NOTIFICATIONS_APPROVED:-}" == "YES" ]] \
  || die "Approve activation of all 11 production jobs, including messages to live recipients."
read -r -p 'Type APPROVE-ENABLE-CLOUD-SCHEDULER-JOBS to start all production schedules: ' APPROVAL
[[ "$APPROVAL" == "APPROVE-ENABLE-CLOUD-SCHEDULER-JOBS" ]] \
  || die "Scheduler activation cancelled; no job was created."

gcloud scheduler jobs create http "$JOB_ID" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --schedule='* * * * *' \
  --time-zone='Asia/Kolkata' \
  --uri="${SERVICE_URL}/internal/scheduler/tick" \
  --http-method=POST \
  --oidc-service-account-email="$SERVICE_ACCOUNT_EMAIL" \
  --oidc-token-audience="$SERVICE_URL" \
  --attempt-deadline=60s \
  --max-retry-attempts=1 \
  --max-retry-duration=30s \
  --min-backoff=5s \
  --max-backoff=30s \
  --quiet

JOB_CONFIG="$(gcloud scheduler jobs describe "$JOB_ID" --project="$PROJECT_ID" --location="$REGION" --format=json)" \
  || die "Could not verify the created Cloud Scheduler job."
python3 - "$JOB_CONFIG" "$SERVICE_URL" "$SERVICE_ACCOUNT_EMAIL" <<'PY' \
  || die "Cloud Scheduler configuration failed post-creation verification."
import json
import sys

job = json.loads(sys.argv[1])
uri = job.get("httpTarget", {}).get("uri", "")
oidc = job.get("httpTarget", {}).get("oidcToken", {})
if job.get("schedule") != "* * * * *" or job.get("timeZone") != "Asia/Kolkata":
    raise SystemExit("Cloud Scheduler does not use the every-minute Asia/Kolkata schedule.")
if uri != sys.argv[2] + "/internal/scheduler/tick":
    raise SystemExit("Cloud Scheduler URI does not match the authenticated backend route.")
if oidc.get("audience") != sys.argv[2] or oidc.get("serviceAccountEmail", "").lower() != sys.argv[3].lower():
    raise SystemExit("Cloud Scheduler OIDC audience or service account does not match the reviewed value.")
if job.get("state") != "ENABLED":
    raise SystemExit("Cloud Scheduler job is not enabled.")
retry = job.get("retryConfig", {})
if retry.get("retryCount") != 1 or retry.get("maxRetryDuration") != "30s" or job.get("attemptDeadline") != "60s":
    raise SystemExit("Cloud Scheduler retry settings do not match the reviewed short retry window.")
print("Cloud Scheduler configuration: PASS (enabled, every minute, Asia/Kolkata, OIDC identity pinned; tasks enqueued asynchronously)")
PY

printf 'SCHEDULER_JOB=%s\nBACKEND_URL=%s\nSCHEDULER_SETUP=PASS\n' "$JOB_NAME" "$SERVICE_URL"
