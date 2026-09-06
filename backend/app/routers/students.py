import secrets
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, UserDetails
from app.models.activity import Activity
from app.models.coach_activity import CoachActivity
from app.models.enrollment import StudentEnrollment
from app.models.attendance import StudentAttendance
from app.models.fee import StudentFee
from app.schemas.user import StudentCreate, UserOut, UserUpdate
from app.schemas.attendance import StudentAttendanceOut
from app.schemas.fee import FeeOut
from app.security import get_current_user, require_admin, require_admin_or_coach, hash_password
from app.services.audit import log_action
from app.services.storage import save_student_photo, read_student_photo

router = APIRouter(prefix="/students", tags=["students"])


def _assert_self_or_admin(current_user: User, student_id: int):
    if current_user.role == UserRole.ADMIN:
        return
    if current_user.role == UserRole.STUDENT and current_user.id == student_id:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this student's data")


@router.get("", response_model=List[UserOut])
def list_students(
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(User).filter(User.role == UserRole.STUDENT)
    if search:
        like = f"%{search}%"
        query = query.filter((User.name.ilike(like)) | (User.email.ilike(like)))
    return query.order_by(User.name).all()


@router.post("", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def create_student(
    payload: StudentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    email = payload.email or f"student.{uuid.uuid4().hex[:12]}@no-login.internal"
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    activity_id = payload.activity_id
    if current_user.role == UserRole.COACH:
        if not activity_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="activity_id is required")
        linked = (
            db.query(CoachActivity)
            .filter(CoachActivity.coach_id == current_user.id, CoachActivity.activity_id == activity_id)
            .first()
        )
        if not linked:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not assigned to this activity")
    elif activity_id:
        activity = db.query(Activity).filter(Activity.id == activity_id).first()
        if not activity:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Activity not found")

    student = User(
        email=email,
        password_hash=hash_password(payload.password or secrets.token_urlsafe(18)),
        name=payload.name,
        phone=payload.phone,
        phone_secondary=payload.phone_secondary,
        role=UserRole.STUDENT,
    )
    db.add(student)
    db.flush()

    if payload.additional_details:
        db.add(UserDetails(user_id=student.id, additional_details=payload.additional_details))

    if activity_id:
        db.add(StudentEnrollment(student_id=student.id, activity_id=activity_id))

    log_action(db, current_user.id, "CREATE", "Student", student.id)
    db.commit()
    db.refresh(student)
    return student


@router.put("/{student_id}", response_model=UserOut)
def update_student(
    student_id: int,
    payload: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    student = db.query(User).filter(User.id == student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    _assert_may_manage_student(db, current_user, student_id)

    # A coach may only correct contact details for their own roster; deactivating a
    # student's account or resetting their password stays admin-only.
    fields = ("name", "phone", "phone_secondary") if current_user.role == UserRole.COACH else ("name", "phone", "phone_secondary", "is_active")
    for field in fields:
        value = getattr(payload, field)
        if value is not None:
            setattr(student, field, value)
    if payload.password and current_user.role == UserRole.ADMIN:
        student.password_hash = hash_password(payload.password)

    log_action(db, current_user.id, "UPDATE", "Student", student.id)
    db.commit()
    db.refresh(student)
    return student


@router.delete("/{student_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_student(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    student = db.query(User).filter(User.id == student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    _assert_may_manage_student(db, current_user, student_id)
    log_action(db, current_user.id, "DELETE", "Student", student.id)
    db.delete(student)
    db.commit()


@router.get("/{student_id}/attendance", response_model=List[StudentAttendanceOut])
def student_attendance(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_self_or_admin(current_user, student_id)
    return (
        db.query(StudentAttendance)
        .filter(StudentAttendance.student_id == student_id)
        .order_by(StudentAttendance.timestamp.desc())
        .all()
    )


@router.get("/{student_id}/fees", response_model=List[FeeOut])
def student_fees(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_self_or_admin(current_user, student_id)
    return (
        db.query(StudentFee)
        .filter(StudentFee.student_id == student_id)
        .order_by(StudentFee.year.desc(), StudentFee.month.desc())
        .all()
    )


def _assert_may_manage_student(db: Session, current_user: User, student_id: int) -> None:
    """Admin may manage any student; a coach may manage a student enrolled in one of the coach's own activities."""
    if current_user.role == UserRole.ADMIN:
        return
    if current_user.role == UserRole.COACH:
        student_activity_ids = {
            row[0]
            for row in db.query(StudentEnrollment.activity_id).filter(StudentEnrollment.student_id == student_id).all()
        }
        coach_activity_ids = {
            row[0] for row in db.query(CoachActivity.activity_id).filter(CoachActivity.coach_id == current_user.id).all()
        }
        if student_activity_ids & coach_activity_ids:
            return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to manage this student")


@router.post("/{student_id}/photo")
def upload_student_photo(
    student_id: int,
    payload: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    student = db.query(User).filter(User.id == student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    _assert_may_manage_student(db, current_user, student_id)

    photo_base64 = payload.get("photo_base64")
    if not photo_base64:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="photo_base64 is required")

    photo_path = save_student_photo(photo_base64, student_id)
    details = db.query(UserDetails).filter(UserDetails.user_id == student_id).first()
    if not details:
        details = UserDetails(user_id=student_id)
        db.add(details)
    details.profile_photo = photo_path

    log_action(db, current_user.id, "UPLOAD_STUDENT_PHOTO", "Student", student_id)
    db.commit()
    return {"detail": "Photo uploaded"}


@router.get("/{student_id}/photo")
def get_student_photo(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.COACH:
        _assert_self_or_admin(current_user, student_id)
    details = db.query(UserDetails).filter(UserDetails.user_id == student_id).first()
    if not details or not details.profile_photo:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No photo on file")
    image_bytes = read_student_photo(details.profile_photo)
    return Response(content=image_bytes, media_type="image/jpeg")
