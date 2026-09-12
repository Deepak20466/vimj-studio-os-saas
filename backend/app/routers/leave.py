from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.leave import CoachLeave, LeaveStatus
from app.schemas.leave import LeaveRequestCreate, LeaveDecision, LeaveOut, LeaveAdminOut
from app.security import require_admin, require_coach, require_admin_or_coach
from app.services.audit import log_action
from app.services.notifications import notify_and_push

router = APIRouter(prefix="/leave", tags=["leave"])


def _to_admin_out(db: Session, records: List[CoachLeave]) -> List[LeaveAdminOut]:
    coach_ids = {r.coach_id for r in records}
    names = {u.id: u.name for u in db.query(User).filter(User.id.in_(coach_ids)).all()} if coach_ids else {}
    return [
        LeaveAdminOut(
            id=r.id,
            coach_id=r.coach_id,
            coach_name=names.get(r.coach_id, "Unknown"),
            start_date=r.start_date,
            end_date=r.end_date,
            reason=r.reason,
            status=r.status,
            decision_note=r.decision_note,
            created_at=r.created_at,
        )
        for r in records
    ]


@router.post("/request", response_model=LeaveOut, status_code=status.HTTP_201_CREATED)
def request_leave(
    payload: LeaveRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    record = CoachLeave(
        coach_id=current_user.id,
        start_date=payload.start_date,
        end_date=payload.end_date,
        reason=payload.reason,
    )
    db.add(record)
    db.flush()
    log_action(db, current_user.id, "CREATE", "CoachLeave", record.id)
    db.commit()
    db.refresh(record)

    admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
    for admin in admins:
        notify_and_push(
            db, admin,
            f"{current_user.name} requested leave from {record.start_date} to {record.end_date}.",
            "Leave request awaiting approval", "LEAVE_PENDING", link="/leave",
        )
    db.commit()
    return record


@router.get("/my", response_model=List[LeaveOut])
def my_leaves(db: Session = Depends(get_db), current_user: User = Depends(require_coach)):
    return (
        db.query(CoachLeave)
        .filter(CoachLeave.coach_id == current_user.id)
        .order_by(CoachLeave.created_at.desc())
        .all()
    )


@router.delete("/{leave_id}", status_code=status.HTTP_204_NO_CONTENT)
def cancel_leave(
    leave_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    record = db.query(CoachLeave).filter(CoachLeave.id == leave_id, CoachLeave.coach_id == current_user.id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Leave request not found")
    if record.status != LeaveStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only a pending request can be cancelled")

    log_action(db, current_user.id, "DELETE", "CoachLeave", record.id)
    db.delete(record)
    db.commit()


@router.get("/pending", response_model=List[LeaveAdminOut])
def pending_leaves(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    records = (
        db.query(CoachLeave)
        .filter(CoachLeave.status == LeaveStatus.PENDING)
        .order_by(CoachLeave.created_at)
        .all()
    )
    return _to_admin_out(db, records)


@router.get("", response_model=List[LeaveAdminOut])
def list_leaves(
    status_filter: Optional[LeaveStatus] = None,
    coach_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(CoachLeave)
    if status_filter:
        query = query.filter(CoachLeave.status == status_filter)
    if coach_id:
        query = query.filter(CoachLeave.coach_id == coach_id)
    records = query.order_by(CoachLeave.created_at.desc()).limit(500).all()
    return _to_admin_out(db, records)


@router.put("/{leave_id}/approve", response_model=LeaveOut)
def approve_leave(
    leave_id: int,
    payload: LeaveDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(CoachLeave).filter(CoachLeave.id == leave_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Leave request not found")
    if record.status != LeaveStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Leave request already decided")

    record.status = LeaveStatus.APPROVED
    record.decision_note = payload.note
    record.approved_by_admin_id = current_user.id

    log_action(db, current_user.id, "APPROVE_LEAVE", "CoachLeave", record.id)
    db.commit()
    db.refresh(record)

    coach = db.query(User).filter(User.id == record.coach_id).first()
    notify_and_push(
        db, coach,
        f"Your leave request ({record.start_date} to {record.end_date}) was approved.",
        "Leave approved", "LEAVE_DECIDED", link="/coach/leave",
    )
    db.commit()
    return record


@router.put("/{leave_id}/reject", response_model=LeaveOut)
def reject_leave(
    leave_id: int,
    payload: LeaveDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(CoachLeave).filter(CoachLeave.id == leave_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Leave request not found")
    if record.status != LeaveStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Leave request already decided")

    record.status = LeaveStatus.REJECTED
    record.decision_note = payload.note
    record.approved_by_admin_id = current_user.id

    log_action(db, current_user.id, "REJECT_LEAVE", "CoachLeave", record.id)
    db.commit()
    db.refresh(record)

    coach = db.query(User).filter(User.id == record.coach_id).first()
    notify_and_push(
        db, coach,
        f"Your leave request ({record.start_date} to {record.end_date}) was rejected"
        + (f": {record.decision_note}" if record.decision_note else "."),
        "Leave rejected", "LEAVE_DECIDED", link="/coach/leave",
    )
    db.commit()
    return record
