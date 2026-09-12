from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field, model_validator

from app.models.leave import LeaveStatus


class LeaveRequestCreate(BaseModel):
    start_date: date
    end_date: date
    reason: str = Field(min_length=3, max_length=1000)

    @model_validator(mode="after")
    def check_dates(self):
        if self.end_date < self.start_date:
            raise ValueError("end_date cannot be before start_date")
        return self


class LeaveDecision(BaseModel):
    note: Optional[str] = Field(default=None, max_length=1000)


class LeaveOut(BaseModel):
    id: int
    coach_id: int
    start_date: date
    end_date: date
    reason: str
    status: LeaveStatus
    decision_note: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class LeaveAdminOut(LeaveOut):
    coach_name: str
