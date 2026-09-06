from sqlalchemy import Column, Integer, ForeignKey, DateTime, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class CoachActivity(Base):
    """Which activities a coach is authorized/assigned to (admin-managed).

    Drives batch/coach assignment pickers, roster visibility, and which
    activity a coach may add a new student under.
    """

    __tablename__ = "coach_activities"
    __table_args__ = (UniqueConstraint("coach_id", "activity_id", name="uq_coach_activity"),)

    id = Column(Integer, primary_key=True, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    activity_id = Column(Integer, ForeignKey("activities.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    coach = relationship("User", foreign_keys=[coach_id])
    activity = relationship("Activity")
