import binascii
import base64
import json
import logging

from fastapi import APIRouter, HTTPException, Request, status
from google.auth.exceptions import GoogleAuthError

from app.config import settings
from app.services.cloud_scheduler import (
    SchedulerJobsFailed,
    SchedulerTickBusy,
    _cloud_tasks_task_id,
    enqueue_cloud_scheduler_tick,
    parse_schedule_time,
    run_cloud_scheduler_job,
    verify_cloud_scheduler_identity,
)

logger = logging.getLogger("vimj.scheduler_endpoint")
router = APIRouter(tags=["internal-scheduler"])


def _oidc_claim_match_flags(
    authorization: str | None, service_account: str
) -> dict[str, bool] | None:
    """Return non-sensitive diagnostic flags without logging token claims or values."""
    if not authorization:
        return None
    scheme, separator, token = authorization.partition(" ")
    parts = token.strip().split(".")
    if not separator or scheme.lower() != "bearer" or len(parts) != 3:
        return None
    try:
        payload_segment = parts[1]
        payload_bytes = base64.urlsafe_b64decode(
            payload_segment + "=" * (-len(payload_segment) % 4)
        )
        claims = json.loads(payload_bytes)
    except (ValueError, TypeError, binascii.Error):
        return None
    if not isinstance(claims, dict):
        return None
    audience = claims.get("aud")
    expected_audience = settings.CLOUD_SCHEDULER_OIDC_AUDIENCE.strip()
    audience_matches = (
        expected_audience in audience
        if isinstance(audience, list)
        else audience == expected_audience
    )
    return {
        "issuer_google": claims.get("iss") in ("https://accounts.google.com", "accounts.google.com"),
        "audience_matches": audience_matches,
        "service_account_matches": str(claims.get("email", "")).strip().lower() == service_account.strip().lower(),
        "email_verified": claims.get("email_verified") is True,
    }


def _verify_google_identity(authorization: str | None, service_account: str) -> None:
    try:
        verify_cloud_scheduler_identity(authorization, service_account=service_account)
    except PermissionError as exc:
        logger.warning(
            "Google service identity denied (%s); OIDC claim checks=%s",
            str(exc),
            _oidc_claim_match_flags(authorization, service_account),
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    except (ValueError, GoogleAuthError) as exc:
        if isinstance(exc, GoogleAuthError):
            logger.warning("Google service identity verifier unavailable (%s)", type(exc).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Google service identity verification is temporarily unavailable",
            )
        logger.warning(
            "Google service identity token rejected (%s); OIDC claim checks=%s",
            type(exc).__name__,
            _oidc_claim_match_flags(authorization, service_account),
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    except Exception as exc:
        logger.warning("Google service identity verification failed (%s)", type(exc).__name__)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")


@router.post("/internal/scheduler/tick", include_in_schema=False)
def cloud_scheduler_tick(request: Request):
    """Verify Cloud Scheduler and quickly enqueue each due job as an OIDC task."""
    expected_job_name = settings.CLOUD_SCHEDULER_JOB_NAME.strip()
    scheduler_account = settings.CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL.strip()
    if not expected_job_name or not scheduler_account or not settings.CLOUD_SCHEDULER_OIDC_AUDIENCE.strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Cloud Scheduler is not configured",
        )

    actual_job_name = request.headers.get("X-CloudScheduler-JobName")
    if actual_job_name != expected_job_name:
        logger.warning(
            "Scheduler tick rejected: job-name header present=%s matches-configured-name=%s matches-job-id=%s",
            bool(actual_job_name),
            actual_job_name == expected_job_name,
            actual_job_name == expected_job_name.rsplit("/", 1)[-1],
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    _verify_google_identity(request.headers.get("Authorization"), scheduler_account)

    try:
        scheduled_for = parse_schedule_time(request.headers.get("X-CloudScheduler-ScheduleTime"))
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid schedule time")

    try:
        return enqueue_cloud_scheduler_tick(scheduled_for)
    except SchedulerTickBusy:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Another scheduler dispatch is active",
            headers={"Retry-After": "5"},
        )
    except SchedulerJobsFailed as exc:
        logger.error("Cloud Scheduler task enqueue failed for jobs: %s", ", ".join(exc.job_names))
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="One or more scheduled jobs could not be queued",
        )


@router.post("/internal/scheduler/run", include_in_schema=False)
async def cloud_scheduler_run(request: Request):
    """Run one Cloud Task only after exact queue, OIDC, and task-name checks."""
    queue = settings.CLOUD_TASKS_QUEUE_NAME.strip()
    task_account = settings.CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL.strip()
    audience = settings.CLOUD_SCHEDULER_OIDC_AUDIENCE.strip()
    if not queue or not task_account or not audience:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Cloud Tasks is not configured",
        )
    queue_parts = queue.split("/")
    if (
        len(queue_parts) != 6
        or queue_parts[0] != "projects"
        or queue_parts[2] != "locations"
        or queue_parts[4] != "queues"
        or request.headers.get("X-CloudTasks-QueueName") != queue_parts[5]
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    _verify_google_identity(request.headers.get("Authorization"), task_account)

    body = await request.body()
    if len(body) > 4096:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Invalid task")
    try:
        payload = json.loads(body)
        job_name = payload["job_name"]
        scheduled_for = parse_schedule_time(payload["scheduled_for"])
        attempt = payload["attempt"]
        if not isinstance(job_name, str) or not isinstance(attempt, int) or isinstance(attempt, bool):
            raise ValueError("Invalid task fields")
        if set(payload) != {"job_name", "scheduled_for", "attempt"}:
            raise ValueError("Unexpected task fields")
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid scheduled task")

    expected_task_id = _cloud_tasks_task_id(job_name, scheduled_for, attempt)
    if request.headers.get("X-CloudTasks-TaskName") != expected_task_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    try:
        return run_cloud_scheduler_job(job_name, scheduled_for, attempt)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid scheduled task")
    except SchedulerTickBusy:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Another execution of this scheduled job is active",
            headers={"Retry-After": "5"},
        )
    except SchedulerJobsFailed as exc:
        logger.error("Cloud Task job failed: %s", ", ".join(exc.job_names))
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Scheduled job failed and will be retried",
        )
