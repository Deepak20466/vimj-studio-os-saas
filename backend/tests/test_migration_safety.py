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
    / "0013_remove_leave_salary_swap_chat_compliance.py"
)
SPEC = importlib.util.spec_from_file_location("vimj_migration_0013", MIGRATION_PATH)
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)


class MigrationSafetyTests(unittest.TestCase):
    def assert_migration_blocked(self, *, environment, host):
        bind = SimpleNamespace(engine=SimpleNamespace(url=SimpleNamespace(host=host)))
        with (
            patch.dict(os.environ, {"ENV": environment}),
            patch.object(MIGRATION.op, "get_bind", return_value=bind),
            patch.object(MIGRATION.op, "drop_table") as drop_table,
        ):
            with self.assertRaisesRegex(RuntimeError, "Blocked destructive migration"):
                MIGRATION.upgrade()
        drop_table.assert_not_called()

    def test_destructive_migration_is_blocked_in_production_even_on_custom_hosts(self):
        self.assert_migration_blocked(environment="production", host="postgres.internal")

    def test_destructive_migration_is_blocked_on_supabase_poolers(self):
        self.assert_migration_blocked(
            environment="staging",
            host="aws-0-region.pooler.supabase.com",
        )


if __name__ == "__main__":
    unittest.main()
