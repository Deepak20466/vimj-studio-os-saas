from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.batch import Batch
from app.models.class_session import ClassSession
from app.models.swap import CoachSwap, SwapStatus
from app.schemas.swap import SwapRequestCreate, AdminAssignSwap, SwapOut, SwapRecentOut
from app.security import get_current_user, require_admin, require_coach
from app.services.audit import log_action
from app.services.notifications import notify_and_push

router = APIRouter(prefix="/swap", tags=["swap"])


@router.post("/request", response_model=SwapOut, status_code=status.HTTP_201_CREATED)
def request_swap(
    payload: SwapRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    class_session = db.query(ClassSession).filter(ClassSession.id == payload.class_id).first()
    if not class_session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    if class_session.coach_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not assigned to this class")

    covering_coach = db.query(User).filter(User.id == payload.covering_coach_id, User.role == UserRole.COACH).first()
    if not covering_coach:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Covering coach not found")

    swap = CoachSwap(
        original_coach_id=current_user.id,
        covering_coach_id=payload.covering_coach_id,
        class_id=payload.class_id,
        batch_id=class_session.batch_id,
        date=payload.date,
        reason=payload.reason,
    )
    db.add(swap)
    db.flush()
    log_action(db, current_user.id, "REQUEST_SWAP", "CoachSwap", swap.id)
    db.commit()
    db.refresh(swap)
    return swap


@router.post("/admin-assign", response_model=SwapOut, status_code=status.HTTP_201_CREATED)
def admin_assign_swap(
    payload: AdminAssignSwap,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Admin directly reassigns a class to a substitute coach, auto-approved.

    Accepts either an existing `class_id` (the reactive "missing attendance" flow) or a
    `batch_id` + `date` (the proactive flow: pick a coach's recurring batch and a date that
    may not have a generated `ClassSession` yet — one is created on the fly from the batch's
    activity/time, mirroring `POST /batches/{id}/generate-sessions` for a single date).
    """
    if not payload.class_id and not payload.batch_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Provide either class_id or batch_id")

    if payload.class_id:
        class_session = db.query(ClassSession).filter(ClassSession.id == payload.class_id).first()
        if not class_session:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    else:
        batch = db.query(Batch).filter(Batch.id == payload.batch_id).first()
        if not batch:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Batch not found")
        class_session = (
            db.query(ClassSession)
            .filter(ClassSession.batch_id == batch.id, ClassSession.date == payload.date)
            .first()
        )
        if not class_session:
            class_session = ClassSession(
                activity_id=batch.activity_id,
                coach_id=payload.original_coach_id,
                batch_id=batch.id,
                date=payload.date,
                start_time=batch.start_time,
                end_time=batch.end_time,
            )
            db.add(class_session)
            db.flush()

    original = db.query(User).filter(User.id == payload.original_coach_id, User.role == UserRole.COACH).first()
    if not original:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Original coach not found")
    covering = db.query(User).filter(User.id == payload.covering_coach_id, User.role == UserRole.COACH).first()
    if not covering:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Substitute coach not found")

    swap = CoachSwap(
        original_coach_id=payload.original_coach_id,
        covering_coach_id=payload.covering_coach_id,
        class_id=class_session.id,
        batch_id=class_session.batch_id,
        date=payload.date,
        reason=payload.reason,
        status=SwapStatus.APPROVED,
    )
    db.add(swap)

    # Take effect immediately: the covering coach now owns this class occurrence, so it shows
    # up in their "Today's Classes" / classes-my query right away, not just in the swap log.
    class_session.coach_id = covering.id

    db.flush()
    log_action(db, current_user.id, "ADMIN_ASSIGN_SWAP", "CoachSwap", swap.id)
    db.commit()
    db.refresh(swap)

    notify_and_push(
        db,
        covering,
        f"You have been assigned to cover a class on {swap.date}. Reason: {swap.reason}",
        "New class assigned",
        "SWAP_ASSIGNED",
    )
    notify_and_push(
        db,
        original,
        f"You have been reassigned off your class on {swap.date}; {covering.name} is now covering it.",
        "Class reassigned",
        "SWAP_REASSIGNED_OFF",
    )
    db.commit()
    return swap


@router.get("/my", response_model=List[SwapOut])
def my_swaps(db: Session = Depends(get_db), current_user: User = Depends(require_coach)):
    return (
        db.query(CoachSwap)
        .filter(
            (CoachSwap.original_coach_id == current_user.id)
            | (CoachSwap.covering_coach_id == current_user.id)
        )
        .order_by(CoachSwap.created_at.desc())
        .all()
    )


@router.get("/pending", response_model=List[SwapOut])
def pending_swaps(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return db.query(CoachSwap).filter(CoachSwap.status == SwapStatus.PENDING).order_by(CoachSwap.created_at).all()


@router.get("/recent", response_model=List[SwapRecentOut])
def recent_swaps(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    """The most recent reassignments (any status), newest first, for admin visibility."""
    swaps = db.query(CoachSwap).order_by(CoachSwap.created_at.desc()).limit(20).all()
    if not swaps:
        return []

    coach_ids = {s.original_coach_id for s in swaps} | {s.covering_coach_id for s in swaps}
    coach_names = {u.id: u.name for u in db.query(User).filter(User.id.in_(coach_ids)).all()}

    class_ids = {s.class_id for s in swaps}
    classes = {c.id: c for c in db.query(ClassSession).filter(ClassSession.id.in_(class_ids)).all()}
    activity_ids = {c.activity_id for c in classes.values()}
    from app.models.activity import Activity

    activity_names = {a.id: a.name for a in db.query(Activity).filter(Activity.id.in_(activity_ids)).all()}

    result = []
    for s in swaps:
        cls = classes.get(s.class_id)
        activity_name = activity_names.get(cls.activity_id, "Unknown") if cls else "Unknown"
        result.append(
            SwapRecentOut(
                id=s.id,
                original_coach_id=s.original_coach_id,
                covering_coach_id=s.covering_coach_id,
                class_id=s.class_id,
                batch_id=s.batch_id,
                date=s.date,
                reason=s.reason,
                status=s.status,
                created_at=s.created_at,
                original_coach_name=coach_names.get(s.original_coach_id, "Unknown"),
                covering_coach_name=coach_names.get(s.covering_coach_id, "Unknown"),
                activity_name=activity_name,
            )
        )
    return result


@router.put("/{swap_id}/approve", response_model=SwapOut)
def approve_swap(
    swap_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    swap = db.query(CoachSwap).filter(CoachSwap.id == swap_id).first()
    if not swap:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Swap request not found")
    if swap.status != SwapStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Swap request already decided")

    swap.status = SwapStatus.APPROVED

    class_session = db.query(ClassSession).filter(ClassSession.id == swap.class_id).first()
    if class_session:
        class_session.coach_id = swap.covering_coach_id

    log_action(db, current_user.id, "APPROVE_SWAP", "CoachSwap", swap.id)
    db.commit()
    db.refresh(swap)

    covering = db.query(User).filter(User.id == swap.covering_coach_id).first()
    original = db.query(User).filter(User.id == swap.original_coach_id).first()
    notify_and_push(db, covering, f"You are now covering a class on {swap.date}.", "Swap approved", "SWAP_ASSIGNED")
    notify_and_push(
        db,
        original,
        f"Your swap request for {swap.date} was approved; {covering.name if covering else 'the covering coach'} is now covering it.",
        "Swap approved",
        "SWAP_REASSIGNED_OFF",
    )
    db.commit()
    return swap


@router.put("/{swap_id}/reject", response_model=SwapOut)
def reject_swap(
    swap_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    swap = db.query(CoachSwap).filter(CoachSwap.id == swap_id).first()
    if not swap:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Swap request not found")
    if swap.status != SwapStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Swap request already decided")

    swap.status = SwapStatus.REJECTED
    log_action(db, current_user.id, "REJECT_SWAP", "CoachSwap", swap.id)
    db.commit()
    db.refresh(swap)
    return swap
