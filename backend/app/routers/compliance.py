from datetime import datetime, date as date_type
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.class_session import ClassSession
from app.models.attendance import StudentAttendance
from app.models.compliance import ClassSkipReason, AttendanceSubmission, LateStatus, ClassPhoto
from app.schemas.compliance import (
    ClassNotConductedRequest,
    ClassSkipReasonOut,
    LateReasonRequest,
    LateDecisionRequest,
    AttendanceSubmissionOut,
    AttendanceSubmissionAdminOut,
    ClassPhotoUploadRequest,
    ClassPhotoOut,
    ComplianceRow,
    ComplianceSummary,
)
from app.security import get_current_user, require_admin, require_coach, require_admin_or_coach
from app.services.audit import log_action
from app.services.notifications import notify_and_push
from app.services.storage import save_class_photo
from app.routers.attendance import _resolve_marking_coach

router = APIRouter(prefix="/compliance", tags=["compliance"])


@router.post("/class-not-conducted", response_model=ClassSkipReasonOut, status_code=status.HTTP_201_CREATED)
def mark_class_not_conducted(
    payload: ClassNotConductedRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    class_session = db.query(ClassSession).filter(ClassSession.id == payload.class_id).first()
    if not class_session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    if class_session.coach_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not assigned to this class")

    class_end_dt = datetime.combine(class_session.date, class_session.end_time)
    if datetime.now() < class_end_dt:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Class has not ended yet")

    existing = db.query(ClassSkipReason).filter(ClassSkipReason.class_id == payload.class_id).first()
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="A reason was already submitted for this class")

    skip = ClassSkipReason(class_id=payload.class_id, coach_id=current_user.id, reason=payload.reason)
    db.add(skip)
    db.flush()
    log_action(db, current_user.id, "CLASS_NOT_CONDUCTED", "ClassSession", class_session.id)
    db.commit()
    db.refresh(skip)

    admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
    for admin in admins:
        notify_and_push(
            db, admin, f"{current_user.name} did not conduct the class on {class_session.date}: {payload.reason}",
            "Class not conducted", "CLASS_NOT_CONDUCTED", link="/compliance",
        )
    db.commit()
    return skip


@router.post("/late-reason", response_model=AttendanceSubmissionOut)
def submit_late_reason(
    payload: LateReasonRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    submission = db.query(AttendanceSubmission).filter(AttendanceSubmission.class_id == payload.class_id).first()
    if not submission:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No attendance submission found for this class")
    if submission.coach_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
    if not submission.is_late:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This submission was not marked late")

    submission.late_reason = payload.reason
    submission.late_status = LateStatus.PENDING
    log_action(db, current_user.id, "SUBMIT_LATE_REASON", "AttendanceSubmission", submission.id)
    db.commit()
    db.refresh(submission)

    admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
    for admin in admins:
        notify_and_push(
            db, admin, f"{current_user.name} submitted a late-attendance reason awaiting your approval.",
            "Late attendance awaiting approval", "LATE_ATTENDANCE_PENDING", link="/compliance",
        )
    db.commit()
    return submission


@router.get("/pending", response_model=List[AttendanceSubmissionAdminOut])
def pending_late_submissions(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    rows = (
        db.query(AttendanceSubmission)
        .filter(AttendanceSubmission.late_status == LateStatus.PENDING)
        .order_by(AttendanceSubmission.created_at)
        .all()
    )
    return _submissions_to_admin_out(db, rows)


def _submissions_to_admin_out(db: Session, rows: List[AttendanceSubmission]) -> List[AttendanceSubmissionAdminOut]:
    result = []
    for r in rows:
        cls = r.class_session
        result.append(
            AttendanceSubmissionAdminOut(
                id=r.id,
                class_id=r.class_id,
                coach_id=r.coach_id,
                submitted_at=r.submitted_at,
                is_late=r.is_late,
                late_reason=r.late_reason,
                late_status=r.late_status,
                created_at=r.created_at,
                coach_name=r.coach.name if r.coach else "Unknown",
                activity_name=cls.activity.name if cls and cls.activity else "Unknown",
                class_date=cls.date if cls else None,
            )
        )
    return result


@router.put("/late/{submission_id}/approve", response_model=AttendanceSubmissionOut)
def approve_late(
    submission_id: int,
    payload: LateDecisionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    submission = db.query(AttendanceSubmission).filter(AttendanceSubmission.id == submission_id).first()
    if not submission:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Submission not found")
    if submission.late_status != LateStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already decided")

    submission.late_status = LateStatus.APPROVED
    submission.decided_by_admin_id = current_user.id
    submission.decided_at = datetime.utcnow()
    log_action(db, current_user.id, "APPROVE_LATE_ATTENDANCE", "AttendanceSubmission", submission.id)
    db.commit()
    db.refresh(submission)

    coach = db.query(User).filter(User.id == submission.coach_id).first()
    notify_and_push(db, coach, "Your late-attendance submission was approved.", "Late attendance approved", "LATE_ATTENDANCE_DECIDED")
    db.commit()
    return submission


@router.put("/late/{submission_id}/reject", response_model=AttendanceSubmissionOut)
def reject_late(
    submission_id: int,
    payload: LateDecisionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    submission = db.query(AttendanceSubmission).filter(AttendanceSubmission.id == submission_id).first()
    if not submission:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Submission not found")
    if submission.late_status != LateStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already decided")

    submission.late_status = LateStatus.REJECTED
    submission.decided_by_admin_id = current_user.id
    submission.decided_at = datetime.utcnow()
    log_action(db, current_user.id, "REJECT_LATE_ATTENDANCE", "AttendanceSubmission", submission.id)
    db.commit()
    db.refresh(submission)

    coach = db.query(User).filter(User.id == submission.coach_id).first()
    notify_and_push(
        db, coach, f"Your late-attendance submission was rejected: {payload.decision_note or 'no reason given'}",
        "Late attendance rejected", "LATE_ATTENDANCE_DECIDED",
    )
    db.commit()
    return submission


@router.get("/summary", response_model=ComplianceSummary)
def compliance_summary(
    date_from: Optional[date_type] = None,
    date_to: Optional[date_type] = None,
    activity_id: Optional[int] = None,
    coach_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(ClassSession)
    if date_from:
        query = query.filter(ClassSession.date >= date_from)
    if date_to:
        query = query.filter(ClassSession.date <= date_to)
    if activity_id:
        query = query.filter(ClassSession.activity_id == activity_id)
    if coach_id:
        query = query.filter(ClassSession.coach_id == coach_id)
    classes = query.order_by(ClassSession.date.desc()).limit(500).all()

    class_ids = [c.id for c in classes]
    submissions = {
        s.class_id: s
        for s in db.query(AttendanceSubmission).filter(AttendanceSubmission.class_id.in_(class_ids)).all()
    } if class_ids else {}
    skips = {
        s.class_id: s
        for s in db.query(ClassSkipReason).filter(ClassSkipReason.class_id.in_(class_ids)).all()
    } if class_ids else {}

    now = datetime.now()
    rows: List[ComplianceRow] = []
    counts = {"submitted": 0, "pending": 0, "delayed": 0, "not_conducted": 0, "late_approved": 0, "late_rejected": 0}

    for cls in classes:
        class_end_dt = datetime.combine(cls.date, cls.end_time)
        submission = submissions.get(cls.id)
        skip = skips.get(cls.id)

        if skip:
            state = "NOT_CONDUCTED"
            counts["not_conducted"] += 1
        elif submission and submission.submitted_at:
            if submission.late_status == LateStatus.APPROVED:
                state = "LATE_APPROVED"
                counts["late_approved"] += 1
            elif submission.late_status == LateStatus.REJECTED:
                state = "LATE_REJECTED"
                counts["late_rejected"] += 1
            elif submission.late_status == LateStatus.PENDING:
                state = "DELAYED"
                counts["delayed"] += 1
            else:
                state = "SUBMITTED"
                counts["submitted"] += 1
        elif now < class_end_dt:
            continue  # not due yet, don't show as pending
        else:
            state = "PENDING"
            counts["pending"] += 1

        rows.append(
            ComplianceRow(
                class_id=cls.id,
                activity_name=cls.activity.name if cls.activity else "Unknown",
                coach_id=cls.coach_id,
                coach_name=cls.coach.name if cls.coach else "Unknown",
                class_date=cls.date,
                end_time=str(cls.end_time),
                state=state,
                skip_reason=skip.reason if skip else None,
                late_reason=submission.late_reason if submission else None,
            )
        )

    return ComplianceSummary(rows=rows, **counts)


@router.post("/class/{class_id}/photo", response_model=ClassPhotoOut, status_code=status.HTTP_201_CREATED)
def upload_class_photo(
    class_id: int,
    payload: ClassPhotoUploadRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    class_session = db.query(ClassSession).filter(ClassSession.id == class_id).first()
    if not class_session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")

    coach_id = _resolve_marking_coach(db, class_session, current_user)
    photo_bytes = save_class_photo(payload.photo_base64)

    photo = ClassPhoto(class_id=class_id, coach_id=coach_id, photo_path=photo_bytes)
    db.add(photo)
    db.flush()
    log_action(db, current_user.id, "UPLOAD_CLASS_PHOTO", "ClassPhoto", photo.id)
    db.commit()
    db.refresh(photo)
    return photo


@router.get("/class/{class_id}/photos", response_model=List[ClassPhotoOut])
def list_class_photos(
    class_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin_or_coach),
):
    return db.query(ClassPhoto).filter(ClassPhoto.class_id == class_id).order_by(ClassPhoto.created_at.desc()).all()


@router.get("/class-photo/{photo_id}")
def get_class_photo(
    photo_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    photo = db.query(ClassPhoto).filter(ClassPhoto.id == photo_id).first()
    if not photo:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Photo not found")
    if current_user.role not in (UserRole.ADMIN, UserRole.COACH):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
    return Response(content=photo.photo_path, media_type="image/jpeg")
