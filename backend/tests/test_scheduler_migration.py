import importlib.util
import ast
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
    def test_0021_only_creates_scheduler_metadata_and_never_mutates_existing_tables(self):
        source = MIGRATION_PATH.read_text(encoding="utf-8")
        tree = ast.parse(source)
        migration_calls = {
            node.func.attr
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "op"
        }
        self.assertEqual(MIGRATION.down_revision, "0020")
        self.assertIn("create_table", migration_calls)
        self.assertIn("create_index", migration_calls)
        self.assertFalse(migration_calls & {"add_column", "alter_column", "drop_table", "drop_column"})
        self.assertIn('sa.Column("attempt", sa.Integer()', source)

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
