import unittest
from datetime import date, time, timedelta
from decimal import Decimal

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.models import (
    Activity,
    AttendanceStatus,
    Batch,
    ClassSession,
    FeeStatus,
    SessionPeriod,
    StudentAttendance,
    StudentEnrollment,
    StudentFee,
    User,
    UserRole,
)
from app.routers import fees, insights
from app.security import get_current_user


class InsightsTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.session_factory = sessionmaker(bind=self.engine)
        self.db = self.session_factory()
        self.admin = User(name="Admin", email="admin@example.com", role=UserRole.ADMIN, password_hash="unused")
        self.coach = User(name="Coach", email="coach@example.com", role=UserRole.COACH, password_hash="unused")
        self.activity = Activity(name="Yoga", monthly_fee=Decimal("1000"))
        self.db.add_all([self.admin, self.coach, self.activity])
        self.db.flush()

        self.batch = Batch(
            activity_id=self.activity.id,
            coach_id=self.coach.id,
            location="Studio",
            session_period=SessionPeriod.MORNING,
            start_time=time(9),
            end_time=time(10),
            days_of_week="MON",
        )
        self.db.add(self.batch)
        self.db.flush()

        self.students = []
        for index in range(11):
            student = User(
                name=f"Student {index}",
                email=f"student{index}@example.com",
                role=UserRole.STUDENT,
                password_hash="unused",
            )
            self.students.append(student)
            self.db.add(student)
        self.db.flush()
        for student in self.students[:10]:
            self.db.add(StudentEnrollment(student_id=student.id, activity_id=self.activity.id))

        today = date.today()
        for week_index in range(6):
            session_date = today - timedelta(days=7 * (5 - week_index))
            class_session = ClassSession(
                activity_id=self.activity.id,
                coach_id=self.coach.id,
                batch_id=self.batch.id,
                date=session_date,
                start_time=time(9),
                end_time=time(10),
            )
            self.db.add(class_session)
            self.db.flush()
            present_count = 10 if week_index < 3 else 6
            for student_index, student in enumerate(self.students[:10]):
                self.db.add(
                    StudentAttendance(
                        student_id=student.id,
                        class_id=class_session.id,
                        coach_id=self.coach.id,
                        status=AttendanceStatus.PRESENT if student_index < present_count else AttendanceStatus.ABSENT,
                    )
                )

        defaulter = self.students[10]
        self.defaulter_fee = StudentFee(
            student_id=defaulter.id,
            month=today.month,
            year=today.year,
            amount=Decimal("250"),
            product_amount=Decimal("0"),
            balance_amount=Decimal("250"),
            status=FeeStatus.OVERDUE,
            due_date=today - timedelta(days=8),
        )
        self.db.add(self.defaulter_fee)

        for month, year in self._last_months(today):
            self.db.add(
                StudentFee(
                    student_id=self.students[9].id,
                    month=month,
                    year=year,
                    amount=Decimal("100"),
                    product_amount=Decimal("0"),
                    balance_amount=Decimal("0"),
                    status=FeeStatus.PAID,
                    due_date=date(year, month, 1),
                )
            )
        self.db.commit()

        self.app = FastAPI()
        self.app.include_router(fees.router)
        self.app.include_router(insights.router)
        self.app.include_router(insights.versioned_router)

        def get_test_db():
            yield self.db

        self.app.dependency_overrides[get_db] = get_test_db
        self.app.dependency_overrides[get_current_user] = lambda: self.admin
        self.client = TestClient(self.app)

    @staticmethod
    def _last_months(today):
        month, year = today.month, today.year
        months = []
        for _ in range(3):
            months.append((month, year))
            month -= 1
            if month == 0:
                month, year = 12, year - 1
        return months

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def test_admin_gets_three_predictions_and_metrics(self):
        response = self.client.get("/insights/revenue-risk")

        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.assertEqual(len(payload["risks"]), 3)
        self.assertEqual(payload["risks"][0]["type"], "fee_default")
        self.assertEqual(payload["risks"][0]["student_ids"], [self.students[10].id])
        self.assertEqual(payload["risks"][0]["students"][0]["student_name"], "Student 10")
        self.assertEqual(payload["summary"]["total_at_risk"], 4250.0)
        self.assertEqual(payload["forecast"]["next_month_revenue"], 100.0)
        self.assertEqual([row["collected"] for row in payload["forecast"]["monthly_collections"]], [100.0, 100.0, 100.0])
        self.assertEqual(payload["kpis"]["total_students"], 11)
        self.assertEqual(payload["batch_analytics"]["attendance_drop_batches"][0]["batch_id"], self.batch.id)

    def test_coach_is_forbidden_from_insights(self):
        self.app.dependency_overrides[get_current_user] = lambda: self.coach

        response = self.client.get("/insights/revenue-risk")
        versioned_response = self.client.get("/api/v1/insights/revenue-risk")

        self.assertEqual(response.status_code, 403, response.text)
        self.assertEqual(versioned_response.status_code, 403, versioned_response.text)

    def test_versioned_path_and_admin_reminder_return_queued(self):
        response = self.client.get("/api/v1/insights/revenue-risk")
        self.assertEqual(response.status_code, 200, response.text)

        reminder = self.client.post(f"/api/v1/fees/{self.defaulter_fee.id}/remind")
        self.assertEqual(reminder.status_code, 200, reminder.text)
        self.assertEqual(reminder.json()["status"], "queued")

        self.app.dependency_overrides[get_current_user] = lambda: self.coach
        forbidden = self.client.post(f"/api/v1/fees/{self.defaulter_fee.id}/remind")
        self.assertEqual(forbidden.status_code, 403, forbidden.text)


if __name__ == "__main__":
    unittest.main()
