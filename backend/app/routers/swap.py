from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.class_session import ClassSession
from app.models.swap import CoachSwap, SwapStatus
from app.schemas.swap import SwapRequestCreate, SwapOut
from app.security import get_current_user, require_admin, require_coach
from app.services.audit import log_action
from app.services.notifications import notify

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
        date=payload.date,
    )
    db.add(swap)
    db.flush()
    log_action(db, current_user.id, "REQUEST_SWAP", "CoachSwap", swap.id)
    db.commit()
    db.refresh(swap)
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
    log_action(db, current_user.id, "APPROVE_SWAP", "CoachSwap", swap.id)
    db.commit()
    db.refresh(swap)

    covering = db.query(User).filter(User.id == swap.covering_coach_id).first()
    if covering and covering.phone:
        notify(covering.phone, f"You are now covering a class on {swap.date}.")
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
