import io
from datetime import date, datetime
from decimal import Decimal
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.activity import Activity
from app.models.enrollment import StudentEnrollment
from app.models.user import User, UserRole
from app.models.fee import StudentFee, FeeStatus
from app.models.fee_receipt import FeeReceipt, ReceiptStatus
from app.schemas.fee_receipt import (
    FeeReceiptCreate,
    FeeReceiptDecision,
    FeeReceiptOut,
    FeeReceiptAdminOut,
)
from app.security import require_admin, require_coach, require_admin_or_coach
from app.services.audit import log_action
from app.services.authorization import coach_may_bill_student
from app.services.notifications import notify, notify_and_push
from app.services.receipt_pdf import build_fee_receipt_pdf

router = APIRouter(prefix="/receipts", tags=["receipts"])


@router.post("", response_model=FeeReceiptOut, status_code=status.HTTP_201_CREATED)
def create_receipt(
    payload: FeeReceiptCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    student = db.query(User).filter(User.id == payload.student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Student not found")
    if not coach_may_bill_student(db, current_user.id, payload.student_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Student is not enrolled in one of your assigned activities",
        )

    receipt = FeeReceipt(
        student_id=payload.student_id,
        coach_id=current_user.id,
        amount=payload.amount,
        month=payload.month,
        year=payload.year,
        payment_mode=payload.payment_mode,
        note=payload.note,
    )
    db.add(receipt)
    db.flush()
    log_action(db, current_user.id, "CREATE", "FeeReceipt", receipt.id)
    db.commit()
    db.refresh(receipt)

    admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
    for admin in admins:
        notify_and_push(
            db, admin,
            f"{current_user.name} recorded a fee receipt of Rs {receipt.amount} for {student.name} ({receipt.month}/{receipt.year}), awaiting your approval.",
            "Fee receipt awaiting approval", "RECEIPT_PENDING", link="/fees",
        )
    db.commit()
    return receipt


@router.get("/my", response_model=List[FeeReceiptAdminOut])
def my_receipts(db: Session = Depends(get_db), current_user: User = Depends(require_coach)):
    receipts = (
        db.query(FeeReceipt)
        .filter(FeeReceipt.coach_id == current_user.id)
        .order_by(FeeReceipt.created_at.desc())
        .all()
    )
    return _to_admin_out(db, receipts)


@router.get("/pending", response_model=List[FeeReceiptAdminOut])
def pending_receipts(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    receipts = (
        db.query(FeeReceipt)
        .filter(FeeReceipt.status == ReceiptStatus.PENDING)
        .order_by(FeeReceipt.created_at)
        .all()
    )
    return _to_admin_out(db, receipts)


@router.get("", response_model=List[FeeReceiptAdminOut])
def list_receipts(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    receipts = db.query(FeeReceipt).order_by(FeeReceipt.created_at.desc()).limit(500).all()
    return _to_admin_out(db, receipts)


def _to_admin_out(db: Session, receipts: List[FeeReceipt]) -> List[FeeReceiptAdminOut]:
    user_ids = {r.student_id for r in receipts} | {r.coach_id for r in receipts}
    names = {u.id: u.name for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
    return [
        FeeReceiptAdminOut(
            id=r.id,
            student_id=r.student_id,
            student_name=names.get(r.student_id, "Unknown"),
            coach_id=r.coach_id,
            coach_name=names.get(r.coach_id, "Unknown"),
            amount=r.amount,
            month=r.month,
            year=r.year,
            payment_mode=r.payment_mode,
            note=r.note,
            status=r.status,
            decision_note=r.decision_note,
            created_at=r.created_at,
            decided_at=r.decided_at,
        )
        for r in receipts
    ]


@router.put("/{receipt_id}/approve", response_model=FeeReceiptOut)
def approve_receipt(
    receipt_id: int,
    payload: FeeReceiptDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    receipt = db.query(FeeReceipt).filter(FeeReceipt.id == receipt_id).first()
    if not receipt:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Receipt not found")
    if receipt.status != ReceiptStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Receipt already decided")

    fee = (
        db.query(StudentFee)
        .filter(
            StudentFee.student_id == receipt.student_id,
            StudentFee.month == receipt.month,
            StudentFee.year == receipt.year,
        )
        .first()
    )
    if not fee:
        fee = StudentFee(
            student_id=receipt.student_id,
            month=receipt.month,
            year=receipt.year,
            amount=receipt.amount,
            balance_amount=Decimal("0"),
            due_date=date(receipt.year, receipt.month, 10),
        )
        db.add(fee)
    fee.status = FeeStatus.PAID
    fee.balance_amount = Decimal("0")
    fee.paid_date = date.today()

    receipt.status = ReceiptStatus.APPROVED
    receipt.decision_note = payload.decision_note
    receipt.approved_by_admin_id = current_user.id
    receipt.decided_at = datetime.utcnow()

    log_action(db, current_user.id, "APPROVE_RECEIPT", "FeeReceipt", receipt.id)
    db.commit()
    db.refresh(receipt)

    coach = db.query(User).filter(User.id == receipt.coach_id).first()
    notify_and_push(
        db,
        coach,
        f"Your fee receipt for {receipt.month}/{receipt.year} was approved.",
        "Receipt approved",
        "RECEIPT_APPROVED",
    )
    student = db.query(User).filter(User.id == receipt.student_id).first()
    if student and student.phone:
        notify(student.phone, f"Your fee payment for {receipt.month}/{receipt.year} has been confirmed.")
    db.commit()
    return receipt


@router.put("/{receipt_id}/reject", response_model=FeeReceiptOut)
def reject_receipt(
    receipt_id: int,
    payload: FeeReceiptDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    receipt = db.query(FeeReceipt).filter(FeeReceipt.id == receipt_id).first()
    if not receipt:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Receipt not found")
    if receipt.status != ReceiptStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Receipt already decided")

    receipt.status = ReceiptStatus.REJECTED
    receipt.decision_note = payload.decision_note
    receipt.approved_by_admin_id = current_user.id
    receipt.decided_at = datetime.utcnow()

    log_action(db, current_user.id, "REJECT_RECEIPT", "FeeReceipt", receipt.id)
    db.commit()
    db.refresh(receipt)

    coach = db.query(User).filter(User.id == receipt.coach_id).first()
    notify_and_push(
        db,
        coach,
        f"Your fee receipt for {receipt.month}/{receipt.year} was rejected: {receipt.decision_note or 'no reason given'}",
        "Receipt rejected",
        "RECEIPT_REJECTED",
    )
    db.commit()
    return receipt


@router.get("/{receipt_id}/pdf")
def receipt_pdf(
    receipt_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    receipt = db.query(FeeReceipt).filter(FeeReceipt.id == receipt_id).first()
    if not receipt:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Receipt not found")
    if current_user.role == UserRole.COACH and receipt.coach_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your receipt")
    if receipt.status != ReceiptStatus.APPROVED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Receipt must be approved by admin before a PDF can be issued",
        )

    student = db.query(User).filter(User.id == receipt.student_id).first()
    approver = db.query(User).filter(User.id == receipt.approved_by_admin_id).first() if receipt.approved_by_admin_id else None
    activity_names = [
        name
        for (name,) in (
            db.query(Activity.name)
            .join(StudentEnrollment, StudentEnrollment.activity_id == Activity.id)
            .filter(StudentEnrollment.student_id == receipt.student_id)
            .all()
        )
    ]
    fee = (
        db.query(StudentFee)
        .filter(
            StudentFee.student_id == receipt.student_id,
            StudentFee.month == receipt.month,
            StudentFee.year == receipt.year,
        )
        .first()
    )
    balance_amount = fee.balance_amount if fee else Decimal("0")

    pdf_bytes = build_fee_receipt_pdf(
        receipt_no=f"RCPT-{receipt.id:06d}",
        student_name=student.name if student else "Unknown",
        activity_names=activity_names,
        month=receipt.month,
        year=receipt.year,
        amount_paid=receipt.amount,
        balance_amount=balance_amount,
        payment_mode=receipt.payment_mode,
        paid_date=receipt.decided_at.date() if receipt.decided_at else date.today(),
        approved_by=approver.name if approver else None,
    )
    log_action(db, current_user.id, "DOWNLOAD_RECEIPT_PDF", "FeeReceipt", receipt.id)
    db.commit()
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=receipt_{receipt.id}.pdf"},
    )
