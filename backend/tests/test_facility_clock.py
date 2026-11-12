import unittest
from datetime import date, datetime, timezone
from unittest.mock import patch

from app.core import clock


class _FrozenDateTime(datetime):
    """Pins the wall clock to 2026-11-11 20:00 UTC, i.e. 01:30 on 12 Nov in IST."""

    @classmethod
    def now(cls, tz=None):
        instant = datetime(2026, 11, 11, 20, 0, tzinfo=timezone.utc)
        return instant.astimezone(tz) if tz else instant.replace(tzinfo=None)


class FacilityClockTests(unittest.TestCase):
    def test_marks_after_utc_midnight_but_before_0530_ist_use_ist_date(self):
        with patch.object(clock, "datetime", _FrozenDateTime):
            self.assertEqual(clock.facility_today(), date(2026, 11, 12))
            self.assertEqual(clock.facility_now(), datetime(2026, 11, 12, 1, 30))
            aware = clock.facility_now_aware()
            self.assertEqual(aware.utcoffset().total_seconds(), 5.5 * 3600)


if __name__ == "__main__":
    unittest.main()
