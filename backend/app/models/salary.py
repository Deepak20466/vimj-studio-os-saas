from sqlalchemy import Column, Integer, ForeignKey, DateTime, Numeric, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class CoachSalary(Base):
    __tablename__ = "coach_salary"
    __table_args__ = (UniqueConstraint("coach_id", "month", "year", name="uq_coach_salary_period"),)

    id = Column(Integer, primary_key=True, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    month = Column(Integer, nullable=False)
    year = Column(Integer, nullable=False)
    amount = Column(Numeric(10, 2), nullable=False)
    notified_at = Column(DateTime(timezone=True), nullable=True)
    acknowledged_date = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    coach = relationship("User", foreign_keys=[coach_id])
