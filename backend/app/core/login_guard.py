"""Per-account lockout for failed password attempts.

Only *failed* sign-ins are recorded, and they are keyed by the normalized login
email rather than the client IP. Successful logins never count, and people who
share one facility Wi-Fi do not lock each other out. Once an account has
LOGIN_FAILURE_LIMIT failures inside LOGIN_FAILURE_WINDOW_SECONDS, further
attempts are refused until the oldest failure in that window expires.

State lives in process memory. With the single-worker deployment this is the
whole picture; with several instances each keeps its own count, which only
makes the lockout softer, never stricter for legitimate users.
"""

import math
import threading
import time
from collections import deque

from app.config import settings


def normalize_login_email(email: str) -> str:
    return email.strip().lower()


class LoginGuard:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._failures: dict[str, deque] = {}

    def _prune(self, key: str, now: float) -> deque | None:
        failures = self._failures.get(key)
        if failures is None:
            return None
        window = settings.LOGIN_FAILURE_WINDOW_SECONDS
        while failures and now - failures[0] >= window:
            failures.popleft()
        if not failures:
            del self._failures[key]
            return None
        return failures

    def retry_after(self, key: str) -> int:
        """Seconds until this account may try again; 0 means attempts are allowed."""
        now = time.monotonic()
        with self._lock:
            failures = self._prune(key, now)
            if failures is None or len(failures) < settings.LOGIN_FAILURE_LIMIT:
                return 0
            remaining = settings.LOGIN_FAILURE_WINDOW_SECONDS - (now - failures[0])
            return max(1, math.ceil(remaining))

    def record_failure(self, key: str) -> None:
        now = time.monotonic()
        with self._lock:
            failures = self._prune(key, now)
            if failures is None:
                failures = self._failures.setdefault(key, deque())
            failures.append(now)

    def reset(self, key: str) -> None:
        with self._lock:
            self._failures.pop(key, None)

    def clear(self) -> None:
        with self._lock:
            self._failures.clear()


login_guard = LoginGuard()
