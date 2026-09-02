from datetime import date
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.models.fee import StudentFee, FeeStatus
from app.schemas.fee import FeeCreate, FeeMarkPaid, FeeOut
from app.security import require_admin
from app.services.audit import log_action
from app.services.notifications import notify

router = APIRouter(prefix="/fees", tags=["fees"])


@router.post("", response_model=FeeOut, status_code=status.HTTP_201_CREATED)
def create_fee(
    payload: FeeCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    existing = (
        db.query(StudentFee)
        .filter(
            StudentFee.student_id == payload.student_id,
            StudentFee.month == payload.month,
            StudentFee.year == payload.year,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Fee record already exists for this period")

    fee = StudentFee(**payload.model_dump())
    db.add(fee)
    db.flush()
    log_action(db, current_user.id, "CREATE", "StudentFee", fee.id)
    db.commit()
    db.refresh(fee)
    return fee


@router.get("/unpaid", response_model=List[FeeOut])
def unpaid_fees(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return (
        db.query(StudentFee)
        .filter(StudentFee.status.in_([FeeStatus.UNPAID, FeeStatus.OVERDUE]))
        .order_by(StudentFee.due_date)
        .all()
    )


@router.post("/mark-paid", response_model=FeeOut)
def mark_paid(
    payload: FeeMarkPaid,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    fee = db.query(StudentFee).filter(StudentFee.id == payload.fee_id).first()
    if not fee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fee record not found")

    fee.status = FeeStatus.PAID
    fee.paid_date = payload.paid_date or date.today()
    log_action(db, current_user.id, "MARK_PAID", "StudentFee", fee.id)
    db.commit()
    db.refresh(fee)
    return fee


@router.post("/{fee_id}/remind")
def send_reminder(
    fee_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    fee = db.query(StudentFee).filter(StudentFee.id == fee_id).first()
    if not fee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fee record not found")

    student = db.query(User).filter(User.id == fee.student_id).first()
    if student and student.phone:
        notify(
            student.phone,
            f"Reminder: your VIMJ Studio fee of {fee.amount} for {fee.month}/{fee.year} is {fee.status.value.lower()}.",
        )
    log_action(db, current_user.id, "SEND_REMINDER", "StudentFee", fee.id)
    db.commit()
    return {"detail": "Reminder sent"}
