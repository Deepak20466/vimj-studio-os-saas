import enum

from sqlalchemy import Column, Integer, String, Text, Boolean, DateTime, Enum, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class LateStatus(str, enum.Enum):
    NONE = "NONE"
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class ClassSkipReason(Base):
    """A coach's reason for not conducting a scheduled class."""

    __tablename__ = "class_skip_reasons"

    id = Column(Integer, primary_key=True, index=True)
    class_id = Column(Integer, ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    reason = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    class_session = relationship("ClassSession")
    coach = relationship("User", foreign_keys=[coach_id])


class AttendanceSubmission(Base):
    """Tracks whether/when attendance was submitted for a class, and any late-marking approval."""

    __tablename__ = "attendance_submissions"

    id = Column(Integer, primary_key=True, index=True)
    class_id = Column(Integer, ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    submitted_at = Column(DateTime(timezone=True), nullable=True)
    is_late = Column(Boolean, default=False, nullable=False)
    late_reason = Column(Text, nullable=True)
    late_status = Column(Enum(LateStatus), nullable=False, default=LateStatus.NONE, index=True)
    decided_by_admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    decided_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    class_session = relationship("ClassSession")
    coach = relationship("User", foreign_keys=[coach_id])
    decided_by = relationship("User", foreign_keys=[decided_by_admin_id])


class ClassPhoto(Base):
    """Batch/session-completion photo captured by a coach."""

    __tablename__ = "class_photos"

    id = Column(Integer, primary_key=True, index=True)
    class_id = Column(Integer, ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    photo_path = Column(String(500), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    class_session = relationship("ClassSession")
    coach = relationship("User", foreign_keys=[coach_id])
