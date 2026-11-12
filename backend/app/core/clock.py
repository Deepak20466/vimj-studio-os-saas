"""Facility-local clock helpers.

The server runs on Cloud Run in UTC, but the academy operates in India. Any
"today" that decides which day an attendance mark, fee, receipt or class
belongs to must use the facility timezone, or a mark made between 00:00 and
05:30 IST is filed under the previous day.

- ``facility_today()`` / ``facility_now()`` return *naive* IST values, matching
  the naive ``Date``/``Time`` columns used for class schedules and comparisons.
- ``facility_now_aware()`` returns an IST-aware datetime, for timestamp columns
  (``DateTime(timezone=True)``) so they are stored and displayed correctly.
"""

from datetime import date, datetime
from zoneinfo import ZoneInfo

FACILITY_TZ = ZoneInfo("Asia/Kolkata")


def facility_now_aware() -> datetime:
    return datetime.now(FACILITY_TZ)


def facility_now() -> datetime:
    return facility_now_aware().replace(tzinfo=None)


def facility_today() -> date:
    return facility_now().date()
