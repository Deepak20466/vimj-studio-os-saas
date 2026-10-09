from sqlalchemy import Column, DateTime, Index, Integer, String
from sqlalchemy.sql import func

from app.database import Base


class SchedulerJobExecution(Base):
    """Latest durable Cloud Scheduler run state for each named job."""

    __tablename__ = "scheduler_job_executions"
    __table_args__ = (Index("ix_scheduler_job_executions_scheduled_for", "scheduled_for"),)

    job_name = Column(String(100), primary_key=True)
    scheduled_for = Column(DateTime(timezone=True), primary_key=True)
    status = Column(String(16), nullable=False)
    attempt = Column(Integer, nullable=False, default=1, server_default="1")
    started_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    finished_at = Column(DateTime(timezone=True), nullable=True)
    error_type = Column(String(100), nullable=True)
