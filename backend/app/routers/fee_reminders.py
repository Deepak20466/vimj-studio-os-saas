from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.fee import StudentFee
from app.models.fee_reminder_draft import FeeReminderDraft, ReminderDraftStatus
from app.schemas.fee_reminder_draft import (
    FeeReminderDraftCreate,
    FeeReminderDecision,
    FeeReminderDraftOut,
    FeeReminderDraftAdminOut,
)
from app.security import require_admin, require_coach
from app.services.audit import log_action
from app.services.authorization import coach_may_bill_student
from app.services.notifications import notify, notify_and_push, fee_reminder_message

router = APIRouter(prefix="/fee-reminders", tags=["fee-reminders"])


@router.post("", response_model=FeeReminderDraftOut, status_code=status.HTTP_201_CREATED)
def create_draft(
    payload: FeeReminderDraftCreate,
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

    message = payload.message
    if not message:
        fee = (
            db.query(StudentFee)
            .filter(StudentFee.student_id == payload.student_id, StudentFee.month == payload.month, StudentFee.year == payload.year)
            .first()
        )
        if not fee:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fee record found for this period; write a custom message instead")
        message = fee_reminder_message(student.name, fee.month, fee.year, fee.amount, fee.due_date)

    draft = FeeReminderDraft(
        student_id=payload.student_id,
        coach_id=current_user.id,
        month=payload.month,
        year=payload.year,
        message=message,
    )
    db.add(draft)
    db.flush()
    log_action(db, current_user.id, "CREATE", "FeeReminderDraft", draft.id)
    db.commit()
    db.refresh(draft)

    admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
    for admin in admins:
        notify_and_push(
            db, admin, f"{current_user.name} submitted a fee reminder for {student.name} awaiting your approval.",
            "Fee reminder awaiting approval", "FEE_REMINDER_PENDING", link="/fees",
        )
    db.commit()
    return draft


@router.get("/my", response_model=List[FeeReminderDraftAdminOut])
def my_drafts(db: Session = Depends(get_db), current_user: User = Depends(require_coach)):
    drafts = (
        db.query(FeeReminderDraft)
        .filter(FeeReminderDraft.coach_id == current_user.id)
        .order_by(FeeReminderDraft.created_at.desc())
        .all()
    )
    return _to_admin_out(db, drafts)


@router.get("/pending", response_model=List[FeeReminderDraftAdminOut])
def pending_drafts(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    drafts = (
        db.query(FeeReminderDraft)
        .filter(FeeReminderDraft.status == ReminderDraftStatus.PENDING)
        .order_by(FeeReminderDraft.created_at)
        .all()
    )
    return _to_admin_out(db, drafts)


@router.get("", response_model=List[FeeReminderDraftAdminOut])
def list_drafts(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    drafts = db.query(FeeReminderDraft).order_by(FeeReminderDraft.created_at.desc()).limit(500).all()
    return _to_admin_out(db, drafts)


def _to_admin_out(db: Session, drafts: List[FeeReminderDraft]) -> List[FeeReminderDraftAdminOut]:
    user_ids = {d.student_id for d in drafts} | {d.coach_id for d in drafts}
    names = {u.id: u.name for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
    return [
        FeeReminderDraftAdminOut(
            id=d.id,
            student_id=d.student_id,
            student_name=names.get(d.student_id, "Unknown"),
            coach_id=d.coach_id,
            coach_name=names.get(d.coach_id, "Unknown"),
            month=d.month,
            year=d.year,
            message=d.message,
            status=d.status,
            decision_note=d.decision_note,
            sent_at=d.sent_at,
            created_at=d.created_at,
            decided_at=d.decided_at,
        )
        for d in drafts
    ]


@router.put("/{draft_id}/approve", response_model=FeeReminderDraftOut)
def approve_draft(
    draft_id: int,
    payload: FeeReminderDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    draft = db.query(FeeReminderDraft).filter(FeeReminderDraft.id == draft_id).first()
    if not draft:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reminder draft not found")
    if draft.status != ReminderDraftStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already decided")

    draft.status = ReminderDraftStatus.APPROVED
    draft.decision_note = payload.decision_note
    draft.approved_by_admin_id = current_user.id
    draft.decided_at = datetime.utcnow()

    student = db.query(User).filter(User.id == draft.student_id).first()
    if student and student.phone:
        notify(student.phone, draft.message)
        draft.sent_at = datetime.utcnow()

    log_action(db, current_user.id, "APPROVE_FEE_REMINDER", "FeeReminderDraft", draft.id)
    db.commit()
    db.refresh(draft)

    coach = db.query(User).filter(User.id == draft.coach_id).first()
    notify_and_push(
        db, coach, f"Your fee reminder for {student.name if student else 'the student'} was approved and sent.",
        "Fee reminder approved", "FEE_REMINDER_DECIDED", link="/coach/fee-reminders",
    )
    db.commit()
    return draft


@router.put("/{draft_id}/reject", response_model=FeeReminderDraftOut)
def reject_draft(
    draft_id: int,
    payload: FeeReminderDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    draft = db.query(FeeReminderDraft).filter(FeeReminderDraft.id == draft_id).first()
    if not draft:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reminder draft not found")
    if draft.status != ReminderDraftStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already decided")

    draft.status = ReminderDraftStatus.REJECTED
    draft.decision_note = payload.decision_note
    draft.approved_by_admin_id = current_user.id
    draft.decided_at = datetime.utcnow()

    log_action(db, current_user.id, "REJECT_FEE_REMINDER", "FeeReminderDraft", draft.id)
    db.commit()
    db.refresh(draft)

    coach = db.query(User).filter(User.id == draft.coach_id).first()
    notify_and_push(
        db, coach, f"Your fee reminder draft was rejected: {draft.decision_note or 'no reason given'}",
        "Fee reminder rejected", "FEE_REMINDER_DECIDED", link="/coach/fee-reminders",
    )
    db.commit()
    return draft
