from datetime import date as date_type, datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.attendance import (
    StudentAttendance,
    AttendanceStatus,
    CoachAttendance,
    CoachAttendanceStatus,
)
from app.models.leave import CoachLeave, LeaveStatus
from app.models.swap import CoachSwap, SwapStatus
from app.models.compliance import AttendanceSubmission, LateStatus
from app.schemas.attendance import (
    MarkStudentAttendanceRequest,
    ManualAttendanceRequest,
    StudentAttendanceOut,
    StudentAttendanceUpdate,
    StudentAttendanceAdminOut,
    CoachEntryExitRequest,
    CoachAttendanceOut,
    MissingCoachOut,
)
from app.security import get_current_user, require_admin, require_coach, require_admin_or_coach
from app.services.geofence import is_within_geofence
from app.services.storage import save_selfie, read_selfie
from app.services.audit import log_action

router = APIRouter(prefix="/attendance", tags=["attendance"])

# How long after a class ends a coach is still allowed to mark attendance for it.
MARK_DEADLINE_MINUTES = 60
# Beyond this, a mark is considered "late" and needs a reason + admin approval.
LATE_MARK_MINUTES = 10


def _get_or_create_submission(db: Session, class_session: ClassSession, coach_id: int, late_reason: Optional[str]) -> AttendanceSubmission:
    """First attendance mark for a class records the submission.

    Marking itself is never blocked by lateness (that would break the existing mark
    flow, including the mobile app, for marks made within the existing 60-minute
    MARK_DEADLINE_MINUTES window). If the mark is late, it's flagged for admin
    review; the coach can supply/confirm the reason immediately via late_reason on
    this request, or afterwards via POST /compliance/late-reason.
    """
    submission = db.query(AttendanceSubmission).filter(AttendanceSubmission.class_id == class_session.id).first()
    if submission:
        return submission

    class_end_dt = datetime.combine(class_session.date, class_session.end_time)
    is_late = datetime.now() > class_end_dt + timedelta(minutes=LATE_MARK_MINUTES)

    submission = AttendanceSubmission(
        class_id=class_session.id,
        coach_id=coach_id,
        submitted_at=datetime.now(),
        is_late=is_late,
        late_reason=late_reason if is_late else None,
        late_status=LateStatus.PENDING if (is_late and late_reason) else LateStatus.NONE,
    )
    db.add(submission)
    db.flush()
    return submission


def _coach_is_on_leave(db: Session, coach_id: int, on_date) -> bool:
    return (
        db.query(CoachLeave)
        .filter(
            CoachLeave.coach_id == coach_id,
            CoachLeave.status == LeaveStatus.APPROVED,
            CoachLeave.start_date <= on_date,
            CoachLeave.end_date >= on_date,
        )
        .first()
        is not None
    )


def _resolve_marking_coach(db: Session, class_session: ClassSession, current_user: User) -> int:
    """Return the coach_id allowed to mark this class: the assigned coach, or an approved swap covering coach."""
    if current_user.id == class_session.coach_id:
        if _coach_is_on_leave(db, current_user.id, class_session.date):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are on approved leave and cannot mark attendance for this class",
            )
        return current_user.id

    swap = (
        db.query(CoachSwap)
        .filter(
            CoachSwap.class_id == class_session.id,
            CoachSwap.covering_coach_id == current_user.id,
            CoachSwap.status == SwapStatus.APPROVED,
        )
        .first()
    )
    if swap:
        return current_user.id

    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not assigned to this class")


@router.post("/mark-student", response_model=StudentAttendanceOut, status_code=status.HTTP_201_CREATED)
def mark_student_attendance(
    payload: MarkStudentAttendanceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    class_session = db.query(ClassSession).filter(ClassSession.id == payload.class_id).first()
    if not class_session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")

    coach_id = _resolve_marking_coach(db, class_session, current_user)

    class_end_dt = datetime.combine(class_session.date, class_session.end_time)
    if datetime.now() > class_end_dt + timedelta(minutes=MARK_DEADLINE_MINUTES):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Attendance marking deadline has passed for this class",
        )

    enrolled = (
        db.query(StudentEnrollment)
        .filter(
            StudentEnrollment.student_id == payload.student_id,
            StudentEnrollment.activity_id == class_session.activity_id,
        )
        .first()
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Student is not enrolled in this activity")

    if not is_within_geofence(float(payload.location_lat), float(payload.location_lng)):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You must be within the facility geofence to mark attendance",
        )

    existing = (
        db.query(StudentAttendance)
        .filter(
            StudentAttendance.student_id == payload.student_id,
            StudentAttendance.class_id == payload.class_id,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attendance already marked for this student")

    _get_or_create_submission(db, class_session, coach_id, payload.late_reason)

    selfie_path = None
    if payload.status == AttendanceStatus.PRESENT:
        if not payload.selfie_base64:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Selfie is required to mark present")
        selfie_path = save_selfie(payload.selfie_base64, payload.student_id)

    record = StudentAttendance(
        student_id=payload.student_id,
        class_id=payload.class_id,
        status=payload.status,
        coach_id=coach_id,
        location_lat=payload.location_lat,
        location_lng=payload.location_lng,
        selfie_photo=selfie_path,
    )
    db.add(record)
    db.flush()
    log_action(db, current_user.id, "MARK_ATTENDANCE", "StudentAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.post("/mark-student/manual", response_model=StudentAttendanceOut, status_code=status.HTTP_201_CREATED)
def mark_student_attendance_manual(
    payload: ManualAttendanceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Admin manual entry: bypasses geofence and selfie requirements."""
    class_session = db.query(ClassSession).filter(ClassSession.id == payload.class_id).first()
    if not class_session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")

    existing = (
        db.query(StudentAttendance)
        .filter(
            StudentAttendance.student_id == payload.student_id,
            StudentAttendance.class_id == payload.class_id,
        )
        .first()
    )
    if existing:
        existing.status = payload.status
        existing.coach_id = class_session.coach_id
        record = existing
    else:
        record = StudentAttendance(
            student_id=payload.student_id,
            class_id=payload.class_id,
            status=payload.status,
            coach_id=class_session.coach_id,
            marked_manually=1,
        )
        db.add(record)

    db.flush()
    log_action(db, current_user.id, "MANUAL_MARK_ATTENDANCE", "StudentAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.post("/coach-entry", response_model=CoachAttendanceOut, status_code=status.HTTP_201_CREATED)
def coach_entry(
    payload: CoachEntryExitRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    today = datetime.now().date()
    if _coach_is_on_leave(db, current_user.id, today):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are on approved leave today")

    if not is_within_geofence(float(payload.location_lat), float(payload.location_lng)):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You must be within the facility geofence to check in",
        )

    record = db.query(CoachAttendance).filter(CoachAttendance.coach_id == current_user.id, CoachAttendance.date == today).first()
    if record and record.entry_time:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Entry already recorded for today")

    if not record:
        record = CoachAttendance(coach_id=current_user.id, date=today, activity_id=payload.activity_id)
        db.add(record)

    record.entry_time = datetime.now()
    record.entry_lat = payload.location_lat
    record.entry_lng = payload.location_lng
    record.status = CoachAttendanceStatus.INCOMPLETE
    db.flush()
    log_action(db, current_user.id, "COACH_ENTRY", "CoachAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.post("/coach-exit", response_model=CoachAttendanceOut)
def coach_exit(
    payload: CoachEntryExitRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    today = datetime.now().date()
    if not is_within_geofence(float(payload.location_lat), float(payload.location_lng)):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You must be within the facility geofence to check out",
        )

    record = db.query(CoachAttendance).filter(CoachAttendance.coach_id == current_user.id, CoachAttendance.date == today).first()
    if not record or not record.entry_time:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No entry recorded for today")
    if record.exit_time:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Exit already recorded for today")

    record.exit_time = datetime.now()
    record.exit_lat = payload.location_lat
    record.exit_lng = payload.location_lng
    record.status = CoachAttendanceStatus.PRESENT
    log_action(db, current_user.id, "COACH_EXIT", "CoachAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.get("/students", response_model=List[StudentAttendanceAdminOut])
def list_student_attendance(
    activity_id: Optional[int] = None,
    class_id: Optional[int] = None,
    coach_id: Optional[int] = None,
    student_id: Optional[int] = None,
    status_filter: Optional[AttendanceStatus] = None,
    date_from: Optional[date_type] = None,
    date_to: Optional[date_type] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    query = (
        db.query(StudentAttendance)
        .join(ClassSession, ClassSession.id == StudentAttendance.class_id)
    )
    if activity_id:
        query = query.filter(ClassSession.activity_id == activity_id)
    if class_id:
        query = query.filter(StudentAttendance.class_id == class_id)
    if current_user.role == UserRole.COACH:
        query = query.filter(StudentAttendance.coach_id == current_user.id)
    elif coach_id:
        query = query.filter(StudentAttendance.coach_id == coach_id)
    if student_id:
        query = query.filter(StudentAttendance.student_id == student_id)
    if status_filter:
        query = query.filter(StudentAttendance.status == status_filter)
    if date_from:
        query = query.filter(ClassSession.date >= date_from)
    if date_to:
        query = query.filter(ClassSession.date <= date_to)

    records = query.order_by(ClassSession.date.desc(), StudentAttendance.timestamp.desc()).limit(500).all()

    result = []
    for r in records:
        result.append(
            StudentAttendanceAdminOut(
                id=r.id,
                student_id=r.student_id,
                student_name=r.student.name if r.student else "Unknown",
                class_id=r.class_id,
                activity_id=r.class_session.activity_id,
                activity_name=r.class_session.activity.name if r.class_session.activity else "Unknown",
                coach_id=r.coach_id,
                coach_name=r.coach.name if r.coach else None,
                status=r.status,
                class_date=r.class_session.date,
                timestamp=r.timestamp,
                marked_manually=bool(r.marked_manually),
            )
        )
    return result


def _authorize_own_attendance_edit(db: Session, current_user: User, record: StudentAttendance) -> None:
    """Coaches may only correct records they marked themselves, on the same day the class was held."""
    if current_user.role == UserRole.COACH:
        if record.coach_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
        if record.class_session.date != datetime.now().date():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only today's attendance records can be corrected",
            )
    elif current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")


@router.put("/students/{attendance_id}", response_model=StudentAttendanceOut)
def update_student_attendance(
    attendance_id: int,
    payload: StudentAttendanceUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    record = db.query(StudentAttendance).filter(StudentAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance record not found")
    _authorize_own_attendance_edit(db, current_user, record)

    record.status = payload.status
    log_action(db, current_user.id, "UPDATE", "StudentAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.delete("/students/{attendance_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_student_attendance(
    attendance_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    record = db.query(StudentAttendance).filter(StudentAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance record not found")
    _authorize_own_attendance_edit(db, current_user, record)

    log_action(db, current_user.id, "DELETE", "StudentAttendance", record.id)
    db.delete(record)
    db.commit()


@router.get("/daily-missing", response_model=List[MissingCoachOut])
def daily_missing(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    today = datetime.now().date()
    classes = db.query(ClassSession).filter(ClassSession.date == today).all()
    marked_class_ids = {
        row[0]
        for row in db.query(StudentAttendance.class_id)
        .join(ClassSession, ClassSession.id == StudentAttendance.class_id)
        .filter(ClassSession.date == today)
        .distinct()
    }

    result = []
    now = datetime.now()
    for cls in classes:
        class_end_dt = datetime.combine(cls.date, cls.end_time)
        if now < class_end_dt:
            continue  # class hasn't ended yet
        if cls.id in marked_class_ids:
            continue
        result.append(
            MissingCoachOut(
                coach_id=cls.coach.id,
                coach_name=cls.coach.name,
                class_id=cls.id,
                activity_name=cls.activity.name,
                date=str(cls.date),
                end_time=str(cls.end_time),
            )
        )
    return result


@router.get("/selfie/{attendance_id}")
def get_selfie(
    attendance_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    record = db.query(StudentAttendance).filter(StudentAttendance.id == attendance_id).first()
    if not record or not record.selfie_photo:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Selfie not found")

    allowed = (
        current_user.role == UserRole.ADMIN
        or current_user.id == record.student_id
        or current_user.id == record.coach_id
    )
    if not allowed:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this selfie")

    image_bytes = read_selfie(record.selfie_photo)
    return Response(content=image_bytes, media_type="image/jpeg")
