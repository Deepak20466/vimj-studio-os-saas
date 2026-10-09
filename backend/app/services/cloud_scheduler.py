"""Authenticated Cloud Scheduler dispatch and durable Cloud Tasks job execution."""
import hashlib
import json
import logging
from datetime import datetime, timedelta, timezone

from google.api_core.exceptions import AlreadyExists
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.cloud import tasks_v2
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
_TASK_RETRY_GRACE = timedelta(minutes=35)
_STALE_TASK_AFTER = timedelta(minutes=45)
_TASK_DISPATCH_DEADLINE = timedelta(seconds=600)


class SchedulerTickBusy(RuntimeError):
    """A matching scheduler/job advisory lock is held by another request."""


class SchedulerJobsFailed(RuntimeError):
    def __init__(self, job_names: list[str]):
        self.job_names = job_names
        super().__init__(", ".join(job_names))


def verify_cloud_scheduler_identity(authorization: str | None, *, service_account: str | None = None) -> None:
    """Verify Google's OIDC token, exact configured service account, and audience."""
    expected_email = (service_account or settings.CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL).strip().lower()
    expected_audience = settings.CLOUD_SCHEDULER_OIDC_AUDIENCE.strip()
    if not expected_email or not expected_audience:
        raise PermissionError("Cloud Scheduler identity is not configured")

    if not authorization:
        raise PermissionError("Missing Google service authorization token")
    scheme, separator, token = authorization.partition(" ")
    if not separator or scheme.lower() != "bearer" or not token.strip():
        raise PermissionError("Invalid Google service authorization header")

    claims = id_token.verify_oauth2_token(
        token.strip(), GoogleAuthRequest(), audience=expected_audience
    )
    actual_email = str(claims.get("email", "")).strip().lower()
    if actual_email != expected_email or claims.get("email_verified") is not True:
        raise PermissionError("Google service identity is not authorized")


def parse_schedule_time(value: str | None) -> datetime:
    """Parse an RFC3339 timestamp and normalize it to its UTC minute slot."""
    if not value:
        raise ValueError("Missing scheduled-time header")
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("Invalid scheduled-time timestamp") from exc
    if parsed.tzinfo is None:
        raise ValueError("Scheduled time must include a timezone")
    return parsed.astimezone(timezone.utc).replace(second=0, microsecond=0)


def _due_jobs(scheduled_local: datetime):
    current_minute = scheduled_local.replace(second=0, microsecond=0)
    previous_instant = current_minute - timedelta(microseconds=1)
    for job_name, (job_function, trigger) in SCHEDULER_JOB_DEFINITIONS.items():
        fire_time = trigger.get_next_fire_time(previous_instant, current_minute)
        if fire_time == current_minute:
            yield job_name, job_function


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _pending_job_runs(current_slot: datetime) -> list[tuple[str, datetime]]:
    """Return failed or abandoned work that is eligible for a new queue attempt."""
    cutoff = current_slot - _EXECUTION_LEDGER_RETENTION
    retry_before = current_slot - _TASK_RETRY_GRACE
    stale_before = current_slot - _STALE_TASK_AFTER
    db = SessionLocal()
    try:
        rows = (
            db.query(SchedulerJobExecution)
            .filter(
                SchedulerJobExecution.status.in_(("FAILED", "QUEUED", "RUNNING")),
                SchedulerJobExecution.scheduled_for >= cutoff,
                SchedulerJobExecution.scheduled_for <= current_slot,
            )
            .order_by(SchedulerJobExecution.scheduled_for, SchedulerJobExecution.job_name)
            .all()
        )
        pending = []
        for row in rows:
            finished_at = _as_utc(row.finished_at) if row.finished_at else None
            started_at = _as_utc(row.started_at) if row.started_at else None
            enqueue_failed = (row.error_type or "").startswith("ENQUEUE:")
            if row.status == "FAILED" and (enqueue_failed or (finished_at and finished_at <= retry_before)):
                pending.append((row.job_name, _as_utc(row.scheduled_for)))
            elif row.status in {"QUEUED", "RUNNING"} and started_at and started_at <= stale_before:
                pending.append((row.job_name, _as_utc(row.scheduled_for)))
        return pending
    finally:
        db.close()


def _acquire_advisory_lock(lock_key: int):
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
                text("SELECT pg_try_advisory_lock(:lock_key)"), {"lock_key": lock_key}
            ).scalar()
        )
        connection.commit()
        return engine, connection, acquired
    except Exception:
        connection.close()
        engine.dispose()
        raise


def _release_advisory_lock(lock_key: int, engine, connection) -> None:
    try:
        connection.execute(
            text("SELECT pg_advisory_unlock(:lock_key)"), {"lock_key": lock_key}
        )
        connection.commit()
    finally:
        connection.close()
        engine.dispose()


def _acquire_tick_lock():
    return _acquire_advisory_lock(_SCHEDULER_TICK_LOCK_KEY)


def _job_lock_key(job_name: str) -> int:
    value = int.from_bytes(hashlib.sha256(f"vimj-scheduler-job:{job_name}".encode()).digest()[:8], "big")
    return value - (1 << 64) if value >= (1 << 63) else value


def _acquire_job_lock(job_name: str):
    return _acquire_advisory_lock(_job_lock_key(job_name))


def _cloud_tasks_task_id(job_name: str, scheduled_for: datetime, attempt: int) -> str:
    identity = f"{job_name}|{_as_utc(scheduled_for).isoformat()}|{attempt}"
    return "vimj-" + hashlib.sha256(identity.encode("utf-8")).hexdigest()[:40]


def _prepare_job_run(job_name: str, scheduled_for: datetime, now: datetime) -> int | None:
    """Create/update the durable queued slot and return its task generation."""
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
            execution = SchedulerJobExecution(
                job_name=job_name,
                scheduled_for=scheduled_for,
                status="QUEUED",
                attempt=1,
                started_at=now,
            )
            db.add(execution)
        elif execution.status == "SUCCEEDED":
            return None
        elif execution.status == "FAILED":
            finished_at = _as_utc(execution.finished_at) if execution.finished_at else None
            if not (execution.error_type or "").startswith("ENQUEUE:") and (
                finished_at is None or finished_at > now - _TASK_RETRY_GRACE
            ):
                return None
            execution.attempt += 1
            execution.status = "QUEUED"
            execution.started_at = now
            execution.finished_at = None
            execution.error_type = None
        elif execution.status in {"QUEUED", "RUNNING"}:
            started_at = _as_utc(execution.started_at) if execution.started_at else None
            if started_at is None or started_at > now - _STALE_TASK_AFTER:
                return None
            execution.attempt += 1
            execution.status = "QUEUED"
            execution.started_at = now
            execution.finished_at = None
            execution.error_type = None
        else:
            return None
        db.commit()
        return execution.attempt
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _mark_enqueue_failure(job_name: str, scheduled_for: datetime, attempt: int, error: Exception) -> None:
    db = SessionLocal()
    try:
        execution = (
            db.query(SchedulerJobExecution)
            .filter(
                SchedulerJobExecution.job_name == job_name,
                SchedulerJobExecution.scheduled_for == scheduled_for,
                SchedulerJobExecution.attempt == attempt,
            )
            .with_for_update()
            .first()
        )
        if execution is not None and execution.status == "QUEUED":
            execution.status = "FAILED"
            execution.finished_at = datetime.now(timezone.utc)
            execution.error_type = f"ENQUEUE:{type(error).__name__}"[:100]
            db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _create_job_task(client, job_name: str, scheduled_for: datetime, attempt: int) -> None:
    queue = settings.CLOUD_TASKS_QUEUE_NAME.strip()
    task_service_account = settings.CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL.strip()
    audience = settings.CLOUD_SCHEDULER_OIDC_AUDIENCE.strip().rstrip("/")
    if not queue or not task_service_account or not audience:
        raise RuntimeError("Cloud Tasks queue, identity, and audience must be configured")
    task_id = _cloud_tasks_task_id(job_name, scheduled_for, attempt)
    body = json.dumps(
        {
            "job_name": job_name,
            "scheduled_for": _as_utc(scheduled_for).isoformat(),
            "attempt": attempt,
        },
        separators=(",", ":"),
    ).encode("utf-8")
    task = tasks_v2.Task(
        name=f"{queue}/tasks/{task_id}",
        http_request=tasks_v2.HttpRequest(
            http_method=tasks_v2.HttpMethod.POST,
            url=f"{audience}/internal/scheduler/run",
            headers={"Content-Type": "application/json"},
            body=body,
            oidc_token=tasks_v2.OidcToken(
                service_account_email=task_service_account,
                audience=audience,
            ),
        ),
        dispatch_deadline=_TASK_DISPATCH_DEADLINE,
    )
    try:
        client.create_task(parent=queue, task=task)
    except AlreadyExists:
        # Cloud Scheduler retries and duplicate minute deliveries use the same
        # task generation. The task name makes creation idempotent.
        return


def enqueue_cloud_scheduler_tick(scheduled_for: datetime, task_client=None) -> dict:
    """Quickly enqueue every due job; task handlers execute under per-job locks."""
    if scheduled_for.tzinfo is None:
        raise ValueError("A timezone-aware Cloud Scheduler timestamp is required")
    scheduled_for = _as_utc(scheduled_for).replace(second=0, microsecond=0)
    scheduled_local = scheduled_for.astimezone(SCHEDULER_TIMEZONE)
    runs = {(name, scheduled_for) for name, _function in _due_jobs(scheduled_local)}
    for job_name, slot in _pending_job_runs(scheduled_for):
        runs.add((job_name, slot))

    engine, connection, acquired = _acquire_tick_lock()
    if not acquired:
        connection.close()
        engine.dispose()
        raise SchedulerTickBusy("Another scheduler dispatch is active")

    owns_client = task_client is None
    client = task_client
    enqueued: list[str] = []
    skipped: list[str] = []
    failed: list[str] = []
    try:
        if client is None:
            client = tasks_v2.CloudTasksClient()
        if scheduled_local.weekday() == 0 and scheduled_local.hour == 3 and scheduled_local.minute == 0:
            _prune_old_execution_rows(scheduled_for)
        known_jobs = set(SCHEDULER_JOB_DEFINITIONS)
        for job_name, slot in sorted(runs, key=lambda item: (item[1], item[0])):
            if job_name not in known_jobs:
                continue
            attempt = _prepare_job_run(job_name, slot, datetime.now(timezone.utc))
            if attempt is None:
                skipped.append(job_name)
                continue
            try:
                _create_job_task(client, job_name, slot, attempt)
                enqueued.append(job_name)
            except Exception as exc:
                _mark_enqueue_failure(job_name, slot, attempt, exc)
                logger.error("Cloud Task enqueue failed for %s (%s)", job_name, type(exc).__name__)
                failed.append(job_name)
    finally:
        if owns_client and client is not None:
            client.close()
        _release_advisory_lock(_SCHEDULER_TICK_LOCK_KEY, engine, connection)

    if failed:
        raise SchedulerJobsFailed(failed)
    return {
        "status": "accepted",
        "scheduled_for": scheduled_for.isoformat(),
        "enqueued": sorted(set(enqueued)),
        "enqueued_slots": len(enqueued),
        "skipped": sorted(set(skipped)),
    }


def _claim_job_run(job_name: str, scheduled_for: datetime, attempt: int) -> bool:
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
        if execution is None or execution.attempt != attempt or execution.status == "SUCCEEDED":
            return False
        execution.status = "RUNNING"
        execution.started_at = now
        execution.finished_at = None
        execution.error_type = None
        db.commit()
        return True
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _finish_job_run(job_name: str, scheduled_for: datetime, attempt: int, error: Exception | None) -> None:
    db = SessionLocal()
    try:
        execution = (
            db.query(SchedulerJobExecution)
            .filter(
                SchedulerJobExecution.job_name == job_name,
                SchedulerJobExecution.scheduled_for == scheduled_for,
                SchedulerJobExecution.attempt == attempt,
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


def run_cloud_scheduler_job(job_name: str, scheduled_for: datetime, attempt: int) -> dict:
    """Execute one queued job slot with durable replay checks and a per-job lock."""
    if job_name not in SCHEDULER_JOB_DEFINITIONS:
        raise ValueError("Unknown scheduled job")
    if scheduled_for.tzinfo is None:
        raise ValueError("A timezone-aware scheduled timestamp is required")
    scheduled_for = _as_utc(scheduled_for).replace(second=0, microsecond=0)
    if attempt < 1 or attempt > 100000:
        raise ValueError("Invalid Cloud Tasks attempt generation")

    engine, connection, acquired = _acquire_job_lock(job_name)
    if not acquired:
        connection.close()
        engine.dispose()
        raise SchedulerTickBusy("Another execution of this scheduled job is active")

    try:
        if not _claim_job_run(job_name, scheduled_for, attempt):
            return {"status": "skipped", "job_name": job_name}
        job_function = SCHEDULER_JOB_DEFINITIONS[job_name][0]
        try:
            job_function(scheduled_for.astimezone(SCHEDULER_TIMEZONE))
        except Exception as exc:
            logger.exception("Scheduled job failed: %s", job_name)
            _finish_job_run(job_name, scheduled_for, attempt, exc)
            raise SchedulerJobsFailed([job_name]) from None
        _finish_job_run(job_name, scheduled_for, attempt, None)
        return {"status": "ok", "job_name": job_name, "scheduled_for": scheduled_for.isoformat()}
    finally:
        _release_advisory_lock(_job_lock_key(job_name), engine, connection)


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
