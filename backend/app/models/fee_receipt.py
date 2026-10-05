import enum

from sqlalchemy import Column, Integer, String, Text, DateTime, Enum, ForeignKey, Numeric, Date
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class ReceiptStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class FeeReceipt(Base):
    """A coach-submitted record of fee collected from a student, awaiting admin approval

    before the underlying `StudentFee` is marked PAID and shared with the student.
    """

    __tablename__ = "fee_receipts"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    product_amount = Column(Numeric(10, 2), nullable=False, default=0)
    product_name = Column(String(120), nullable=True)
    amount = Column(Numeric(10, 2), nullable=False)
    billing_date = Column(Date, nullable=True)
    month = Column(Integer, nullable=False)
    year = Column(Integer, nullable=False)
    payment_mode = Column(String(20), nullable=False, default="CASH")
    note = Column(Text, nullable=True)
    status = Column(Enum(ReceiptStatus), nullable=False, default=ReceiptStatus.PENDING, index=True)
    decision_note = Column(Text, nullable=True)
    approved_by_admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    decided_at = Column(DateTime(timezone=True), nullable=True)

    student = relationship("User", foreign_keys=[student_id])
    coach = relationship("User", foreign_keys=[coach_id])
    approved_by = relationship("User", foreign_keys=[approved_by_admin_id])
