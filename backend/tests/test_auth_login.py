import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.rate_limit import limiter
from app.database import Base, get_db
from app.models.user import User, UserRole
from app.routers import auth


class AuthLoginTests(unittest.TestCase):
    def setUp(self):
        limiter.reset()
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.session_factory = sessionmaker(bind=self.engine)
        with self.session_factory() as db:
            db.add_all(
                [
                    User(
                        name="Admin",
                        email="admin@example.com",
                        role=UserRole.ADMIN,
                        password_hash="admin-hash",
                    ),
                    User(
                        name="Coach",
                        email="coach@example.com",
                        role=UserRole.COACH,
                        password_hash="coach-hash",
                    ),
                ]
            )
            db.commit()

        self.app = FastAPI()
        self.app.state.limiter = limiter
        self.app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
        self.app.include_router(auth.router)

        def get_test_db():
            db = self.session_factory()
            try:
                yield db
            finally:
                db.close()

        self.app.dependency_overrides[get_db] = get_test_db

    def tearDown(self):
        self.engine.dispose()

    def _client(self):
        return TestClient(self.app)

    def test_admin_and_coach_login_return_compatible_token_responses(self):
        with (
            patch(
                "app.routers.auth.verify_password",
                side_effect=lambda password, stored: password == "correct-password"
                and stored in {"admin-hash", "coach-hash"},
            ),
            patch("app.routers.auth.log_action"),
            self._client() as client,
        ):
            for email, role, user_id in (
                ("admin@example.com", "ADMIN", 1),
                ("coach@example.com", "COACH", 2),
            ):
                response = client.post(
                    "/auth/login",
                    json={"email": email, "password": "correct-password"},
                )
                self.assertEqual(response.status_code, 200, response.text)
                payload = response.json()
                self.assertEqual(payload["role"], role)
                self.assertEqual(payload["user_id"], user_id)
                self.assertTrue(payload["access_token"])
                self.assertTrue(payload["refresh_token"])

    def test_invalid_password_still_returns_unauthorized(self):
        with (
            patch("app.routers.auth.verify_password", return_value=False),
            self._client() as client,
        ):
            response = client.post(
                "/auth/login",
                json={"email": "admin@example.com", "password": "wrong-password"},
            )

        self.assertEqual(response.status_code, 401, response.text)
        self.assertEqual(response.json()["detail"], "Invalid email or password")

    def test_login_rate_limit_still_returns_429(self):
        with (
            patch("app.routers.auth.verify_password", return_value=False),
            self._client() as client,
        ):
            for _ in range(5):
                response = client.post(
                    "/auth/login",
                    json={"email": "admin@example.com", "password": "wrong-password"},
                )
                self.assertEqual(response.status_code, 401, response.text)

            limited = client.post(
                "/auth/login",
                json={"email": "admin@example.com", "password": "wrong-password"},
            )

        self.assertEqual(limited.status_code, 429, limited.text)
        self.assertIn("Rate limit exceeded", limited.json()["error"])

    def test_forgot_password_rate_limiter_returns_generic_response(self):
        with self._client() as client:
            response = client.post(
                "/auth/forgot-password",
                json={"email": "not-found@example.com"},
            )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(
            response.json()["detail"],
            "If the email exists, a reset link has been sent",
        )


if __name__ == "__main__":
    unittest.main()
