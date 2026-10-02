from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field

from app.models.fee import FeeStatus


class FeeCreate(BaseModel):
    student_id: int
    month: int = Field(ge=1, le=12)
    year: int = Field(ge=2000, le=2100)
    product_amount: Decimal = Field(default=Decimal("0"), ge=0)
    amount: Decimal = Field(ge=0)
    due_date: date


class FeeMarkPaid(BaseModel):
    fee_id: int
    paid_date: Optional[date] = None


class FeeUpdate(BaseModel):
    product_amount: Optional[Decimal] = Field(default=None, ge=0)
    amount: Optional[Decimal] = Field(default=None, ge=0)
    balance_amount: Optional[Decimal] = None
    due_date: Optional[date] = None
    status: Optional[FeeStatus] = None
    paid_date: Optional[date] = None


class FeeOut(BaseModel):
    id: int
    student_id: int
    month: int = Field(ge=1, le=12)
    year: int = Field(ge=2000, le=2100)
    product_amount: Decimal = Field(default=Decimal("0"), ge=0)
    amount: Decimal = Field(ge=0)
    balance_amount: Decimal
    status: FeeStatus
    due_date: date
    paid_date: Optional[date]
    created_at: datetime

    class Config:
        from_attributes = True


class FeeAdminOut(FeeOut):
    student_name: str
