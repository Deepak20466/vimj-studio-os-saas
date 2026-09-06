from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel


class SalaryCreate(BaseModel):
    coach_id: int
    month: int
    year: int
    amount: Decimal


class SalaryAcknowledge(BaseModel):
    salary_id: int


class SalaryOut(BaseModel):
    id: int
    coach_id: int
    month: int
    year: int
    amount: Decimal
    notified_at: Optional[datetime]
    acknowledged_date: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True


class SalaryAdminOut(SalaryOut):
    coach_name: str
