from datetime import date, timedelta

from sqlalchemy.orm import Session

from app.models.batch import Batch
from app.models.class_session import ClassSession

WEEKDAY_CODES = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


def generate_sessions_for_batch(db: Session, batch: Batch, start_date: date, end_date: date) -> int:
    """Create one ClassSession per matching weekday/month in [start_date, end_date] that
    doesn't already exist for this batch. Shared by the manual generate-sessions endpoint
    and the daily auto-generate scheduler job."""
    days = set(batch.days_of_week.split(","))
    months = {int(m) for m in batch.active_months.split(",")}
    existing_dates = {
        row[0] for row in db.query(ClassSession.date).filter(ClassSession.batch_id == batch.id).all()
    }

    created = 0
    current = start_date
    while current <= end_date:
        if (
            current.month in months
            and WEEKDAY_CODES[current.weekday()] in days
            and current not in existing_dates
        ):
            db.add(
                ClassSession(
                    activity_id=batch.activity_id,
                    coach_id=batch.coach_id,
                    batch_id=batch.id,
                    date=current,
                    start_time=batch.start_time,
                    end_time=batch.end_time,
                )
            )
            created += 1
        current += timedelta(days=1)

    return created
