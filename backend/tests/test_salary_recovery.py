import unittest
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.models.salary import CoachSalary
from app.models.user import User, UserRole
from app.routers import coaches, salary
from app.security import get_current_user


class SalaryRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.session_factory = sessionmaker(bind=self.engine)
        with self.session_factory() as db:
            self.admin = User(
                id=1,
                name="Admin",
                email="admin@example.com",
                password_hash="unused",
                role=UserRole.ADMIN,
            )
            self.coach = User(
                id=2,
                name="Coach",
                email="coach@example.com",
                password_hash="unused",
                role=UserRole.COACH,
            )
            db.add_all([self.admin, self.coach])
            db.flush()
            db.add(
                CoachSalary(
                    id=1,
                    coach_id=2,
                    month=10,
                    year=2026,
                    amount=Decimal("25000.00"),
                    created_at=datetime(2026, 10, 1),
                )
            )
            db.commit()

        self.current_user = SimpleNamespace(id=1, role=UserRole.ADMIN)
        self.app = FastAPI()
        self.app.include_router(coaches.router)
        self.app.include_router(salary.router)

        def get_test_db():
            db = self.session_factory()
            try:
                yield db
            finally:
                db.close()

        self.app.dependency_overrides[get_db] = get_test_db
        self.app.dependency_overrides[get_current_user] = lambda: self.current_user
        self.client = TestClient(self.app)

    def tearDown(self):
        self.client.close()
        self.engine.dispose()

    def test_admin_can_list_salary_records(self):
        response = self.client.get("/salary")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()[0]["coach_name"], "Coach")
        self.assertEqual(response.json()[0]["amount"], "25000.00")

    def test_coach_can_read_only_own_history(self):
        self.current_user = SimpleNamespace(id=2, role=UserRole.COACH)
        own = self.client.get("/coaches/2/salary")
        other = self.client.get("/coaches/3/salary")
        admin_list = self.client.get("/salary")
        self.assertEqual(own.status_code, 200, own.text)
        self.assertEqual(own.json()[0]["coach_id"], 2)
        self.assertEqual(other.status_code, 403)
        self.assertEqual(admin_list.status_code, 403)

    def test_migration_is_additive_and_refuses_destructive_downgrade(self):
        migration = Path(__file__).parents[1] / "alembic" / "versions" / "0020_restore_coach_salary.py"
        source = migration.read_text(encoding="utf-8-sig")
        self.assertNotIn("op.drop_table", source)
        self.assertIn('"0020"', source)
        self.assertIn('"0019"', source)
        self.assertIn("may contain payroll history", source)


if __name__ == "__main__":
    unittest.main()
