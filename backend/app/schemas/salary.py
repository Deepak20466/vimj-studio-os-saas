from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field


class SalaryCreate(BaseModel):
    coach_id: int
    month: int = Field(ge=1, le=12)
    year: int = Field(ge=2000, le=9999)
    amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2)


class SalaryAcknowledge(BaseModel):
    salary_id: int


class SalaryUpdate(BaseModel):
    amount: Optional[Decimal] = Field(default=None, gt=0, max_digits=10, decimal_places=2)
    month: Optional[int] = Field(default=None, ge=1, le=12)
    year: Optional[int] = Field(default=None, ge=2000, le=9999)


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
