from datetime import datetime, date
from typing import Optional

from pydantic import BaseModel

from app.models.leave import LeaveStatus


class LeaveRequestCreate(BaseModel):
    start_date: date
    end_date: date
    reason: str


class LeaveDecision(BaseModel):
    note: Optional[str] = None


class LeaveUpdate(BaseModel):
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    reason: Optional[str] = None


class LeaveOut(BaseModel):
    id: int
    coach_id: int
    start_date: date
    end_date: date
    reason: str
    status: LeaveStatus
    approved_by_admin_id: Optional[int]
    decision_note: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class LeaveAdminOut(LeaveOut):
    coach_name: str
