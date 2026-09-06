from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel

from app.models.fee_receipt import ReceiptStatus


class FeeReceiptCreate(BaseModel):
    student_id: int
    amount: Decimal
    month: int
    year: int
    payment_mode: str = "CASH"
    note: Optional[str] = None


class FeeReceiptDecision(BaseModel):
    decision_note: Optional[str] = None


class FeeReceiptOut(BaseModel):
    id: int
    student_id: int
    coach_id: int
    amount: Decimal
    month: int
    year: int
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
