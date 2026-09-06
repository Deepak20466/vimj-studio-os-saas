from datetime import datetime, date
from typing import Optional

from pydantic import BaseModel

from app.models.swap import SwapStatus


class SwapRequestCreate(BaseModel):
    covering_coach_id: int
    class_id: int
    date: date
    reason: Optional[str] = None


class AdminAssignSwap(BaseModel):
    original_coach_id: int
    covering_coach_id: int
    class_id: Optional[int] = None
    batch_id: Optional[int] = None
    date: date
    reason: str


class SwapOut(BaseModel):
    id: int
    original_coach_id: int
    covering_coach_id: int
    class_id: int
    batch_id: Optional[int]
    date: date
    reason: Optional[str]
    status: SwapStatus
    created_at: datetime

    class Config:
        from_attributes = True


class SwapRecentOut(SwapOut):
    original_coach_name: str
    covering_coach_name: str
    activity_name: str
