from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer
from sqlalchemy.sql import func

from app.database import Base


class AdminAttendanceVisibility(Base):
    __tablename__ = "admin_attendance_list_visibility"

    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    show_student_attendance_records = Column(Boolean, nullable=False, default=True)
    show_coach_attendance_records = Column(Boolean, nullable=False, default=True)
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
