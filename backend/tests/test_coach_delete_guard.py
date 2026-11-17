"""Regression tests for DELETE /coaches/{id} and the records that cascade with a coach.

Approved expected behaviour (owner decision): a coach with associated class sessions or student
attendance must not be permanently deleted. The endpoint returns 409 Conflict with a message telling
the administrator to deactivate the coach instead, and every session, attendance row and other
historical record is preserved. A coach with no associated records may still be deleted.

SQLite enforces foreign keys only when PRAGMA foreign_keys=ON, so the test engine turns it on to mirror
the ON DELETE CASCADE / SET NULL actions that the production PostgreSQL schema uses.
"""

import datetime
import unittest
from decimal import Decimal
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401  - registers every table so foreign keys resolve
from app.database import Base, get_db
from app.models.activity import Activity
from app.models.attendance import AttendanceStatus, StudentAttendance
from app.models.class_session import ClassSession
from app.models.salary import CoachSalary
from app.models.user import User, UserRole
from app.routers import coaches
from app.security import require_admin


class CoachDeleteGuardTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )

        @event.listens_for(self.engine, "connect")
        def _enable_foreign_keys(dbapi_connection, _record):
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

        Base.metadata.create_all(self.engine)
        self.session_factory = sessionmaker(bind=self.engine)
        with self.session_factory() as db:
            admin = User(name="Admin", email="admin@example.com", role=UserRole.ADMIN, password_hash="x")
            coach = User(name="Coach", email="coach@example.com", role=UserRole.COACH, password_hash="x")
            student = User(name="Student", email="student@example.com", role=UserRole.STUDENT, password_hash="x")
            activity = Activity(name="Yoga", capacity=10, monthly_fee=Decimal("1000"))
            db.add_all([admin, coach, student, activity])
            db.commit()
            self.admin_id = admin.id
            self.coach_id = coach.id
            self.student_id = student.id
            self.activity_id = activity.id

        self.app = FastAPI()
        self.app.include_router(coaches.router)

        def get_test_db():
            db = self.session_factory()
            try:
                yield db
            finally:
                db.close()

        self.app.dependency_overrides[get_db] = get_test_db
        self.app.dependency_overrides[require_admin] = lambda: SimpleNamespace(
            id=self.admin_id, role=UserRole.ADMIN, name="Admin"
        )

    def tearDown(self):
        self.engine.dispose()

    def _add_session_with_attendance(self):
        with self.session_factory() as db:
            session_row = ClassSession(
                activity_id=self.activity_id,
                coach_id=self.coach_id,
                date=datetime.date(2026, 10, 5),
                start_time=datetime.time(9, 0),
                end_time=datetime.time(10, 0),
            )
            db.add(session_row)
            db.flush()
            db.add(
                StudentAttendance(
                    student_id=self.student_id,
                    class_id=session_row.id,
                    status=AttendanceStatus.PRESENT,
                    coach_id=self.coach_id,
                )
            )
            db.commit()
            return session_row.id

    def _count(self, model):
        with self.session_factory() as db:
            return db.query(model).count()

    def _coach_exists(self):
        with self.session_factory() as db:
            return db.query(User).filter(User.id == self.coach_id).first() is not None

    def test_coach_with_sessions_and_attendance_cannot_be_deleted(self):
        self._add_session_with_attendance()
        with TestClient(self.app) as client:
            response = client.delete(f"/coaches/{self.coach_id}")

        self.assertEqual(response.status_code, 409, response.text)
        self.assertIn("deactivate", response.json()["detail"].lower())
        self.assertTrue(self._coach_exists())
        self.assertEqual(self._count(ClassSession), 1)
        self.assertEqual(self._count(StudentAttendance), 1)

    def test_coach_with_sessions_only_cannot_be_deleted(self):
        with self.session_factory() as db:
            db.add(
                ClassSession(
                    activity_id=self.activity_id,
                    coach_id=self.coach_id,
                    date=datetime.date(2026, 10, 6),
                    start_time=datetime.time(9, 0),
                    end_time=datetime.time(10, 0),
                )
            )
            db.commit()
        with TestClient(self.app) as client:
            response = client.delete(f"/coaches/{self.coach_id}")

        self.assertEqual(response.status_code, 409, response.text)
        self.assertTrue(self._coach_exists())
        self.assertEqual(self._count(ClassSession), 1)

    def test_coach_without_associated_records_can_still_be_deleted(self):
        with TestClient(self.app) as client:
            response = client.delete(f"/coaches/{self.coach_id}")

        self.assertEqual(response.status_code, 204, response.text)
        self.assertFalse(self._coach_exists())

    def test_characterization_salary_rows_are_removed_with_a_coach_without_sessions(self):
        """Characterization only (outside the approved scope). Records salary-ledger cascade
        behaviour so the owner can decide whether salary, fee receipts and reminder drafts should
        also block deletion. This test passes on the current code by design and should be
        changed only if that scope decision is made."""
        with self.session_factory() as db:
            db.add(CoachSalary(coach_id=self.coach_id, month=10, year=2026, amount=Decimal("500")))
            db.commit()
        with TestClient(self.app) as client:
            response = client.delete(f"/coaches/{self.coach_id}")

        self.assertEqual(response.status_code, 204, response.text)
        self.assertEqual(self._count(CoachSalary), 0)


if __name__ == "__main__":
    unittest.main()
