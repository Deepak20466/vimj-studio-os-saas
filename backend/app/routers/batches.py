from datetime import date, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.batch import Batch
from app.models.class_session import ClassSession
from app.models.coach_activity import CoachActivity
from app.models.enrollment import StudentEnrollment
from app.models.attendance import StudentAttendance, AttendanceStatus
from app.models.fee import StudentFee
from app.schemas.batch import BatchCreate, BatchUpdate, BatchOut, GenerateSessionsRequest
from app.security import get_current_user, require_admin
from app.services.audit import log_action
from app.services.batches import WEEKDAY_CODES as _WEEKDAY_CODES, generate_sessions_for_batch
from app.services.scheduler import BATCH_AUTO_GENERATE_DAYS_AHEAD

router = APIRouter(prefix="/batches", tags=["batches"])


def _days_to_str(days: List[str]) -> str:
    return ",".join(days)


def _months_to_str(months: List[int]) -> str:
    return ",".join(str(m) for m in months)


def _out(batch: Batch) -> BatchOut:
    return BatchOut(
        id=batch.id,
        activity_id=batch.activity_id,
        coach_id=batch.coach_id,
        location=batch.location,
        session_period=batch.session_period,
        start_time=batch.start_time,
        end_time=batch.end_time,
        days_of_week=batch.days_of_week.split(","),
        active_months=[int(m) for m in batch.active_months.split(",") if m],
        is_active=batch.is_active,
        created_at=batch.created_at,
    )


@router.get("", response_model=List[BatchOut])
def list_batches(
    activity_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(Batch)
    if activity_id:
        query = query.filter(Batch.activity_id == activity_id)
    return [_out(b) for b in query.order_by(Batch.created_at.desc()).all()]


@router.get("/{batch_id}/roster")
def batch_roster(
    batch_id: int,
    class_date: Optional[date] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """The complete student list for one batch/session slot (e.g. Morning 8am) on a given date:
    who's present/absent/unmarked, and — for students marked present that day — their current
    month's fee status. Used by the Activities > Sessions view so admin can drill from an
    activity's slots down to a single occurrence's roster without leaving the page."""
    batch = db.query(Batch).filter(Batch.id == batch_id).first()
    if not batch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Batch not found")

    target_date = class_date or date.today()

    class_session = (
        db.query(ClassSession)
        .filter(ClassSession.batch_id == batch_id, ClassSession.date == target_date)
        .first()
    )

    enrolled = (
        db.query(User, StudentEnrollment.id)
        .join(StudentEnrollment, StudentEnrollment.student_id == User.id)
        .filter(StudentEnrollment.activity_id == batch.activity_id)
        .order_by(User.name)
        .all()
    )
    student_ids = [s.id for s, _ in enrolled]

    attendance_by_student = {}
    if class_session and student_ids:
        for record in (
            db.query(StudentAttendance)
            .filter(StudentAttendance.class_id == class_session.id, StudentAttendance.student_id.in_(student_ids))
            .all()
        ):
            attendance_by_student[record.student_id] = record

    today = date.today()
    fees_by_student = (
        {
            f.student_id: f
            for f in db.query(StudentFee)
            .filter(StudentFee.student_id.in_(student_ids), StudentFee.month == today.month, StudentFee.year == today.year)
            .all()
        }
        if student_ids
        else {}
    )

    students = []
    present_count = 0
    absent_count = 0
    not_confirm_count = 0
    unmarked_count = 0
    for student, enrollment_id in enrolled:
        record = attendance_by_student.get(student.id)
        attendance_status = record.status.value if record else "UNMARKED"
        if attendance_status == AttendanceStatus.PRESENT.value:
            present_count += 1
        elif attendance_status in (AttendanceStatus.ABSENT.value, AttendanceStatus.LEAVE.value):
            absent_count += 1
        elif attendance_status == AttendanceStatus.NOT_CONFIRM.value:
            not_confirm_count += 1
        else:
            unmarked_count += 1

        fee = fees_by_student.get(student.id)
        students.append(
            {
                "student_id": student.id,
                "student_name": student.name,
                "enrollment_id": enrollment_id,
                "attendance_status": attendance_status,
                "attendance_id": record.id if record else None,
                "fee_status": fee.status.value if (fee and attendance_status == AttendanceStatus.PRESENT.value) else None,
                "fee_id": fee.id if (fee and attendance_status == AttendanceStatus.PRESENT.value) else None,
            }
        )

    return {
        "batch": _out(batch),
        "class_date": target_date,
        "class_id": class_session.id if class_session else None,
        "present_count": present_count,
        "absent_count": absent_count,
        "not_confirm_count": not_confirm_count,
        "unmarked_count": unmarked_count,
        "students": students,
    }


@router.get("/coverage")
def batches_coverage(
    check_date: Optional[date] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Answers "is any slot not taken, and who takes which activity": unassigned batches
    (no coach linked), batches scheduled for `check_date` that have no generated `ClassSession`
    yet, and a per-activity map of which coach(es) run it."""
    target = check_date or date.today()
    weekday_code = _WEEKDAY_CODES[target.weekday()]
    active_batches = db.query(Batch).filter(Batch.is_active.is_(True)).all()

    unassigned = [_out(b) for b in active_batches if b.coach_id is None]

    scheduled_today = [
        b
        for b in active_batches
        if weekday_code in b.days_of_week.split(",") and str(target.month) in b.active_months.split(",")
    ]
    scheduled_batch_ids = [b.id for b in scheduled_today]
    generated_batch_ids = (
        {
            row[0]
            for row in db.query(ClassSession.batch_id)
            .filter(ClassSession.date == target, ClassSession.batch_id.in_(scheduled_batch_ids))
            .all()
        }
        if scheduled_batch_ids
        else set()
    )
    not_generated = [_out(b) for b in scheduled_today if b.id not in generated_batch_ids]

    activity_map: dict = {}
    for b in active_batches:
        if not b.coach_id:
            continue
        entry = activity_map.setdefault(
            b.activity_id,
            {"activity_id": b.activity_id, "activity_name": b.activity.name if b.activity else "Unknown", "coaches": {}},
        )
        coach_entry = entry["coaches"].setdefault(
            b.coach_id, {"coach_id": b.coach_id, "coach_name": b.coach.name if b.coach else "Unknown", "batch_count": 0}
        )
        coach_entry["batch_count"] += 1

    activity_coach_map = [
        {"activity_id": e["activity_id"], "activity_name": e["activity_name"], "coaches": list(e["coaches"].values())}
        for e in activity_map.values()
    ]

    return {
        "date": target,
        "unassigned_batches": unassigned,
        "batches_not_generated_today": not_generated,
        "activity_coach_map": activity_coach_map,
    }


@router.get("/my", response_model=List[BatchOut])
def my_batches(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role != UserRole.COACH:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only coaches have a batch list")
    return [_out(b) for b in db.query(Batch).filter(Batch.coach_id == current_user.id).all()]


@router.post("", response_model=BatchOut, status_code=status.HTTP_201_CREATED)
def create_batch(
    payload: BatchCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    activity = db.query(Activity).filter(Activity.id == payload.activity_id).first()
    if not activity:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Activity not found")
    if payload.coach_id is not None:
        coach = db.query(User).filter(User.id == payload.coach_id, User.role == UserRole.COACH).first()
        if not coach:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Coach not found")

    data = payload.model_dump()
    data["days_of_week"] = _days_to_str(data["days_of_week"])
    data["active_months"] = _months_to_str(data["active_months"])
    batch = Batch(**data)
    db.add(batch)
    db.flush()

    # Without this, a newly-created batch sits invisible to its coach until the nightly
    # auto-generate job runs (up to ~24h later) or an admin remembers to click "Generate
    # Sessions" — a coach assigned a new schedule today sees nothing about it in their
    # classes list until tomorrow at the earliest, which reads as "the coach never received
    # the schedule" even though the assignment itself succeeded.
    if batch.coach_id and batch.is_active:
        generate_sessions_for_batch(db, batch, date.today(), date.today() + timedelta(days=BATCH_AUTO_GENERATE_DAYS_AHEAD))

    log_action(db, current_user.id, "CREATE", "Batch", batch.id)
    db.commit()
    db.refresh(batch)
    return _out(batch)


@router.put("/{batch_id}", response_model=BatchOut)
def update_batch(
    batch_id: int,
    payload: BatchUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    batch = db.query(Batch).filter(Batch.id == batch_id).first()
    if not batch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Batch not found")

    updates = payload.model_dump(exclude_unset=True)
    if "coach_id" in updates and updates["coach_id"] is not None:
        coach = db.query(User).filter(User.id == updates["coach_id"], User.role == UserRole.COACH).first()
        if not coach:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Coach not found")
    if "days_of_week" in updates:
        updates["days_of_week"] = _days_to_str(updates["days_of_week"])
    if "active_months" in updates:
        updates["active_months"] = _months_to_str(updates["active_months"])
    for field, value in updates.items():
        setattr(batch, field, value)

    # Same reasoning as create_batch: e.g. assigning a coach to a previously-unassigned
    # batch, or reactivating one, shouldn't require waiting for the nightly job before the
    # coach can see it. generate_sessions_for_batch skips dates that already have a session,
    # so calling this on every update is harmless even when nothing relevant changed.
    if batch.coach_id and batch.is_active:
        generate_sessions_for_batch(db, batch, date.today(), date.today() + timedelta(days=BATCH_AUTO_GENERATE_DAYS_AHEAD))

    log_action(db, current_user.id, "UPDATE", "Batch", batch.id)
    db.commit()
    db.refresh(batch)
    return _out(batch)


@router.delete("/{batch_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_batch(
    batch_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    batch = db.query(Batch).filter(Batch.id == batch_id).first()
    if not batch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Batch not found")
    log_action(db, current_user.id, "DELETE", "Batch", batch.id)
    db.delete(batch)
    db.commit()


@router.post("/{batch_id}/generate-sessions")
def generate_sessions(
    batch_id: int,
    payload: GenerateSessionsRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    batch = db.query(Batch).filter(Batch.id == batch_id).first()
    if not batch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Batch not found")
    if not batch.coach_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Assign a coach to this batch first")
    if payload.end_date < payload.start_date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="end_date must be on/after start_date")

    created = generate_sessions_for_batch(db, batch, payload.start_date, payload.end_date)

    log_action(db, current_user.id, "GENERATE_SESSIONS", "Batch", batch.id, details=f"{created} sessions")
    db.commit()
    return {"detail": f"{created} class session(s) generated"}
