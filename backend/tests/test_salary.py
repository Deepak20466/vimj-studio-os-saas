import unittest
from decimal import Decimal

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.models import User, UserRole
from app.models.salary import CoachSalary
from app.routers import salary
from app.security import get_current_user


class SalaryApiTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.session_factory = sessionmaker(bind=self.engine)
        self.db = self.session_factory()
        self.admin = User(
            name="Admin", email="admin@example.com", role=UserRole.ADMIN,
            password_hash="unused",
        )
        self.coach = User(
            name="Coach One", email="coach1@example.com", role=UserRole.COACH,
            password_hash="unused",
        )
        self.other_coach = User(
            name="Coach Two", email="coach2@example.com", role=UserRole.COACH,
            password_hash="unused",
        )
        self.db.add_all([self.admin, self.coach, self.other_coach])
        self.db.flush()
        self.db.add_all([
            CoachSalary(coach_id=self.coach.id, month=1, year=2026, amount=Decimal("25000.00")),
            CoachSalary(coach_id=self.other_coach.id, month=1, year=2026, amount=Decimal("30000.00")),
        ])
        self.db.commit()

        self.current_user = self.admin
        self.app = FastAPI()
        self.app.include_router(salary.router)
        self.app.dependency_overrides[get_db] = lambda: self.db
        self.app.dependency_overrides[get_current_user] = lambda: self.current_user
        self.client = TestClient(self.app)

    def tearDown(self):
        self.client.close()
        self.db.close()
        self.engine.dispose()

    def test_admin_can_create_and_list_salary(self):
        created = self.client.post("/salary", json={
            "coach_id": self.coach.id,
            "month": 2,
            "year": 2026,
            "amount": "26000.00",
        })
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.json()["amount"], "26000.00")

        listed = self.client.get("/salary")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(len(listed.json()), 3)

    def test_admin_can_download_pdf_and_csv(self):
        csv_response = self.client.get("/salary/export?fmt=csv")
        self.assertEqual(csv_response.status_code, 200)
        self.assertIn("text/csv", csv_response.headers["content-type"])
        self.assertIn("Coach One", csv_response.text)
        self.assertIn("Coach Two", csv_response.text)

        pdf_response = self.client.get("/salary/export?fmt=pdf")
        self.assertEqual(pdf_response.status_code, 200)
        self.assertIn("application/pdf", pdf_response.headers["content-type"])
        self.assertTrue(pdf_response.content.startswith(b"%PDF"))

    def test_coach_export_is_always_limited_to_own_records(self):
        self.current_user = self.coach
        csv_response = self.client.get(
            f"/salary/export?fmt=csv&coach_id={self.other_coach.id}"
        )
        self.assertEqual(csv_response.status_code, 200)
        self.assertIn("Coach One", csv_response.text)
        self.assertNotIn("Coach Two", csv_response.text)
        self.assertNotIn("30000.00", csv_response.text)

        pdf_response = self.client.get("/salary/export?fmt=pdf")
        self.assertEqual(pdf_response.status_code, 200)
        self.assertTrue(pdf_response.content.startswith(b"%PDF"))

    def test_export_rejects_unknown_format(self):
        response = self.client.get("/salary/export?fmt=xlsx")
        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
