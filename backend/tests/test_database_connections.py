import unittest
from unittest.mock import MagicMock, patch

from sqlalchemy.pool import NullPool, QueuePool

from app import database


class DatabaseConnectionTests(unittest.TestCase):
    def test_transaction_pooler_uses_null_pool(self):
        engine = database.create_database_engine(
            "postgresql+psycopg2://vimj:secret@aws-0-region.pooler.supabase.com:6543/postgres"
        )
        try:
            self.assertIsInstance(engine.pool, NullPool)
        finally:
            engine.dispose()

    def test_other_postgres_connections_have_a_bounded_pool(self):
        engine = database.create_database_engine(
            "postgresql+psycopg2://vimj:secret@db.example.test:5432/postgres"
        )
        try:
            self.assertIsInstance(engine.pool, QueuePool)
            self.assertEqual(engine.pool.size(), 2)
            self.assertEqual(engine.pool._max_overflow, 0)
        finally:
            engine.dispose()

    def test_legacy_postgres_scheme_is_normalized_for_psycopg2(self):
        engine = database.create_database_engine(
            "postgres://vimj:secret@aws-0-region.pooler.supabase.com:6543/postgres"
        )
        try:
            self.assertEqual(engine.url.drivername, "postgresql+psycopg2")
            self.assertIsInstance(engine.pool, NullPool)
        finally:
            engine.dispose()

    def test_supabase_shared_session_url_is_routed_to_transaction_pooler(self):
        engine = database.create_database_engine(
            "postgres://vimj:secret@aws-0-ap-south-1.pooler.supabase.com:5432/postgres?sslmode=require"
        )
        try:
            self.assertEqual(engine.url.port, 6543)
            self.assertEqual(engine.url.query["sslmode"], "require")
            self.assertIsInstance(engine.pool, NullPool)
        finally:
            engine.dispose()

    def test_request_session_is_closed_when_dependency_finishes(self):
        session = MagicMock()
        with patch.object(database, "SessionLocal", return_value=session):
            dependency = database.get_db()
            self.assertIs(next(dependency), session)
            dependency.close()

        session.close.assert_called_once_with()

    def test_request_session_is_closed_when_dependency_raises(self):
        session = MagicMock()
        with patch.object(database, "SessionLocal", return_value=session):
            dependency = database.get_db()
            next(dependency)
            with self.assertRaisesRegex(RuntimeError, "request failed"):
                dependency.throw(RuntimeError("request failed"))

        session.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
