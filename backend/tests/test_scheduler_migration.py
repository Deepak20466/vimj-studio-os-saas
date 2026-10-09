import importlib.util
import os
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


MIGRATION_PATH = (
    Path(__file__).parents[1]
    / "alembic"
    / "versions"
    / "0021_cloud_scheduler_job_executions.py"
)
SPEC = importlib.util.spec_from_file_location("vimj_migration_0021", MIGRATION_PATH)
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)


class SchedulerMigrationTests(unittest.TestCase):
    def test_supabase_schema_change_requires_explicit_approval(self):
        bind = SimpleNamespace(engine=SimpleNamespace(url=SimpleNamespace(host="db.example.supabase.co")))
        with (
            patch.dict(os.environ, {"VIMJ_SCHEMA_CHANGE_APPROVED": ""}),
            patch.object(MIGRATION.op, "get_bind", return_value=bind),
            patch.object(MIGRATION.op, "create_table") as create_table,
        ):
            with self.assertRaisesRegex(RuntimeError, "requires VIMJ_SCHEMA_CHANGE_APPROVED"):
                MIGRATION.upgrade()
        create_table.assert_not_called()

    def test_downgrade_refuses_to_drop_scheduler_execution_state(self):
        with patch.object(MIGRATION.op, "drop_table") as drop_table:
            with self.assertRaisesRegex(RuntimeError, "Refusing to drop scheduler_job_executions"):
                MIGRATION.downgrade()
        drop_table.assert_not_called()


if __name__ == "__main__":
    unittest.main()
