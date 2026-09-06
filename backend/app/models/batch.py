import enum

from sqlalchemy import Column, Integer, String, DateTime, Boolean, Enum, ForeignKey, Time
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class SessionPeriod(str, enum.Enum):
    MORNING = "MORNING"
    AFTERNOON = "AFTERNOON"
    EVENING = "EVENING"


class Batch(Base):
    """A recurring weekly schedule template (activity + location + session + time + days +
    active months + coach). Actual dated occurrences are generated as `ClassSession` rows
    (see `services.batches.generate_sessions_for_batch`), both on-demand via the
    generate-sessions endpoint and automatically by the daily
    `job_auto_generate_batch_sessions` scheduler job, so attendance marking, swaps, and
    reporting all keep working against `ClassSession` unchanged.
    """

    __tablename__ = "batches"

    id = Column(Integer, primary_key=True, index=True)
    activity_id = Column(Integer, ForeignKey("activities.id", ondelete="CASCADE"), nullable=False, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    location = Column(String(255), nullable=False)
    session_period = Column(Enum(SessionPeriod), nullable=False)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    days_of_week = Column(String(40), nullable=False)  # comma list, e.g. "MON,WED,FRI"
    active_months = Column(String(60), nullable=False, default="1,2,3,4,5,6,7,8,9,10,11,12")  # comma list of month numbers 1-12
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    activity = relationship("Activity")
    coach = relationship("User", foreign_keys=[coach_id])
