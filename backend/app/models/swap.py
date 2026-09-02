import enum

from sqlalchemy import Column, Integer, ForeignKey, DateTime, Date, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class SwapStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class CoachSwap(Base):
    __tablename__ = "coach_swap"

    id = Column(Integer, primary_key=True, index=True)
    original_coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    covering_coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    class_id = Column(Integer, ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, index=True)
    date = Column(Date, nullable=False)
    status = Column(Enum(SwapStatus), nullable=False, default=SwapStatus.PENDING, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    original_coach = relationship("User", foreign_keys=[original_coach_id])
    covering_coach = relationship("User", foreign_keys=[covering_coach_id])
    class_session = relationship("ClassSession", foreign_keys=[class_id])
