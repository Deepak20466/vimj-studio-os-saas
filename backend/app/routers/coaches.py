from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.attendance import CoachAttendance
from app.models.coach_activity import CoachActivity
from app.models.salary import CoachSalary
from app.schemas.user import UserCreate, UserOut, UserUpdate
from app.schemas.attendance import CoachAttendanceOut
from app.schemas.salary import SalaryOut
from app.schemas.coach_activity import CoachActivitiesSet, CoachActivityOut
from app.security import get_current_user, require_admin, require_coach, hash_password
from app.services.audit import log_action

router = APIRouter(prefix="/coaches", tags=["coaches"])


def _assert_self_or_admin(current_user: User, coach_id: int):
    if current_user.role == UserRole.ADMIN:
        return
    if current_user.role == UserRole.COACH and current_user.id == coach_id:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this coach's data")


@router.get("/directory")
def coach_directory(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    """Minimal name/id list of other active coaches, used to pick a covering coach for a swap.

    Deliberately excludes attendance, salary, and any other coach-private data.
    """
    coaches = (
        db.query(User)
        .filter(User.role == UserRole.COACH, User.is_active.is_(True), User.id != current_user.id)
        .order_by(User.name)
        .all()
    )
    return [{"id": c.id, "name": c.name} for c in coaches]


@router.get("", response_model=List[UserOut])
def list_coaches(
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(User).filter(User.role == UserRole.COACH)
    if search:
        like = f"%{search}%"
        query = query.filter((User.name.ilike(like)) | (User.email.ilike(like)))
    return query.order_by(User.name).all()


@router.post("", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def create_coach(
    payload: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    coach = User(
        email=payload.email,
        password_hash=hash_password(payload.password),
        name=payload.name,
        phone=payload.phone,
        role=UserRole.COACH,
    )
    db.add(coach)
    db.flush()
    log_action(db, current_user.id, "CREATE", "Coach", coach.id)
    db.commit()
    db.refresh(coach)
    return coach


@router.put("/{coach_id}", response_model=UserOut)
def update_coach(
    coach_id: int,
    payload: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    coach = db.query(User).filter(User.id == coach_id, User.role == UserRole.COACH).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach not found")

    if payload.email and payload.email != coach.email:
        if db.query(User).filter(User.email == payload.email, User.id != coach_id).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
        coach.email = payload.email

    for field in ("name", "phone", "phone_secondary", "is_active"):
        value = getattr(payload, field)
        if value is not None:
            setattr(coach, field, value)
    if payload.password:
        coach.password_hash = hash_password(payload.password)

    log_action(db, current_user.id, "UPDATE", "Coach", coach.id)
    db.commit()
    db.refresh(coach)
    return coach


@router.delete("/{coach_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_coach(
    coach_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    coach = db.query(User).filter(User.id == coach_id, User.role == UserRole.COACH).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach not found")
    log_action(db, current_user.id, "DELETE", "Coach", coach.id)
    db.delete(coach)
    db.commit()


@router.get("/{coach_id}/attendance", response_model=List[CoachAttendanceOut])
def coach_attendance(
    coach_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_self_or_admin(current_user, coach_id)
    return (
        db.query(CoachAttendance)
        .filter(CoachAttendance.coach_id == coach_id)
        .order_by(CoachAttendance.date.desc())
        .all()
    )


@router.get("/{coach_id}/salary", response_model=List[SalaryOut])
def coach_salary(
    coach_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_self_or_admin(current_user, coach_id)
    return (
        db.query(CoachSalary)
        .filter(CoachSalary.coach_id == coach_id)
        .order_by(CoachSalary.year.desc(), CoachSalary.month.desc())
        .all()
    )


@router.get("/{coach_id}/activities", response_model=List[CoachActivityOut])
def get_coach_activities(
    coach_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_self_or_admin(current_user, coach_id)
    rows = (
        db.query(Activity)
        .join(CoachActivity, CoachActivity.activity_id == Activity.id)
        .filter(CoachActivity.coach_id == coach_id)
        .all()
    )
    return [CoachActivityOut(activity_id=a.id, activity_name=a.name) for a in rows]


@router.put("/{coach_id}/activities", response_model=List[CoachActivityOut])
def set_coach_activities(
    coach_id: int,
    payload: CoachActivitiesSet,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    coach = db.query(User).filter(User.id == coach_id, User.role == UserRole.COACH).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach not found")

    valid_ids = {
        row[0] for row in db.query(Activity.id).filter(Activity.id.in_(payload.activity_ids)).all()
    }
    if len(valid_ids) != len(set(payload.activity_ids)):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="One or more activities not found")

    db.query(CoachActivity).filter(CoachActivity.coach_id == coach_id).delete()
    for activity_id in valid_ids:
        db.add(CoachActivity(coach_id=coach_id, activity_id=activity_id))

    log_action(db, current_user.id, "SET_ACTIVITIES", "Coach", coach_id)
    db.commit()

    rows = (
        db.query(Activity)
        .join(CoachActivity, CoachActivity.activity_id == Activity.id)
        .filter(CoachActivity.coach_id == coach_id)
        .all()
    )
    return [CoachActivityOut(activity_id=a.id, activity_name=a.name) for a in rows]
