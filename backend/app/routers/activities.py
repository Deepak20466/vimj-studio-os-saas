from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from datetime import date, datetime

from app.database import get_db
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.attendance import StudentAttendance
from app.models.fee import StudentFee, FeeStatus
from app.schemas.activity import (
    ActivityCreate,
    ActivityUpdate,
    ActivityOut,
    ClassCreate,
    ClassUpdate,
    ClassOut,
    EnrollmentCreate,
    GroupPhotoUpload,
)
from app.security import get_current_user, require_admin, require_coach
from app.services.audit import log_action
from app.services.storage import save_class_photo

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


@router.put("/classes/{class_id}", response_model=ClassOut)
def update_class(
    class_id: int,
    payload: ClassUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    class_session = db.query(ClassSession).filter(ClassSession.id == class_id).first()
    if not class_session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")

    updates = payload.model_dump(exclude_unset=True)
    if "coach_id" in updates:
        coach = db.query(User).filter(User.id == updates["coach_id"], User.role == UserRole.COACH).first()
        if not coach:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Coach not found")
    for field, value in updates.items():
        setattr(class_session, field, value)

    log_action(db, current_user.id, "UPDATE", "Class", class_session.id)
    db.commit()
    db.refresh(class_session)
    return class_session


@router.delete("/classes/{class_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_class(
    class_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    class_session = db.query(ClassSession).filter(ClassSession.id == class_id).first()
    if not class_session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")

    log_action(db, current_user.id, "DELETE", "Class", class_session.id)
    db.delete(class_session)
    db.commit()


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


@router.get("/classes/{class_id}/summary")
def class_summary(
    class_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Enrolled/marked/fee counts for one class occurrence — shown on the coach dashboard so a
    coach can see how many students are expected, how many are marked, and paid/unpaid, at a glance."""
    cls = db.query(ClassSession).filter(ClassSession.id == class_id).first()
    if not cls:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    if current_user.role == UserRole.COACH and cls.coach_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your class")

    student_ids = [
        row[0]
        for row in db.query(StudentEnrollment.student_id).filter(StudentEnrollment.activity_id == cls.activity_id).all()
    ]
    enrolled_count = len(student_ids)
    marked_count = db.query(StudentAttendance).filter(StudentAttendance.class_id == class_id).count()

    today = date.today()
    fee_paid_count = 0
    fee_unpaid_count = enrolled_count
    if student_ids:
        paid_count = (
            db.query(StudentFee)
            .filter(
                StudentFee.student_id.in_(student_ids),
                StudentFee.month == today.month,
                StudentFee.year == today.year,
                StudentFee.status == FeeStatus.PAID,
            )
            .count()
        )
        fee_paid_count = paid_count
        fee_unpaid_count = enrolled_count - paid_count

    return {
        "class_id": class_id,
        "enrolled_count": enrolled_count,
        "marked_count": marked_count,
        "fee_paid_count": fee_paid_count,
        "fee_unpaid_count": fee_unpaid_count,
    }


@router.post("/classes/{class_id}/group-photo", response_model=ClassOut)
def upload_group_photo(
    class_id: int,
    payload: GroupPhotoUpload,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    """Coach captures one group photo covering the whole class roster, after the
    session has finished. Mobile coach app only — re-uploading replaces the photo."""
    cls = db.query(ClassSession).filter(ClassSession.id == class_id).first()
    if not cls:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    if cls.coach_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your class")

    class_end_dt = datetime.combine(cls.date, cls.end_time)
    if datetime.now() < class_end_dt:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The class hasn't finished yet")

    cls.group_photo = save_class_photo(payload.photo_base64)
    cls.group_photo_uploaded_at = datetime.now()
    log_action(db, current_user.id, "UPLOAD_GROUP_PHOTO", "Class", cls.id)
    db.commit()
    db.refresh(cls)
    return cls


@router.get("/classes/{class_id}/group-photo")
def get_group_photo(
    class_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cls = db.query(ClassSession).filter(ClassSession.id == class_id).first()
    if not cls or not cls.group_photo:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group photo not found")

    allowed = current_user.role == UserRole.ADMIN or current_user.id == cls.coach_id
    if not allowed:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this photo")

    return Response(content=cls.group_photo, media_type="image/jpeg")


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


@router.delete("/enroll/{enrollment_id}", status_code=status.HTTP_204_NO_CONTENT)
def unenroll_student(
    enrollment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    enrollment = db.query(StudentEnrollment).filter(StudentEnrollment.id == enrollment_id).first()
    if not enrollment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Enrollment not found")

    log_action(db, current_user.id, "DELETE", "Enrollment", enrollment.id)
    db.delete(enrollment)
    db.commit()


@router.get("/{activity_id}/roster")
def activity_roster(
    activity_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role == UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
    rows = (
        db.query(User, StudentEnrollment.id)
        .join(StudentEnrollment, StudentEnrollment.student_id == User.id)
        .filter(StudentEnrollment.activity_id == activity_id)
        .all()
    )
    today = date.today()
    student_ids = [s.id for s, _ in rows]
    fees_by_student = {
        f.student_id: f.status.value
        for f in db.query(StudentFee)
        .filter(StudentFee.student_id.in_(student_ids), StudentFee.month == today.month, StudentFee.year == today.year)
        .all()
    } if student_ids else {}
    return [
        {
            "id": s.id,
            "name": s.name,
            "email": s.email,
            "enrollment_id": enrollment_id,
            "fee_status": fees_by_student.get(s.id, "UNPAID"),
        }
        for s, enrollment_id in rows
    ]
