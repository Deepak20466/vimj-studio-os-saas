from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field

from app.models.fee_receipt import ReceiptStatus


class FeeReceiptCreate(BaseModel):
    student_id: int
    product_amount: Decimal = Field(default=Decimal("0"), ge=0)
    product_name: Optional[str] = None
    amount: Decimal = Field(ge=0)
    month: int = Field(ge=1, le=12)
    year: int = Field(ge=2000, le=2100)
    billing_date: Optional[date] = None
    payment_mode: str = "CASH"
    note: Optional[str] = None


class FeeReceiptDecision(BaseModel):
    decision_note: Optional[str] = None


class FeeReceiptOut(BaseModel):
    id: int
    student_id: int
    coach_id: int
    product_amount: Decimal = Field(default=Decimal("0"), ge=0)
    product_name: Optional[str] = None
    amount: Decimal = Field(ge=0)
    month: int = Field(ge=1, le=12)
    year: int = Field(ge=2000, le=2100)
    billing_date: Optional[date] = None
    payment_mode: str
    note: Optional[str]
    status: ReceiptStatus
    decision_note: Optional[str]
    created_at: datetime
    decided_at: Optional[datetime]

    class Config:
        from_attributes = True


class FeeReceiptAdminOut(FeeReceiptOut):
    student_name: str
    coach_name: str
