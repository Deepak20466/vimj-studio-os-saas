from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.attendance import StudentAttendance
from app.models.fee import StudentFee
from app.schemas.user import UserCreate, UserOut, UserUpdate
from app.schemas.attendance import StudentAttendanceOut
from app.schemas.fee import FeeOut
from app.security import get_current_user, require_admin, hash_password
from app.services.audit import log_action

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
    payload: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    student = User(
        email=payload.email,
        password_hash=hash_password(payload.password),
        name=payload.name,
        phone=payload.phone,
        role=UserRole.STUDENT,
    )
    db.add(student)
    db.flush()
    log_action(db, current_user.id, "CREATE", "Student", student.id)
    db.commit()
    db.refresh(student)
    return student


@router.put("/{student_id}", response_model=UserOut)
def update_student(
    student_id: int,
    payload: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    student = db.query(User).filter(User.id == student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")

    for field in ("name", "phone", "is_active"):
        value = getattr(payload, field)
        if value is not None:
            setattr(student, field, value)
    if payload.password:
        student.password_hash = hash_password(payload.password)

    log_action(db, current_user.id, "UPDATE", "Student", student.id)
    db.commit()
    db.refresh(student)
    return student


@router.delete("/{student_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_student(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    student = db.query(User).filter(User.id == student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
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
