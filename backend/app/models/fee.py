import enum

from sqlalchemy import Column, Integer, ForeignKey, DateTime, Date, Enum, Numeric, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class FeeStatus(str, enum.Enum):
    PAID = "PAID"
    UNPAID = "UNPAID"
    OVERDUE = "OVERDUE"


class StudentFee(Base):
    __tablename__ = "student_fees"
    __table_args__ = (UniqueConstraint("student_id", "month", "year", name="uq_student_fee_period"),)

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    month = Column(Integer, nullable=False)
    year = Column(Integer, nullable=False)
    amount = Column(Numeric(10, 2), nullable=False)
    balance_amount = Column(Numeric(10, 2), nullable=False, default=0)
    status = Column(Enum(FeeStatus), nullable=False, default=FeeStatus.UNPAID, index=True)
    due_date = Column(Date, nullable=False)
    paid_date = Column(Date, nullable=True)
    reminder_sent_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    student = relationship("User", foreign_keys=[student_id])
