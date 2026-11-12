"""Correct coach self-marks that were filed under the previous day.

Before the facility-clock fix, POST /attendance/coach-mark used the server's UTC
date. A coach marking between 00:00 and 05:30 IST therefore got a record dated
the day before. The audit log keeps the true moment of every self-mark
(action COACH_MARK_ATTENDANCE, entity_id = the coach_attendance row id), so this
script uses that moment, converted to IST, as the correct date.

Only records that are exactly one day behind their audit moment are touched.
Admin manual entries are never changed: they have no COACH_MARK_ATTENDANCE audit
row and carry an explicitly chosen date. If the corrected date would collide with
another record for the same coach, the row is skipped and reported for a human.

Usage (from backend/, with DATABASE_URL set to the target database):

    python scripts/fix_coach_mark_dates.py --backup backup.json            # dry run
    python scripts/fix_coach_mark_dates.py --backup backup.json --apply    # write

The dry run is the default and changes nothing. With --apply, a JSON backup of
every changed row is written first, and all updates commit in one transaction.
"""

import argparse
import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import SessionLocal  # noqa: E402
from app.models.attendance import CoachAttendance  # noqa: E402
from app.models.audit import AuditLog  # noqa: E402

FACILITY_TZ = ZoneInfo("Asia/Kolkata")


def _as_ist(moment: datetime) -> datetime:
    if moment.tzinfo is None:
        # Audit timestamps are written by the database clock as timezone-aware
        # values; a naive value can only come from a driver that dropped the offset.
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(FACILITY_TZ)


def find_candidates(db):
    """Return (fixable, collisions): records whose date is one day behind their mark."""
    marks = (
        db.query(AuditLog.entity_id, AuditLog.created_at)
        .filter(AuditLog.action == "COACH_MARK_ATTENDANCE", AuditLog.entity_type == "CoachAttendance")
        .order_by(AuditLog.created_at)
        .all()
    )
    moment_by_record = {}
    for entity_id, created_at in marks:
        if entity_id is not None:
            moment_by_record.setdefault(entity_id, created_at)

    fixable, collisions = [], []
    for record_id, created_at in moment_by_record.items():
        record = db.query(CoachAttendance).filter(CoachAttendance.id == record_id).first()
        if record is None:
            continue
        local_moment = _as_ist(created_at)
        correct = local_moment.date()
        if record.date == correct or (correct - record.date).days != 1:
            continue
        clash = (
            db.query(CoachAttendance)
            .filter(
                CoachAttendance.coach_id == record.coach_id,
                CoachAttendance.date == correct,
                CoachAttendance.id != record.id,
            )
            .first()
        )
        entry = {
            "id": record.id,
            "coach_id": record.coach_id,
            "status": record.status.value if record.status else None,
            "old_date": record.date.isoformat(),
            "new_date": correct.isoformat(),
            "marked_at_ist": local_moment.strftime("%Y-%m-%d %H:%M"),
        }
        (collisions if clash else fixable).append(entry)
    return fixable, collisions


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--backup", required=True, help="Path for the JSON backup written before any change")
    parser.add_argument("--apply", action="store_true", help="Actually update the rows (default: dry run)")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        fixable, collisions = find_candidates(db)
        print(f"Records to correct: {len(fixable)}")
        for entry in fixable:
            print(f"  record {entry['id']}: coach {entry['coach_id']} {entry['old_date']} -> {entry['new_date']} (marked {entry['marked_at_ist']} IST)")
        print(f"Skipped, would collide with an existing record (review by hand): {len(collisions)}")
        for entry in collisions:
            print(f"  record {entry['id']}: coach {entry['coach_id']} {entry['old_date']} -> {entry['new_date']}")

        if not args.apply:
            print("Dry run only. Re-run with --apply to write these changes.")
            return
        if not fixable:
            print("Nothing to change.")
            return

        Path(args.backup).write_text(json.dumps(fixable, indent=2), encoding="utf-8")
        print(f"Backup written to {args.backup}")
        for entry in fixable:
            record = db.query(CoachAttendance).filter(CoachAttendance.id == entry["id"]).one()
            record.date = date.fromisoformat(entry["new_date"])
        db.commit()
        print(f"Updated {len(fixable)} record(s).")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
