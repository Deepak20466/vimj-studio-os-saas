import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from zoneinfo import ZoneInfo

from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.config import settings
from app.models.scheduler_job_execution import SchedulerJobExecution
from app.services import cloud_scheduler
from app.services import scheduler
from app.routers.cloud_scheduler import cloud_scheduler_tick
from fastapi import HTTPException


class CloudSchedulerTests(unittest.TestCase):
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
        self.assertNotIn("mark_overdue_fees", {name for name, _function in cloud_scheduler._due_jobs(slot.replace(minute=31))})

    def test_schedule_header_requires_timezone_and_normalizes_to_scheduled_minute(self):
        parsed = cloud_scheduler.parse_schedule_time("2026-10-10T03:30:00Z")
        self.assertEqual(parsed, datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc))
        parsed_with_seconds = cloud_scheduler.parse_schedule_time("2026-10-10T03:30:30.123Z")
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
        verify.assert_called_once()
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

    def test_route_rejects_unconfigured_or_wrong_cloud_scheduler_job(self):
        with patch.object(settings, "CLOUD_SCHEDULER_JOB_NAME", ""):
            with self.assertRaises(HTTPException) as missing_config:
                cloud_scheduler_tick(SimpleNamespace(headers={}))
        self.assertEqual(missing_config.exception.status_code, 503)

        headers = {"X-CloudScheduler-JobName": "projects/other/locations/region/jobs/other"}
        with (
            patch.object(settings, "CLOUD_SCHEDULER_JOB_NAME", "projects/vimj-academy/locations/asia-south1/jobs/vimj-minute-dispatch"),
            patch.object(settings, "CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
            patch("app.routers.cloud_scheduler.verify_cloud_scheduler_identity") as verify,
        ):
            with self.assertRaises(HTTPException) as wrong_job:
                cloud_scheduler_tick(SimpleNamespace(headers=headers))
        self.assertEqual(wrong_job.exception.status_code, 401)
        verify.assert_not_called()

    def test_route_verifies_oidc_before_dispatch(self):
        job_name = "projects/vimj-academy/locations/asia-south1/jobs/vimj-minute-dispatch"
        headers = {
            "X-CloudScheduler-JobName": job_name,
            "Authorization": "Bearer signed-token",
            "X-CloudScheduler-ScheduleTime": "2026-10-10T03:30:00Z",
        }
        with (
            patch.object(settings, "CLOUD_SCHEDULER_JOB_NAME", job_name),
            patch.object(settings, "CLOUD_SCHEDULER_SERVICE_ACCOUNT_EMAIL", "scheduler@vimj-academy.iam.gserviceaccount.com"),
            patch.object(settings, "CLOUD_SCHEDULER_OIDC_AUDIENCE", "https://vimj-api.run.app"),
            patch("app.routers.cloud_scheduler.verify_cloud_scheduler_identity") as verify,
            patch("app.routers.cloud_scheduler.run_cloud_scheduler_tick", return_value={"status": "ok"}) as dispatch,
        ):
            response = cloud_scheduler_tick(SimpleNamespace(headers=headers))
        verify.assert_called_once_with("Bearer signed-token")
        self.assertEqual(dispatch.call_args.args[0], datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc))
        self.assertEqual(response, {"status": "ok"})

    def test_replayed_slot_does_not_repeat_successful_job(self):
        job = MagicMock()
        trigger = CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE)
        instant = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        engine = create_engine("sqlite:///:memory:")
        SchedulerJobExecution.__table__.create(engine)
        session_factory = sessionmaker(bind=engine, expire_on_commit=False)
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (job, trigger)}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", session_factory),
            patch.object(cloud_scheduler, "_acquire_tick_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_tick_lock"),
        ):
            first = cloud_scheduler.run_cloud_scheduler_tick(instant)
            second = cloud_scheduler.run_cloud_scheduler_tick(instant)

        self.assertEqual(first["completed"], ["minute_job"])
        self.assertEqual(second["skipped"], ["minute_job"])
        job.assert_called_once()
        with session_factory() as db:
            self.assertEqual(db.query(SchedulerJobExecution).one().status, "SUCCEEDED")
        engine.dispose()

    def test_failed_slot_can_be_retried_without_repeating_completed_jobs(self):
        flaky_job = MagicMock(side_effect=[RuntimeError("temporary"), None])
        trigger = CronTrigger(minute="*", timezone=scheduler.SCHEDULER_TIMEZONE)
        instant = datetime(2026, 10, 10, 3, 30, tzinfo=timezone.utc)
        engine = create_engine("sqlite:///:memory:")
        SchedulerJobExecution.__table__.create(engine)
        session_factory = sessionmaker(bind=engine, expire_on_commit=False)
        with (
            patch.dict(scheduler.SCHEDULER_JOB_DEFINITIONS, {"minute_job": (flaky_job, trigger)}, clear=True),
            patch.object(cloud_scheduler, "SessionLocal", session_factory),
            patch.object(cloud_scheduler, "_acquire_tick_lock", return_value=(MagicMock(), MagicMock(), True)),
            patch.object(cloud_scheduler, "_release_tick_lock"),
        ):
            with self.assertRaises(cloud_scheduler.SchedulerJobsFailed):
                cloud_scheduler.run_cloud_scheduler_tick(instant)
            response = cloud_scheduler.run_cloud_scheduler_tick(instant)

        self.assertEqual(response["completed"], ["minute_job"])
        self.assertEqual(flaky_job.call_count, 2)
        with session_factory() as db:
            self.assertEqual(db.query(SchedulerJobExecution).one().status, "SUCCEEDED")
        engine.dispose()


if __name__ == "__main__":
    unittest.main()
