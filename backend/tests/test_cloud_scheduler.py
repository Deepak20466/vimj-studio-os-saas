import asyncio
import json
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from zoneinfo import ZoneInfo

from apscheduler.triggers.cron import CronTrigger
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.config import settings
from app.models.scheduler_job_execution import SchedulerJobExecution
from app.services import cloud_scheduler
from app.services import scheduler
from app.routers.cloud_scheduler import cloud_scheduler_run, cloud_scheduler_tick


class CloudSchedulerTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite:///:memory:")
        SchedulerJobExecution.__table__.create(self.engine)
        self.session_factory = sessionmaker(bind=self.engine, expire_on_commit=False)

    def tearDown(self):
        self.engine.dispose()

    def test_all_eleven_jobs_have_individual_timezone_aware_schedules(self):
        self.assertEqual(len(scheduler.SCHEDULER_JOB_DEFINITIONS), 11)
        for _function, trigger in scheduler.SCHEDULER_JOB_DEFINITIONS.values():
            self.assertEqual(str(trigger.timezone), "Asia/Kolkata")

    def test_minute_and_monthly_schedules_match_india_local_time(self):
        slot = datetime(2026, 10, 10, 9, 0, tzinfo=ZoneInfo("Asia/Kolkata"))
        due = {name for name, _function in cloud_scheduler._due_jobs(slot)}
        self.assertEqual(
            due,
            {
                "monthly_fee_reminders",
                "coach_attendance_reminders",
                "pre_session_attendance_reminder",
                "coach_before_class_reminder",
                "coach_entry_missing_alert",
                "coach_exit_missing_alert",
                "missed_attendance_admin_alert",
            },
        )
        salary_slot = datetime(2026, 10, 10, 9, 5, tzinfo=ZoneInfo("Asia/Kolkata"))
        self.assertIn(
            "monthly_salary_notifications",
            {name for name, _function in cloud_scheduler._due_jobs(salary_slot)},
        )

    def test_daily_jobs_use_india_local_time(self):
        slot = datetime(2026, 10, 11, 0, 30, tzinfo=ZoneInfo("Asia/Kolkata"))
        due = {name for name, _function in cloud_scheduler._due_jobs(slot)}
        self.assertIn("mark_overdue_fees", due)
        self.assertNotIn(
            "mark_overdue_fees",
            {name for name, _function in cloud_scheduler._due_jobs(slot.replace(minute=31))},
        )

    def test_schedule_header_requires_timezone_and_normalizes_to_scheduled_minute(self):
        parsed = cloud_scheduler.parse_schedule_time("2026-10-10T03:30:00Z")
        self.assertEqual(parsed, datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc))
        parsed_with_seconds = cloud_scheduler.parse_schedule_time("2026-10-10T09:00:30.123+05:30")
        self.assertEqual(parsed_with_seconds, parsed)
        with self.assertRaises(ValueError):
            cloud_scheduler.parse_schedule_time("2026-10-10T03:30:00")

    def test_oidc_verification_checks_exact_service_account_and_audience(self):
        with (
            patch.object(settings, "CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
            patch.object(
                cloud_scheduler.id_token,
                "verify_oauth2_token",
                return_value={
                    "email": "scheduler@vimj-academy.iam.gserviceaccount.com",
                    "email_verified": True,
                },
            ) as verify,
        ):
            cloud_scheduler.verify_cloud_scheduler_identity("Bearer signed-token")
            cloud_scheduler.verify_cloud_scheduler_identity(
                "Bearer task-token", service_account="scheduler@vimj-academy.iam.gserviceaccount.com"
            )
        self.assertEqual(verify.call_count, 2)
        self.assertEqual(verify.call_args.kwargs["audience"], "https://vimj-api.run.app")

    def test_oidc_rejects_missing_or_unexpected_identity(self):
        with (
            patch.object(settings, "CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
        ):
            with self.assertRaises(PermissionError):
                cloud_scheduler.verify_cloud_scheduler_identity(None)
            with patch.object(
                cloud_scheduler.id_token,
                "verify_oauth2_token",
                return_value={"email": "other@example.com", "email_verified": True},
            ):
                with self.assertRaises(PermissionError):
                    cloud_scheduler.verify_cloud_scheduler_identity("Bearer signed-token")

    def test_scheduler_route_checks_job_header_and_uses_oidc_before_enqueue(self):
        job_name = "projects/vimj-academy/locations/asia-south1/jobs/vimj-minute-dispatch"
        headers = {
            "X-CloudScheduler-JobName": job_name.rsplit("/", 1)[-1],
            "Authorization": "Bearer signed-token",
            "X-CloudScheduler-ScheduleTime": "2026-10-10T03:30:00Z",
        }
        with (
            patch.object(settings, "CLOUD_SCHEDULER_JOB_NAME", job_name),
            patch.object(settings, "CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
            patch("app.routers.cloud_scheduler._verify_google_identity") as verify,
            patch("app.routers.cloud_scheduler.enqueue_cloud_scheduler_tick", return_value={"status": "accepted"}) as enqueue,
        ):
            response = cloud_scheduler_tick(SimpleNamespace(headers=headers))
        verify.assert_called_once_with("Bearer signed-token", "scheduler@vimj-academy.iam.gserviceaccount.com")
        self.assertEqual(enqueue.call_args.args[0], datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc))
        self.assertEqual(response, {"status": "accepted"})

    def test_scheduler_route_rejects_wrong_job_before_oidc_verification(self):
        with (
            patch.object(settings, "CLOUD_SCHEDULER_JOB_NAME", "projects/vimj-academy/locations/asia-south1/jobs/expected"),
            patch.object(settings, "CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
            patch("app.routers.cloud_scheduler._verify_google_identity") as verify,
        ):
            with self.assertRaises(HTTPException) as rejected:
                cloud_scheduler_tick(SimpleNamespace(headers={"X-CloudScheduler-JobName": "wrong"}))
        self.assertEqual(rejected.exception.status_code, 401)
        verify.assert_not_called()

    def test_task_route_checks_queue_oidc_and_task_name_before_running(self):
        slot = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        job_name = "coach_attendance_reminders"
        attempt = 2
        task_name = cloud_scheduler._cloud_tasks_task_id(job_name, slot, attempt)
        body = json.dumps({"job_name": job_name, "scheduled_for": slot.isoformat(), "attempt": attempt}).encode()

        async def read_body():
            return body

        request = SimpleNamespace(
            headers={
                "Authorization": "Bearer task-token",
                "X-CloudTasks-QueueName": "vimj-scheduled-jobs",
                "X-CloudTasks-TaskName": task_name,
            },
            body=read_body,
        )
        with (
            patch.object(settings, "CLOUD_TASKS_QUEUE_NAME", "projects/vimj-academy/locations/asia-south1/queues/vimj-scheduled-jobs"),
            patch.object(settings, "CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
            patch("app.routers.cloud_scheduler._verify_google_identity") as verify,
            patch("app.routers.cloud_scheduler.run_cloud_scheduler_job", return_value={"status": "ok"}) as run,
        ):
            response = asyncio.run(cloud_scheduler_run(request))
        verify.assert_called_once_with("Bearer task-token", "scheduler@vimj-academy.iam.gserviceaccount.com")
        run.assert_called_once_with(job_name, slot, attempt)
        self.assertEqual(response, {"status": "ok"})

    def test_task_route_rejects_a_forged_task_header(self):
        body = json.dumps({"job_name": "coach_attendance_reminders", "scheduled_for": "2026-10-10T03:30:00+00:00", "attempt": 1}).encode()

        async def read_body():
            return body

        request = SimpleNamespace(
            headers={
                "Authorization": "Bearer task-token",
                "X-CloudTasks-QueueName": "vimj-scheduled-jobs",
                "X-CloudTasks-TaskName": "forged",
            },
            body=read_body,
        )
        with (
            patch.object(settings, "CLOUD_TASKS_QUEUE_NAME", "projects/vimj-academy/locations/asia-south1/queues/vimj-scheduled-jobs"),
            patch.object(settings, "CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
            patch("app.routers.cloud_scheduler._verify_google_identity"),
            patch("app.routers.cloud_scheduler.run_cloud_scheduler_job") as run,
        ):
            with self.assertRaises(HTTPException) as rejected:
                asyncio.run(cloud_scheduler_run(request))
        self.assertEqual(rejected.exception.status_code, 401)
        run.assert_not_called()

    def test_dispatch_creates_deterministic_tasks_and_skips_duplicate_slot(self):
        job = MagicMock()
        trigger = CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE)
        instant = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        task_client = MagicMock()
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (job, trigger)}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", self.session_factory),
            patch.object(cloud_scheduler, "_acquire_tick_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_advisory_lock"),
            patch.object(settings, "CLOUD_TASKS_QUEUE_NAME", "projects/vimj-academy/locations/asia-south1/queues/vimj-scheduled-jobs"),
            patch.object(settings, "CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL", "tasks@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
        ):
            first = cloud_scheduler.enqueue_cloud_scheduler_tick(instant, task_client)
            second = cloud_scheduler.enqueue_cloud_scheduler_tick(instant, task_client)

        self.assertEqual(first["enqueued"], ["minute_job"])
        self.assertEqual(second["skipped"], ["minute_job"])
        self.assertEqual(task_client.create_task.call_count, 1)
        task = task_client.create_task.call_args.kwargs["task"]
        self.assertEqual(task.http_request.url, "https://vimj-api.run.app/internal/scheduler/run")
        self.assertEqual(task.http_request.oidc_token.service_account_email, "tasks@vimj-academy.iam.gserviceaccount.com")
        self.assertEqual(task.name.rsplit("/", 1)[1], cloud_scheduler._cloud_tasks_task_id("minute_job", instant, 1))
        with self.session_factory() as db:
            row = db.query(SchedulerJobExecution).one()
            self.assertEqual((row.status, row.attempt), ("QUEUED", 1))

    def test_dispatch_closes_owned_cloud_tasks_transport_and_releases_lock(self):
        job = MagicMock()
        instant = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        client = SimpleNamespace(transport=MagicMock())
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (job, CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE))}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", self.session_factory),
            patch.object(cloud_scheduler, "_due_jobs", return_value=[("minute_job", job)]),
            patch.object(cloud_scheduler, "_pending_job_runs", return_value=[]),
            patch.object(cloud_scheduler, "_acquire_tick_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_advisory_lock") as release_lock,
            patch.object(cloud_scheduler.tasks_v2, "CloudTasksClient", return_value=client),
            patch.object(cloud_scheduler, "_create_job_task"),
        ):
            result = cloud_scheduler.enqueue_cloud_scheduler_tick(instant)

        self.assertEqual(result["enqueued"], ["minute_job"])
        client.transport.close.assert_called_once_with()
        release_lock.assert_called_once()

    def test_failed_task_creation_is_retried_with_a_new_generation(self):
        job = MagicMock()
        trigger = CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE)
        instant = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        task_client = MagicMock()
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (job, trigger)}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", self.session_factory),
            patch.object(cloud_scheduler, "_acquire_tick_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_advisory_lock"),
            patch.object(cloud_scheduler, "_create_job_task", side_effect=[RuntimeError("unavailable"), None]) as create_task,
        ):
            with self.assertRaises(cloud_scheduler.SchedulerJobsFailed):
                cloud_scheduler.enqueue_cloud_scheduler_tick(instant, task_client)
            response = cloud_scheduler.enqueue_cloud_scheduler_tick(instant, task_client)

        self.assertEqual(response["enqueued"], ["minute_job"])
        self.assertEqual(create_task.call_args.args[3], 2)
        with self.session_factory() as db:
            row = db.query(SchedulerJobExecution).one()
            self.assertEqual((row.status, row.attempt), ("QUEUED", 2))

    def test_job_success_is_durable_and_replay_is_skipped(self):
        job = MagicMock()
        slot = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        with self.session_factory() as db:
            db.add(SchedulerJobExecution(job_name="minute_job", scheduled_for=slot, status="QUEUED", attempt=1))
            db.commit()
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (job, CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE))}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", self.session_factory),
            patch.object(cloud_scheduler, "_acquire_job_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_advisory_lock"),
        ):
            first = cloud_scheduler.run_cloud_scheduler_job("minute_job", slot, 1)
            replay = cloud_scheduler.run_cloud_scheduler_job("minute_job", slot, 1)
        self.assertEqual(first["status"], "ok")
        self.assertEqual(replay["status"], "skipped")
        job.assert_called_once_with(slot.astimezone(scheduler.SCHEDULER_TIMEZONE))
        with self.session_factory() as db:
            self.assertEqual(db.query(SchedulerJobExecution).one().status, "SUCCEEDED")

    def test_failed_job_retries_same_generation_and_completes(self):
        job = MagicMock(side_effect=[RuntimeError("temporary"), None])
        slot = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        with self.session_factory() as db:
            db.add(SchedulerJobExecution(job_name="minute_job", scheduled_for=slot, status="QUEUED", attempt=1))
            db.commit()
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (job, CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE))}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", self.session_factory),
            patch.object(cloud_scheduler, "_acquire_job_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_advisory_lock"),
        ):
            with self.assertRaises(cloud_scheduler.SchedulerJobsFailed):
                cloud_scheduler.run_cloud_scheduler_job("minute_job", slot, 1)
            response = cloud_scheduler.run_cloud_scheduler_job("minute_job", slot, 1)
        self.assertEqual(response["status"], "ok")
        self.assertEqual(job.call_count, 2)
        with self.session_factory() as db:
            row = db.query(SchedulerJobExecution).one()
            self.assertEqual((row.status, row.attempt), ("SUCCEEDED", 1))

    def test_old_task_generation_cannot_run_after_retry_is_queued(self):
        job = MagicMock()
        slot = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        with self.session_factory() as db:
            db.add(SchedulerJobExecution(job_name="minute_job", scheduled_for=slot, status="QUEUED", attempt=2))
            db.commit()
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (job, CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE))}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", self.session_factory),
            patch.object(cloud_scheduler, "_acquire_job_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_advisory_lock"),
        ):
            response = cloud_scheduler.run_cloud_scheduler_job("minute_job", slot, 1)
        self.assertEqual(response["status"], "skipped")
        job.assert_not_called()


if __name__ == "__main__":
    unittest.main()
