from sqlalchemy import Column, Integer, ForeignKey, Date, Time, DateTime, LargeBinary
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class ClassSession(Base):
    __tablename__ = "classes"

    id = Column(Integer, primary_key=True, index=True)
    activity_id = Column(Integer, ForeignKey("activities.id", ondelete="CASCADE"), nullable=False, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    batch_id = Column(Integer, ForeignKey("batches.id", ondelete="SET NULL"), nullable=True, index=True)
    date = Column(Date, nullable=False, index=True)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    # One coach-captured group photo of the whole class, taken after the session ends
    # (mobile coach app only). Stored as bytes in Postgres, same rationale as every other
    # photo in this app — see services/storage.py.
    group_photo = Column(LargeBinary, nullable=True)
    group_photo_uploaded_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    activity = relationship("Activity", back_populates="classes")
    coach = relationship("User", foreign_keys=[coach_id])
    batch = relationship("Batch")
    student_attendance = relationship("StudentAttendance", back_populates="class_session", passive_deletes=True)

    @property
    def has_group_photo(self) -> bool:
        return self.group_photo is not None
