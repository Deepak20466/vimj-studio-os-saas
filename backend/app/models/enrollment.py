from sqlalchemy import Column, Integer, ForeignKey, DateTime, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class StudentEnrollment(Base):
    """Links a student to an activity so coaches have a class roster to mark attendance against."""

    __tablename__ = "student_enrollments"
    __table_args__ = (UniqueConstraint("student_id", "activity_id", name="uq_student_activity"),)

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    activity_id = Column(Integer, ForeignKey("activities.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    student = relationship("User", foreign_keys=[student_id])
    activity = relationship("Activity")
