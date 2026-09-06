from datetime import date
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.models.fee import StudentFee, FeeStatus
from app.schemas.fee import FeeCreate, FeeMarkPaid, FeeUpdate, FeeOut, FeeAdminOut
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

    fee = StudentFee(**payload.model_dump(), balance_amount=payload.amount)
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


@router.get("", response_model=List[FeeAdminOut])
def list_fees(
    student_id: Optional[int] = None,
    status_filter: Optional[FeeStatus] = None,
    month: Optional[int] = None,
    year: Optional[int] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(StudentFee)
    if student_id:
        query = query.filter(StudentFee.student_id == student_id)
    if status_filter:
        query = query.filter(StudentFee.status == status_filter)
    if month:
        query = query.filter(StudentFee.month == month)
    if year:
        query = query.filter(StudentFee.year == year)

    fees = query.order_by(StudentFee.year.desc(), StudentFee.month.desc()).limit(500).all()
    students = {u.id: u.name for u in db.query(User).filter(User.id.in_([f.student_id for f in fees])).all()}
    return [
        FeeAdminOut(
            id=f.id,
            student_id=f.student_id,
            student_name=students.get(f.student_id, "Unknown"),
            month=f.month,
            year=f.year,
            amount=f.amount,
            status=f.status,
            due_date=f.due_date,
            paid_date=f.paid_date,
            created_at=f.created_at,
        )
        for f in fees
    ]


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
    fee.balance_amount = Decimal("0")
    fee.paid_date = payload.paid_date or date.today()
    log_action(db, current_user.id, "MARK_PAID", "StudentFee", fee.id)
    db.commit()
    db.refresh(fee)
    return fee


@router.put("/{fee_id}", response_model=FeeOut)
def update_fee(
    fee_id: int,
    payload: FeeUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    fee = db.query(StudentFee).filter(StudentFee.id == fee_id).first()
    if not fee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fee record not found")

    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(fee, field, value)

    if "balance_amount" in updates and "status" not in updates:
        if fee.balance_amount <= 0:
            fee.status = FeeStatus.PAID
            fee.paid_date = fee.paid_date or date.today()
        elif fee.status == FeeStatus.PAID:
            fee.status = FeeStatus.OVERDUE if fee.due_date < date.today() else FeeStatus.UNPAID
            fee.paid_date = None
    elif "status" in updates and "balance_amount" not in updates:
        if fee.status == FeeStatus.PAID:
            fee.balance_amount = Decimal("0")
            fee.paid_date = fee.paid_date or date.today()
        elif fee.balance_amount <= 0:
            fee.balance_amount = fee.amount

    log_action(db, current_user.id, "UPDATE", "StudentFee", fee.id)
    db.commit()
    db.refresh(fee)
    return fee


@router.delete("/{fee_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_fee(
    fee_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    fee = db.query(StudentFee).filter(StudentFee.id == fee_id).first()
    if not fee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fee record not found")

    log_action(db, current_user.id, "DELETE", "StudentFee", fee.id)
    db.delete(fee)
    db.commit()


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
