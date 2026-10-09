"""Authenticated, request-driven dispatcher for the Cloud Run scheduler tick."""
import logging
from datetime import datetime, timedelta, timezone

from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import id_token
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool

from app.config import settings
from app.database import SessionLocal
from app.models.scheduler_job_execution import SchedulerJobExecution
from app.services.scheduler import (
    SCHEDULER_JOB_DEFINITIONS,
    SCHEDULER_TIMEZONE,
    _scheduler_lock_url,
)

logger = logging.getLogger("vimj.cloud_scheduler")

_SCHEDULER_TICK_LOCK_KEY = 0x56494D4B
_EXECUTION_LEDGER_RETENTION = timedelta(days=2)


class SchedulerTickBusy(RuntimeError):
    """Another request currently owns the cross-instance scheduler lock."""


class SchedulerJobsFailed(RuntimeError):
    def __init__(self, job_names: list[str]):
        self.job_names = job_names
        super().__init__(", ".join(job_names))


def verify_cloud_scheduler_identity(authorization: str | None) -> None:
    """Verify Google's OIDC token, exact Cloud Scheduler identity, and audience."""
    expected_email = settings.CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL.strip().lower()
    expected_audience = settings.CLOUD_SCHEDULER_OIDC_AUDIENCE.strip()
    if not expected_email or not expected_audience:
        raise PermissionError("Cloud Scheduler identity is not configured")

    if not authorization:
        raise PermissionError("Missing Cloud Scheduler bearer token")
    scheme, separator, token = authorization.partition(" ")
    if not separator or scheme.lower() != "bearer" or not token.strip():
        raise PermissionError("Invalid Cloud Scheduler authorization header")

    claims = id_token.verify_oauth2_token(
        token.strip(), GoogleAuthRequest(), audience=expected_audience
    )
    actual_email = str(claims.get("email", "")).strip().lower()
    if actual_email != expected_email or claims.get("email_verified") is not True:
        raise PermissionError("Cloud Scheduler identity is not authorized")


def parse_schedule_time(value: str | None) -> datetime:
    """Parse Cloud Scheduler's RFC3339 schedule-time header into a UTC minute."""
    if not value:
        raise ValueError("Missing Cloud Scheduler schedule-time header")
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("Invalid Cloud Scheduler schedule-time header") from exc
    if parsed.tzinfo is None:
        raise ValueError("Cloud Scheduler schedule time must include a timezone")
    # Cloud Scheduler's header is RFC3339 and may include sub-minute precision.
    # Cron definitions in this dispatcher have minute precision, so normalize
    # to the represented minute instead of rejecting a valid delivery header.
    return parsed.astimezone(timezone.utc).replace(second=0, microsecond=0)


def _due_jobs(scheduled_local: datetime):
    current_minute = scheduled_local.replace(second=0, microsecond=0)
    previous_instant = current_minute - timedelta(microseconds=1)
    for job_name, (job_function, trigger) in SCHEDULER_JOB_DEFINITIONS.items():
        fire_time = trigger.get_next_fire_time(previous_instant, current_minute)
        if fire_time == current_minute:
            yield job_name, job_function


def _pending_job_runs(current_slot: datetime) -> list[tuple[str, datetime]]:
    """Return recent incomplete slots so a failed task retries on the next tick."""
    cutoff = current_slot - _EXECUTION_LEDGER_RETENTION
    db = SessionLocal()
    try:
        rows = (
            db.query(SchedulerJobExecution)
            .filter(
                SchedulerJobExecution.status.in_(("FAILED", "RUNNING")),
                SchedulerJobExecution.scheduled_for >= cutoff,
                SchedulerJobExecution.scheduled_for <= current_slot,
            )
            .order_by(SchedulerJobExecution.scheduled_for, SchedulerJobExecution.job_name)
            .all()
        )
        return [
            (
                row.job_name,
                row.scheduled_for.replace(tzinfo=timezone.utc)
                if row.scheduled_for.tzinfo is None
                else row.scheduled_for.astimezone(timezone.utc),
            )
            for row in rows
        ]
    finally:
        db.close()


def _claim_job_run(job_name: str, scheduled_for: datetime) -> bool:
    now = datetime.now(timezone.utc)
    db = SessionLocal()
    try:
        execution = (
            db.query(SchedulerJobExecution)
            .filter(
                SchedulerJobExecution.job_name == job_name,
                SchedulerJobExecution.scheduled_for == scheduled_for,
            )
            .with_for_update()
            .first()
        )
        if execution is not None:
            if execution.status == "SUCCEEDED":
                return False
            # The global PostgreSQL advisory lock is already held, so a RUNNING
            # row cannot belong to another live dispatcher. Retry the prior
            # attempt after a process crash or failed job.
            execution.status = "RUNNING"
            execution.started_at = now
            execution.finished_at = None
            execution.error_type = None
        else:
            db.add(
                SchedulerJobExecution(
                    job_name=job_name,
                    scheduled_for=scheduled_for,
                    status="RUNNING",
                    started_at=now,
                )
            )
        db.commit()
        return True
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _finish_job_run(job_name: str, scheduled_for: datetime, error: Exception | None) -> None:
    db = SessionLocal()
    try:
        execution = (
            db.query(SchedulerJobExecution)
            .filter(
                SchedulerJobExecution.job_name == job_name,
                SchedulerJobExecution.scheduled_for == scheduled_for,
            )
            .with_for_update()
            .first()
        )
        if execution is None:
            raise RuntimeError("Scheduler execution claim disappeared")
        execution.status = "FAILED" if error is not None else "SUCCEEDED"
        execution.finished_at = datetime.now(timezone.utc)
        execution.error_type = type(error).__name__[:100] if error is not None else None
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _prune_old_execution_rows(scheduled_for: datetime) -> None:
    db = SessionLocal()
    try:
        db.query(SchedulerJobExecution).filter(
            SchedulerJobExecution.scheduled_for < scheduled_for - _EXECUTION_LEDGER_RETENTION
        ).delete(synchronize_session=False)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _acquire_tick_lock():
    url = _scheduler_lock_url(settings.DATABASE_URL)
    engine = create_engine(
        url.render_as_string(hide_password=False),
        poolclass=NullPool,
        connect_args={"connect_timeout": 10},
    )
    connection = engine.connect()
    try:
        acquired = bool(
            connection.execute(
                text("SELECT pg_try_advisory_lock(:lock_key)"),
                {"lock_key": _SCHEDULER_TICK_LOCK_KEY},
            ).scalar()
        )
        connection.commit()
        return engine, connection, acquired
    except Exception:
        connection.close()
        engine.dispose()
        raise


def _release_tick_lock(engine, connection) -> None:
    try:
        connection.execute(
            text("SELECT pg_advisory_unlock(:lock_key)"),
            {"lock_key": _SCHEDULER_TICK_LOCK_KEY},
        )
        connection.commit()
    finally:
        connection.close()
        engine.dispose()


def run_cloud_scheduler_tick(scheduled_for: datetime) -> dict:
    """Run the jobs due at one Cloud Scheduler minute, with lock and replay safety."""
    if scheduled_for.tzinfo is None:
        raise ValueError("A timezone-aware Cloud Scheduler timestamp is required")
    scheduled_for = scheduled_for.astimezone(timezone.utc).replace(second=0, microsecond=0)
    scheduled_local = scheduled_for.astimezone(SCHEDULER_TIMEZONE)
    due_jobs = [
        (job_name, job_function, scheduled_for)
        for job_name, job_function in _due_jobs(scheduled_local)
    ]

    engine, connection, acquired = _acquire_tick_lock()
    if not acquired:
        connection.close()
        engine.dispose()
        raise SchedulerTickBusy("Another scheduler tick is active")

    completed: list[str] = []
    skipped: list[str] = []
    failed: list[str] = []
    try:
        # Keep only two days of per-slot replay state. This is internal
        # scheduler metadata created by this service, not recovered business data.
        if scheduled_local.weekday() == 0 and scheduled_local.hour == 3 and scheduled_local.minute == 0:
            _prune_old_execution_rows(scheduled_for)
        known_jobs = {name: definition[0] for name, definition in SCHEDULER_JOB_DEFINITIONS.items()}
        runs = {(name, slot): function for name, function, slot in due_jobs}
        for job_name, slot in _pending_job_runs(scheduled_for):
            job_function = known_jobs.get(job_name)
            if job_function is not None:
                runs[(job_name, slot)] = job_function

        for (job_name, slot), job_function in sorted(runs.items(), key=lambda item: (item[0][1], item[0][0])):
            if not _claim_job_run(job_name, slot):
                skipped.append(job_name)
                continue
            try:
                job_function(slot.astimezone(SCHEDULER_TIMEZONE))
            except Exception as exc:
                logger.exception("Scheduled job failed: %s", job_name)
                _finish_job_run(job_name, slot, exc)
                failed.append(job_name)
            else:
                _finish_job_run(job_name, slot, None)
                completed.append(job_name)
    finally:
        _release_tick_lock(engine, connection)

    if failed:
        raise SchedulerJobsFailed(failed)
    return {
        "status": "ok",
        "scheduled_for": scheduled_for.isoformat(),
        "completed": sorted(set(completed)),
        "completed_slots": len(completed),
        "skipped": sorted(set(skipped)),
        "failed": sorted(set(failed)),
    }
