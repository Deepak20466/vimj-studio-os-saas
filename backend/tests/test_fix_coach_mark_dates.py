import importlib.util
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base
from app.models.attendance import AttendanceStatus, CoachAttendance, CoachAttendanceStatus  # noqa: F401
from app.models.audit import AuditLog
from app.models.user import User, UserRole

_spec = importlib.util.spec_from_file_location(
    "fix_coach_mark_dates",
    Path(__file__).resolve().parent.parent / "scripts" / "fix_coach_mark_dates.py",
)
fix = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fix)


class FixCoachMarkDatesTests(unittest.TestCase):
    def setUp(self):
        engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
        )
        Base.metadata.create_all(engine)
        self.db = sessionmaker(bind=engine)()
        self.coach = User(name="C", email="c@example.com", role=UserRole.COACH, password_hash="x")
        self.db.add(self.coach)
        self.other = User(name="D", email="d@example.com", role=UserRole.COACH, password_hash="x")
        self.db.add(self.other)
        self.db.flush()

    def tearDown(self):
        self.db.close()

    def _mark(self, record_id, stored_date, utc_moment, coach_id=None):
        self.db.add(CoachAttendance(id=record_id, coach_id=coach_id or self.coach.id, date=stored_date,
                                    status=CoachAttendanceStatus.PRESENT))
        self.db.add(AuditLog(user_id=self.coach.id, action="COACH_MARK_ATTENDANCE",
                             entity_type="CoachAttendance", entity_id=record_id,
                             created_at=utc_moment))
        self.db.flush()

    def test_misdated_self_mark_is_corrected_and_admin_entries_are_not(self):
        # 01:30 IST on 12 Nov (19:00 UTC on 11 Nov), but filed under 11 Nov.
        self._mark(1, date(2026, 11, 11), datetime(2026, 11, 11, 19, 0, tzinfo=timezone.utc))
        # Correctly filed mark made at 10:00 IST on 12 Nov by another coach: must be left alone.
        self._mark(2, date(2026, 11, 12), datetime(2026, 11, 12, 4, 30, tzinfo=timezone.utc),
                   coach_id=self.other.id)
        # Admin manual entry for 11 Nov, with no self-mark audit row: must be left alone.
        self.db.add(CoachAttendance(coach_id=self.coach.id, date=date(2026, 11, 11),
                                    status=CoachAttendanceStatus.ABSENT))
        self.db.flush()

        fixable, collisions = fix.find_candidates(self.db)

        self.assertEqual([e["id"] for e in fixable], [1])
        self.assertEqual(fixable[0]["new_date"], "2026-11-12")
        self.assertEqual(collisions, [])

    def test_correction_that_would_collide_is_reported_not_applied(self):
        self._mark(1, date(2026, 11, 11), datetime(2026, 11, 11, 19, 0, tzinfo=timezone.utc))
        # The same coach already has a correctly dated mark for 12 Nov: moving record 1 would collide.
        self._mark(2, date(2026, 11, 12), datetime(2026, 11, 12, 6, 0, tzinfo=timezone.utc))

        fixable, collisions = fix.find_candidates(self.db)

        self.assertEqual(fixable, [])
        self.assertEqual([e["id"] for e in collisions], [1])


if __name__ == "__main__":
    unittest.main()
