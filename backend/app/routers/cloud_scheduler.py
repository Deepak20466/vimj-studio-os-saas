import logging

from fastapi import APIRouter, HTTPException, Request, status
from google.auth.exceptions import GoogleAuthError

from app.config import settings
from app.services.cloud_scheduler import (
    SchedulerJobsFailed,
    SchedulerTickBusy,
    parse_schedule_time,
    run_cloud_scheduler_tick,
    verify_cloud_scheduler_identity,
)

logger = logging.getLogger("vimj.scheduler_endpoint")
router = APIRouter(tags=["internal-scheduler"])


@router.post("/internal/scheduler/tick", include_in_schema=False)
def cloud_scheduler_tick(request: Request):
    """Dispatch scheduled jobs only for the configured Google service account."""
    expected_job_name = settings.CLOUD_SCHEDULER_JOB_NAME.strip()
    if (
        not expected_job_name
        or not settings.CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL.strip()
        or not settings.CLOUD_SCHEDULER_OIDC_AUDIENCE.strip()
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Cloud Scheduler is not configured",
        )

    if request.headers.get("X-CloudScheduler-JobName") != expected_job_name:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    try:
        verify_cloud_scheduler_identity(request.headers.get("Authorization"))
    except PermissionError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    except (ValueError, GoogleAuthError) as exc:
        # A verifier key-fetch outage should be retried by Cloud Scheduler; an
        # invalid token is rejected below without exposing verifier details.
        if isinstance(exc, GoogleAuthError):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Cloud Scheduler identity verification is temporarily unavailable",
            )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    except Exception as exc:
        logger.warning("Cloud Scheduler identity verification failed (%s)", type(exc).__name__)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")

    try:
        scheduled_for = parse_schedule_time(request.headers.get("X-CloudScheduler-ScheduleTime"))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))

    try:
        return run_cloud_scheduler_tick(scheduled_for)
    except SchedulerTickBusy:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Another scheduled run is active",
            headers={"Retry-After": "5"},
        )
    except SchedulerJobsFailed as exc:
        logger.error("Cloud Scheduler jobs failed: %s", ", ".join(exc.job_names))
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="One or more scheduled jobs failed",
        )
