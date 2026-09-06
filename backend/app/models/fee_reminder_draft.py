import enum

from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class ReminderDraftStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class FeeReminderDraft(Base):
    """A coach-written fee reminder message, held for admin approval before it is sent to the student."""

    __tablename__ = "fee_reminder_drafts"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    month = Column(Integer, nullable=False)
    year = Column(Integer, nullable=False)
    message = Column(Text, nullable=False)
    status = Column(Enum(ReminderDraftStatus), nullable=False, default=ReminderDraftStatus.PENDING)
    decision_note = Column(Text, nullable=True)
    approved_by_admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    sent_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    decided_at = Column(DateTime(timezone=True), nullable=True)

    student = relationship("User", foreign_keys=[student_id])
    coach = relationship("User", foreign_keys=[coach_id])
