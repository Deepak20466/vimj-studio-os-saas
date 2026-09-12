from datetime import date as date_type, datetime
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
    AttendanceApprovalStatus,
)
from app.schemas.attendance import (
    MarkStudentAttendanceRequest,
    ManualAttendanceRequest,
    StudentAttendanceOut,
    StudentAttendanceUpdate,
    StudentAttendanceAdminOut,
    AttendanceReviewRequest,
    CoachMarkRequest,
    CoachAttendanceOut,
    CoachAttendanceAdminOut,
    CoachAttendanceManualCreate,
    CoachAttendanceManualUpdate,
    MissingCoachOut,
)
from app.security import get_current_user, require_admin, require_coach, require_admin_or_coach
from app.services.audit import log_action
from app.services.notifications import notify_and_push

router = APIRouter(prefix="/attendance", tags=["attendance"])


def _resolve_marking_coach(db: Session, class_session: ClassSession, current_user: User) -> int:
    """Return the coach_id allowed to mark this class: only the assigned coach."""
    if current_user.id == class_session.coach_id:
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

    record = StudentAttendance(
        student_id=payload.student_id,
        class_id=payload.class_id,
        status=payload.status,
        coach_id=coach_id,
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
        existing.approval_status = AttendanceApprovalStatus.APPROVED
        record = existing
    else:
        record = StudentAttendance(
            student_id=payload.student_id,
            class_id=payload.class_id,
            status=payload.status,
            coach_id=class_session.coach_id,
            marked_manually=1,
            approval_status=AttendanceApprovalStatus.APPROVED,
        )
        db.add(record)

    db.flush()
    log_action(db, current_user.id, "MANUAL_MARK_ATTENDANCE", "StudentAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.post("/coach-mark", response_model=CoachAttendanceOut, status_code=status.HTTP_201_CREATED)
def coach_mark(
    payload: CoachMarkRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    """Coach marks their own facility attendance for today — manual entry, no GPS. Once
    submitted it cannot be changed by the coach; only admin's own tools can correct it."""
    today = datetime.now().date()

    existing = (
        db.query(CoachAttendance)
        .filter(CoachAttendance.coach_id == current_user.id, CoachAttendance.date == today)
        .first()
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You have already marked your attendance for today")

    record = CoachAttendance(
        coach_id=current_user.id,
        date=today,
        activity_id=payload.activity_id,
        entry_time=datetime.now(),
        status=payload.status,
    )
    db.add(record)
    db.flush()
    log_action(db, current_user.id, "COACH_MARK_ATTENDANCE", "CoachAttendance", record.id)
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
    approval_status: Optional[AttendanceApprovalStatus] = None,
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
    if approval_status:
        query = query.filter(StudentAttendance.approval_status == approval_status)
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
                has_selfie=bool(r.selfie_photo),
                approval_status=r.approval_status,
            )
        )
    return result


@router.put("/students/{attendance_id}", response_model=StudentAttendanceOut)
def update_student_attendance(
    attendance_id: int,
    payload: StudentAttendanceUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Admin-only: once a coach submits an attendance mark it cannot be changed by the coach —
    only admin's own tools (this endpoint, or approve/reject) can correct it."""
    record = db.query(StudentAttendance).filter(StudentAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance record not found")

    record.status = payload.status
    log_action(db, current_user.id, "UPDATE", "StudentAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.delete("/students/{attendance_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_student_attendance(
    attendance_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Admin-only — see update_student_attendance."""
    record = db.query(StudentAttendance).filter(StudentAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance record not found")

    log_action(db, current_user.id, "DELETE", "StudentAttendance", record.id)
    db.delete(record)
    db.commit()


@router.put("/students/{attendance_id}/approve", response_model=StudentAttendanceOut)
def approve_student_attendance(
    attendance_id: int,
    payload: AttendanceReviewRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(StudentAttendance).filter(StudentAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance record not found")
    if record.approval_status != AttendanceApprovalStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This record has already been reviewed")

    record.approval_status = AttendanceApprovalStatus.APPROVED
    log_action(db, current_user.id, "APPROVE_ATTENDANCE", "StudentAttendance", record.id, details=payload.note)
    db.commit()
    db.refresh(record)

    coach = db.query(User).filter(User.id == record.coach_id).first() if record.coach_id else None
    if coach:
        notify_and_push(
            db, coach,
            f"Your attendance mark for {record.student.name if record.student else 'a student'} on "
            f"{record.class_session.date} was approved and is now locked.",
            "Attendance approved", "ATTENDANCE_DECIDED", link="/coach/attendance",
        )
        db.commit()
    return record


@router.put("/students/{attendance_id}/reject", response_model=StudentAttendanceOut)
def reject_student_attendance(
    attendance_id: int,
    payload: AttendanceReviewRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(StudentAttendance).filter(StudentAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance record not found")
    if record.approval_status != AttendanceApprovalStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This record has already been reviewed")

    record.approval_status = AttendanceApprovalStatus.REJECTED
    log_action(db, current_user.id, "REJECT_ATTENDANCE", "StudentAttendance", record.id, details=payload.note)
    db.commit()
    db.refresh(record)

    coach = db.query(User).filter(User.id == record.coach_id).first() if record.coach_id else None
    if coach:
        notify_and_push(
            db, coach,
            f"Your attendance mark for {record.student.name if record.student else 'a student'} on "
            f"{record.class_session.date} was rejected"
            + (f": {payload.note}" if payload.note else ".")
            + " Contact admin to have it corrected.",
            "Attendance rejected", "ATTENDANCE_DECIDED", link="/coach/attendance",
        )
        db.commit()
    return record


@router.get("/coaches", response_model=List[CoachAttendanceAdminOut])
def list_coach_attendance(
    coach_id: Optional[int] = None,
    date_from: Optional[date_type] = None,
    date_to: Optional[date_type] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Admin view of coach facility entry/exit records, for manual reporting/CRUD."""
    query = db.query(CoachAttendance)
    if coach_id:
        query = query.filter(CoachAttendance.coach_id == coach_id)
    if date_from:
        query = query.filter(CoachAttendance.date >= date_from)
    if date_to:
        query = query.filter(CoachAttendance.date <= date_to)

    records = query.order_by(CoachAttendance.date.desc()).limit(500).all()
    coaches = {u.id: u.name for u in db.query(User).filter(User.id.in_([r.coach_id for r in records])).all()}
    return [
        CoachAttendanceAdminOut(
            id=r.id,
            coach_id=r.coach_id,
            coach_name=coaches.get(r.coach_id, "Unknown"),
            date=r.date,
            entry_time=r.entry_time,
            exit_time=r.exit_time,
            status=r.status,
        )
        for r in records
    ]


@router.post("/coaches/manual", response_model=CoachAttendanceOut, status_code=status.HTTP_201_CREATED)
def create_coach_attendance_manual(
    payload: CoachAttendanceManualCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Admin manual entry for a coach's facility attendance — bypasses geofencing."""
    coach = db.query(User).filter(User.id == payload.coach_id, User.role == UserRole.COACH).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Coach not found")

    existing = (
        db.query(CoachAttendance)
        .filter(CoachAttendance.coach_id == payload.coach_id, CoachAttendance.date == payload.date)
        .first()
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attendance record already exists for this coach on this date")

    record = CoachAttendance(
        coach_id=payload.coach_id,
        date=payload.date,
        entry_time=datetime.combine(payload.date, payload.entry_time) if payload.entry_time else None,
        exit_time=datetime.combine(payload.date, payload.exit_time) if payload.exit_time else None,
        status=payload.status,
    )
    db.add(record)
    db.flush()
    log_action(db, current_user.id, "MANUAL_MARK_COACH_ATTENDANCE", "CoachAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.put("/coaches/{attendance_id}", response_model=CoachAttendanceOut)
def update_coach_attendance(
    attendance_id: int,
    payload: CoachAttendanceManualUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(CoachAttendance).filter(CoachAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach attendance record not found")

    if payload.entry_time is not None:
        record.entry_time = datetime.combine(record.date, payload.entry_time)
    if payload.exit_time is not None:
        record.exit_time = datetime.combine(record.date, payload.exit_time)
    if payload.status is not None:
        record.status = payload.status

    log_action(db, current_user.id, "UPDATE", "CoachAttendance", record.id)
    db.commit()
    db.refresh(record)
    return record


@router.delete("/coaches/{attendance_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_coach_attendance(
    attendance_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(CoachAttendance).filter(CoachAttendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach attendance record not found")

    log_action(db, current_user.id, "DELETE", "CoachAttendance", record.id)
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

    return Response(content=record.selfie_photo, media_type="image/jpeg")
