import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.login_guard import login_guard
from app.core.rate_limit import limiter
from app.database import Base, get_db
from app.models.user import PasswordResetToken, User, UserRole
from app.routers import auth


class PasswordResetGuardTests(unittest.TestCase):
    """Guards on the reset token: single use, and a token must belong to an existing user."""

    def setUp(self):
        limiter.reset()
        login_guard.clear()
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.session_factory = sessionmaker(bind=self.engine)
        with self.session_factory() as db:
            db.add(
                User(
                    name="Coach",
                    email="coach@example.com",
                    role=UserRole.COACH,
                    password_hash="original-hash",
                )
            )
            db.commit()
            self.user_id = db.query(User).filter(User.email == "coach@example.com").one().id

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

    def _add_token(self, token, *, user_id, used=False):
        with self.session_factory() as db:
            db.add(
                PasswordResetToken(
                    user_id=user_id,
                    token=token,
                    used=used,
                    expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
                )
            )
            db.commit()

    def _stored_hash(self):
        with self.session_factory() as db:
            return db.query(User).filter(User.id == self.user_id).one().password_hash

    def _reset(self, client, token):
        return client.post(
            "/auth/reset-password",
            json={"token": token, "new_password": "new-password"},
        )

    def test_used_reset_token_is_rejected_and_password_unchanged(self):
        self._add_token("guard-used-token", user_id=self.user_id, used=True)
        with (
            patch("app.routers.auth.hash_password", return_value="new-password-hash"),
            patch("app.routers.auth.log_action"),
            TestClient(self.app) as client,
        ):
            response = self._reset(client, "guard-used-token")
        self.assertEqual(response.status_code, 400, response.text)
        self.assertEqual(self._stored_hash(), "original-hash")

    def test_reset_token_cannot_be_reused_after_success(self):
        self._add_token("guard-reuse-token", user_id=self.user_id)
        with (
            patch("app.routers.auth.hash_password", return_value="new-password-hash"),
            patch("app.routers.auth.log_action"),
            TestClient(self.app) as client,
        ):
            first = self._reset(client, "guard-reuse-token")
            self.assertEqual(first.status_code, 200, first.text)
            second = self._reset(client, "guard-reuse-token")
        self.assertEqual(second.status_code, 400, second.text)
        self.assertEqual(self._stored_hash(), "new-password-hash")

    def test_reset_token_for_missing_user_is_rejected(self):
        self._add_token("guard-orphan-token", user_id=999_999)
        with (
            patch("app.routers.auth.hash_password", return_value="new-password-hash"),
            patch("app.routers.auth.log_action"),
            TestClient(self.app) as client,
        ):
            response = self._reset(client, "guard-orphan-token")
        self.assertEqual(response.status_code, 400, response.text)
        self.assertEqual(self._stored_hash(), "original-hash")


if __name__ == "__main__":
    unittest.main()
