from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.leave import CoachLeave, LeaveStatus
from app.schemas.leave import LeaveRequestCreate, LeaveDecision, LeaveUpdate, LeaveOut, LeaveAdminOut
from app.security import get_current_user, require_admin, require_coach
from app.services.audit import log_action
from app.services.notifications import notify_and_push

router = APIRouter(prefix="/leave", tags=["leave"])


@router.post("/request", response_model=LeaveOut, status_code=status.HTTP_201_CREATED)
def request_leave(
    payload: LeaveRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    if payload.end_date < payload.start_date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="end_date must be on/after start_date")

    leave = CoachLeave(
        coach_id=current_user.id,
        start_date=payload.start_date,
        end_date=payload.end_date,
        reason=payload.reason,
    )
    db.add(leave)
    db.flush()
    log_action(db, current_user.id, "REQUEST_LEAVE", "CoachLeave", leave.id)
    db.commit()
    db.refresh(leave)

    admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
    for admin in admins:
        notify_and_push(
            db, admin,
            f"{current_user.name} requested leave from {leave.start_date} to {leave.end_date}. Reason: {leave.reason or 'none given'}",
            "Leave request awaiting approval", "LEAVE_REQUEST_PENDING", link="/leave",
        )
    db.commit()
    return leave


@router.get("/my", response_model=List[LeaveOut])
def my_leaves(db: Session = Depends(get_db), current_user: User = Depends(require_coach)):
    return db.query(CoachLeave).filter(CoachLeave.coach_id == current_user.id).order_by(CoachLeave.created_at.desc()).all()


@router.get("/pending", response_model=List[LeaveOut])
def pending_leaves(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return (
        db.query(CoachLeave)
        .filter(CoachLeave.status == LeaveStatus.PENDING)
        .order_by(CoachLeave.created_at)
        .all()
    )


@router.get("", response_model=List[LeaveAdminOut])
def list_leaves(
    coach_id: Optional[int] = None,
    status_filter: Optional[LeaveStatus] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(CoachLeave)
    if coach_id:
        query = query.filter(CoachLeave.coach_id == coach_id)
    if status_filter:
        query = query.filter(CoachLeave.status == status_filter)

    leaves = query.order_by(CoachLeave.created_at.desc()).limit(500).all()
    coaches = {u.id: u.name for u in db.query(User).filter(User.id.in_([l.coach_id for l in leaves])).all()}
    return [
        LeaveAdminOut(
            id=l.id,
            coach_id=l.coach_id,
            coach_name=coaches.get(l.coach_id, "Unknown"),
            start_date=l.start_date,
            end_date=l.end_date,
            reason=l.reason,
            status=l.status,
            approved_by_admin_id=l.approved_by_admin_id,
            decision_note=l.decision_note,
            created_at=l.created_at,
        )
        for l in leaves
    ]


@router.put("/{leave_id}", response_model=LeaveOut)
def update_leave(
    leave_id: int,
    payload: LeaveUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    leave = db.query(CoachLeave).filter(CoachLeave.id == leave_id).first()
    if not leave:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Leave request not found")

    if current_user.role == "COACH":
        if leave.coach_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
        if leave.status != LeaveStatus.PENDING:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only pending requests can be edited")
    elif current_user.role != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    updates = payload.model_dump(exclude_unset=True)
    new_start = updates.get("start_date", leave.start_date)
    new_end = updates.get("end_date", leave.end_date)
    if new_end < new_start:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="end_date must be on/after start_date")

    for field, value in updates.items():
        setattr(leave, field, value)
    log_action(db, current_user.id, "UPDATE", "CoachLeave", leave.id)
    db.commit()
    db.refresh(leave)
    return leave


@router.delete("/{leave_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_leave(
    leave_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    leave = db.query(CoachLeave).filter(CoachLeave.id == leave_id).first()
    if not leave:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Leave request not found")

    if current_user.role == "COACH":
        if leave.coach_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
        if leave.status != LeaveStatus.PENDING:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only pending requests can be cancelled")
    elif current_user.role != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    log_action(db, current_user.id, "DELETE", "CoachLeave", leave.id)
    db.delete(leave)
    db.commit()


def _balance_check(db: Session, coach_id: int, year: int) -> int:
    """Return leave days already approved this calendar year (simple entitlement bookkeeping)."""
    approved = db.query(CoachLeave).filter(
        CoachLeave.coach_id == coach_id,
        CoachLeave.status == LeaveStatus.APPROVED,
    ).all()
    days = 0
    for leave in approved:
        if leave.start_date.year == year:
            days += (leave.end_date - leave.start_date).days + 1
    return days


@router.get("/balance/{coach_id}")
def leave_balance(
    coach_id: int,
    year: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.models.user import UserRole

    if current_user.role == "COACH" and current_user.id != coach_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    ANNUAL_ENTITLEMENT_DAYS = 18
    used = _balance_check(db, coach_id, year)
    return {"coach_id": coach_id, "year": year, "entitlement_days": ANNUAL_ENTITLEMENT_DAYS, "used_days": used, "remaining_days": max(ANNUAL_ENTITLEMENT_DAYS - used, 0)}


@router.put("/{leave_id}/approve", response_model=LeaveOut)
def approve_leave(
    leave_id: int,
    payload: LeaveDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    leave = db.query(CoachLeave).filter(CoachLeave.id == leave_id).first()
    if not leave:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Leave request not found")
    if leave.status != LeaveStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Leave request already decided")

    leave.status = LeaveStatus.APPROVED
    leave.approved_by_admin_id = current_user.id
    leave.decision_note = payload.note
    log_action(db, current_user.id, "APPROVE_LEAVE", "CoachLeave", leave.id)
    db.commit()
    db.refresh(leave)

    coach = db.query(User).filter(User.id == leave.coach_id).first()
    notify_and_push(
        db, coach, f"Your leave request ({leave.start_date} to {leave.end_date}) has been approved.",
        "Leave approved", "LEAVE_APPROVED", link="/coach/leave",
    )
    db.commit()
    return leave


@router.put("/{leave_id}/reject", response_model=LeaveOut)
def reject_leave(
    leave_id: int,
    payload: LeaveDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    leave = db.query(CoachLeave).filter(CoachLeave.id == leave_id).first()
    if not leave:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Leave request not found")
    if leave.status != LeaveStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Leave request already decided")

    leave.status = LeaveStatus.REJECTED
    leave.approved_by_admin_id = current_user.id
    leave.decision_note = payload.note
    log_action(db, current_user.id, "REJECT_LEAVE", "CoachLeave", leave.id)
    db.commit()
    db.refresh(leave)

    coach = db.query(User).filter(User.id == leave.coach_id).first()
    notify_and_push(
        db, coach, f"Your leave request ({leave.start_date} to {leave.end_date}) has been rejected.",
        "Leave rejected", "LEAVE_REJECTED", link="/coach/leave",
    )
    db.commit()
    return leave
