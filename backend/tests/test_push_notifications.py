import unittest
from unittest.mock import Mock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.models import User, UserRole
from app.models.notification import PushDeviceToken
from app.routers import notifications
from app.security import get_current_user
from app.services import notifications as notification_service


class PushDeviceTokenTests(unittest.TestCase):
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
        self.student = User(name="Student", email="student@example.com", role=UserRole.STUDENT, password_hash="unused")
        self.db.add_all([self.admin, self.coach, self.student])
        self.db.commit()

        self.app = FastAPI()
        self.app.include_router(notifications.router)

        def get_test_db():
            yield self.db

        self.app.dependency_overrides[get_db] = get_test_db
        self.current_user = self.admin
        self.app.dependency_overrides[get_current_user] = lambda: self.current_user
        self.client = TestClient(self.app)

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def test_authenticated_admin_and_coach_can_register_and_remove_token(self):
        token = "fcm-device-token-for-tests-long-enough-to-pass"
        for user in (self.admin, self.coach):
            self.current_user = user
            response = self.client.post("/notifications/device-token", json={"token": token, "platform": "android"})
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(self.db.query(PushDeviceToken).count(), 1)
            removed = self.client.post("/notifications/device-token/remove", json={"token": token})
            self.assertEqual(removed.status_code, 200, removed.text)
            self.assertEqual(self.db.query(PushDeviceToken).count(), 0)

    def test_student_cannot_register_push_token(self):
        self.current_user = self.student
        response = self.client.post(
            "/notifications/device-token",
            json={"token": "fcm-device-token-for-tests-long-enough-to-pass", "platform": "android"},
        )
        self.assertEqual(response.status_code, 403, response.text)

    def test_push_uses_registered_token_and_fcm_http_v1_payload(self):
        token = "registered-fcm-device-token-long-enough-for-this-test"
        self.db.add(PushDeviceToken(user_id=self.admin.id, token=token, platform="android"))
        self.db.commit()
        fcm_session = Mock()
        fcm_session.post.return_value.ok = True

        with (
            patch("app.database.SessionLocal", return_value=self.session_factory()),
            patch.object(notification_service.settings, "FIREBASE_PROJECT_ID", "vimj-academy"),
            patch.object(notification_service, "_fcm_session", fcm_session),
        ):
            notification_service.send_push(self.admin.id, "Fee reminder", "A fee is due", "/fees")

        fcm_session.post.assert_called_once()
        url = fcm_session.post.call_args.args[0]
        payload = fcm_session.post.call_args.kwargs["json"]["message"]
        self.assertIn("/projects/vimj-academy/messages:send", url)
        self.assertEqual(payload["token"], token)
        self.assertEqual(payload["notification"], {"title": "Fee reminder", "body": "A fee is due"})
