from datetime import datetime, date

from pydantic import BaseModel

from app.models.swap import SwapStatus


class SwapRequestCreate(BaseModel):
    covering_coach_id: int
    class_id: int
    date: date


class SwapOut(BaseModel):
    id: int
    original_coach_id: int
    covering_coach_id: int
    class_id: int
    date: date
    status: SwapStatus
    created_at: datetime

    class Config:
        from_attributes = True
