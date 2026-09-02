from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.schemas.activity import (
    ActivityCreate,
    ActivityUpdate,
    ActivityOut,
    ClassCreate,
    ClassOut,
    EnrollmentCreate,
)
from app.security import get_current_user, require_admin
from app.services.audit import log_action

router = APIRouter(prefix="/activities", tags=["activities"])


@router.get("", response_model=List[ActivityOut])
def list_activities(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Activity).order_by(Activity.name).all()


@router.post("", response_model=ActivityOut, status_code=status.HTTP_201_CREATED)
def create_activity(
    payload: ActivityCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    activity = Activity(**payload.model_dump())
    db.add(activity)
    db.flush()
    log_action(db, current_user.id, "CREATE", "Activity", activity.id)
    db.commit()
    db.refresh(activity)
    return activity


@router.put("/{activity_id}", response_model=ActivityOut)
def update_activity(
    activity_id: int,
    payload: ActivityUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    activity = db.query(Activity).filter(Activity.id == activity_id).first()
    if not activity:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Activity not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(activity, field, value)
    log_action(db, current_user.id, "UPDATE", "Activity", activity.id)
    db.commit()
    db.refresh(activity)
    return activity


@router.delete("/{activity_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_activity(
    activity_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    activity = db.query(Activity).filter(Activity.id == activity_id).first()
    if not activity:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Activity not found")
    log_action(db, current_user.id, "DELETE", "Activity", activity.id)
    db.delete(activity)
    db.commit()


@router.get("/{activity_id}/classes", response_model=List[ClassOut])
def list_classes_for_activity(
    activity_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(ClassSession).filter(ClassSession.activity_id == activity_id)
    if current_user.role == UserRole.COACH:
        query = query.filter(ClassSession.coach_id == current_user.id)
    return query.order_by(ClassSession.date.desc()).all()


@router.post("/classes", response_model=ClassOut, status_code=status.HTTP_201_CREATED)
def create_class(
    payload: ClassCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    coach = db.query(User).filter(User.id == payload.coach_id, User.role == UserRole.COACH).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Coach not found")
    activity = db.query(Activity).filter(Activity.id == payload.activity_id).first()
    if not activity:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Activity not found")

    class_session = ClassSession(**payload.model_dump())
    db.add(class_session)
    db.flush()
    log_action(db, current_user.id, "CREATE", "Class", class_session.id)
    db.commit()
    db.refresh(class_session)
    return class_session


@router.get("/classes/my", response_model=List[ClassOut])
def my_classes(
    class_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.COACH:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only coaches have a class list")
    query = db.query(ClassSession).filter(ClassSession.coach_id == current_user.id)
    if class_date:
        query = query.filter(ClassSession.date == class_date)
    return query.order_by(ClassSession.date.desc(), ClassSession.start_time).all()


@router.post("/enroll", status_code=status.HTTP_201_CREATED)
def enroll_student(
    payload: EnrollmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    student = db.query(User).filter(User.id == payload.student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Student not found")
    activity = db.query(Activity).filter(Activity.id == payload.activity_id).first()
    if not activity:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Activity not found")

    existing = (
        db.query(StudentEnrollment)
        .filter(
            StudentEnrollment.student_id == payload.student_id,
            StudentEnrollment.activity_id == payload.activity_id,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Student already enrolled")

    enrollment = StudentEnrollment(**payload.model_dump())
    db.add(enrollment)
    log_action(db, current_user.id, "CREATE", "Enrollment", None)
    db.commit()
    return {"detail": "Student enrolled"}


@router.get("/{activity_id}/roster")
def activity_roster(
    activity_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role == UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
    students = (
        db.query(User)
        .join(StudentEnrollment, StudentEnrollment.student_id == User.id)
        .filter(StudentEnrollment.activity_id == activity_id)
        .all()
    )
    return [{"id": s.id, "name": s.name, "email": s.email} for s in students]
