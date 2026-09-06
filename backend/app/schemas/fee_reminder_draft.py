from datetime import datetime
from typing import Optional

from pydantic import BaseModel

from app.models.fee_reminder_draft import ReminderDraftStatus


class FeeReminderDraftCreate(BaseModel):
    student_id: int
    month: int
    year: int
    message: Optional[str] = None  # if omitted, a default message is generated from the student's fee record


class FeeReminderDecision(BaseModel):
    decision_note: Optional[str] = None


class FeeReminderDraftOut(BaseModel):
    id: int
    student_id: int
    coach_id: int
    month: int
    year: int
    message: str
    status: ReminderDraftStatus
    decision_note: Optional[str]
    sent_at: Optional[datetime]
    created_at: datetime
    decided_at: Optional[datetime]

    class Config:
        from_attributes = True


class FeeReminderDraftAdminOut(FeeReminderDraftOut):
    student_name: str
    coach_name: str
