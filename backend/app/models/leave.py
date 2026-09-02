import enum

from sqlalchemy import Column, Integer, ForeignKey, DateTime, Enum, Date, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class LeaveStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class CoachLeave(Base):
    __tablename__ = "coach_leave"

    id = Column(Integer, primary_key=True, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)
    reason = Column(String(1000), nullable=False)
    status = Column(Enum(LeaveStatus), nullable=False, default=LeaveStatus.PENDING, index=True)
    approved_by_admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    decision_note = Column(String(1000), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    coach = relationship("User", foreign_keys=[coach_id])
    approved_by = relationship("User", foreign_keys=[approved_by_admin_id])
