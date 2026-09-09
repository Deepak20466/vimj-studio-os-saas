import enum

from sqlalchemy import Column, Integer, ForeignKey, DateTime, Date, Enum, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class SwapStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class SwapInitiator(str, enum.Enum):
    """Who created the swap — decides which party still needs to act on it.

    COACH-initiated (the requesting coach picked a covering coach) needs the ADMIN's
    approval via PUT /swap/{id}/approve|reject. ADMIN-initiated (an admin reassigned a
    class directly) needs the COVERING COACH's acceptance via PUT /swap/{id}/respond —
    the reassignment only takes effect once they accept, so a coach can't be committed
    to covering a class without ever agreeing to it.
    """

    ADMIN = "ADMIN"
    COACH = "COACH"


class CoachSwap(Base):
    __tablename__ = "coach_swap"

    id = Column(Integer, primary_key=True, index=True)
    original_coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    covering_coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    class_id = Column(Integer, ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, index=True)
    batch_id = Column(Integer, ForeignKey("batches.id", ondelete="SET NULL"), nullable=True, index=True)
    date = Column(Date, nullable=False)
    reason = Column(Text, nullable=True)
    status = Column(Enum(SwapStatus), nullable=False, default=SwapStatus.PENDING, index=True)
    initiated_by = Column(Enum(SwapInitiator), nullable=False, default=SwapInitiator.COACH)
    decline_reason = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    original_coach = relationship("User", foreign_keys=[original_coach_id])
    covering_coach = relationship("User", foreign_keys=[covering_coach_id])
    class_session = relationship("ClassSession", foreign_keys=[class_id])
    batch = relationship("Batch", foreign_keys=[batch_id])
