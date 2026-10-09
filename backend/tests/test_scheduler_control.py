import asyncio
import unittest
from unittest.mock import MagicMock, patch

from app.config import Settings
from app.main import lifespan
from app.services import scheduler as scheduler_service


class SchedulerControlTests(unittest.TestCase):
    def test_scheduler_is_enabled_by_default(self):
        self.assertTrue(Settings(_env_file=None).SCHEDULER_ENABLED)

    def test_production_lifespan_can_disable_scheduler(self):
        async def exercise_lifespan():
            with (
                patch("app.main.settings.ENV", "production"),
                patch("app.main.settings.SCHEDULER_ENABLED", False),
                patch("app.main.start_scheduler") as start_scheduler,
                patch("app.main.shutdown_scheduler") as shutdown_scheduler,
            ):
                async with lifespan(MagicMock()):
                    pass

                start_scheduler.assert_not_called()
                shutdown_scheduler.assert_called_once_with()

        asyncio.run(exercise_lifespan())

    def test_production_lifespan_never_starts_in_process_scheduler(self):
        async def exercise_lifespan():
            with (
                patch("app.main.settings.ENV", "production"),
                patch("app.main.settings.SCHEDULER_ENABLED", True),
                patch("app.main.start_scheduler") as start_scheduler,
                patch("app.main.shutdown_scheduler") as shutdown_scheduler,
            ):
                async with lifespan(MagicMock()):
                    pass

                start_scheduler.assert_not_called()
                shutdown_scheduler.assert_called_once_with()

        asyncio.run(exercise_lifespan())

    def test_supabase_transaction_pooler_uses_session_pooler_for_owner_lock(self):
        url = scheduler_service._scheduler_lock_url(
            "postgresql+psycopg2://vimj:secret@aws-0-region.pooler.supabase.com:6543/postgres"
        )
        self.assertEqual(url.port, 5432)
        self.assertEqual(url.username, "vimj")
        self.assertEqual(url.database, "postgres")

    def test_second_scheduler_owner_does_not_start_jobs(self):
        with (
            patch.object(scheduler_service, "_acquire_scheduler_owner_lock", return_value=False),
            patch.object(scheduler_service.scheduler, "add_job") as add_job,
            patch.object(scheduler_service.scheduler, "start") as start,
        ):
            scheduler_service.start_scheduler()

        add_job.assert_not_called()
        start.assert_not_called()


if __name__ == "__main__":
    unittest.main()
