from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel

from app.models.fee import FeeStatus


class FeeCreate(BaseModel):
    student_id: int
    month: int
    year: int
    amount: Decimal
    due_date: date


class FeeMarkPaid(BaseModel):
    fee_id: int
    paid_date: Optional[date] = None


class FeeOut(BaseModel):
    id: int
    student_id: int
    month: int
    year: int
    amount: Decimal
    status: FeeStatus
    due_date: date
    paid_date: Optional[date]
    created_at: datetime

    class Config:
        from_attributes = True
