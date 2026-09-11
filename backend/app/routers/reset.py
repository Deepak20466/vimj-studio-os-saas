from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.models.attendance import StudentAttendance, CoachAttendance
from app.models.leave import CoachLeave
from app.models.swap import CoachSwap
from app.models.fee import StudentFee
from app.models.salary import CoachSalary
from app.models.fee_receipt import FeeReceipt
from app.models.fee_reminder_draft import FeeReminderDraft
from app.models.compliance import AttendanceSubmission, ClassSkipReason, ClassPhoto
from app.models.notification import Notification
from app.security import require_admin, require_coach
from app.services.audit import log_action

router = APIRouter(prefix="/reset", tags=["reset"])


@router.post("/all")
def reset_all_data(db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    """Admin-only: wipe all transactional/operational history system-wide so the
    app starts fresh, without touching structure or the roster. Deliberately
    KEEPS Users (admins/coaches/students), Activities, Batches, and generated
    ClassSessions intact — only records/history reset, so the app keeps working
    immediately (coaches still see their schedule; nothing needs re-creating).
    """
    counts = {
        "attendance": db.query(StudentAttendance).delete(),
        "coach_attendance": db.query(CoachAttendance).delete(),
        "compliance_submissions": db.query(AttendanceSubmission).delete(),
        "compliance_skip_reasons": db.query(ClassSkipReason).delete(),
        "compliance_class_photos": db.query(ClassPhoto).delete(),
        "leave": db.query(CoachLeave).delete(),
        "swaps": db.query(CoachSwap).delete(),
        "fees": db.query(StudentFee).delete(),
        "salary": db.query(CoachSalary).delete(),
        "receipts": db.query(FeeReceipt).delete(),
        "fee_reminders": db.query(FeeReminderDraft).delete(),
        "notifications": db.query(Notification).delete(),
    }

    log_action(db, current_user.id, "RESET_ALL_DATA", "System", details=str(counts))
    db.commit()
    return {"detail": "All attendance, fee, leave, salary, swap, compliance, and notification data has been reset.", "deleted": counts}


@router.post("/mine")
def reset_my_data(db: Session = Depends(get_db), current_user: User = Depends(require_coach)):
    """Coach-only: wipe only the requesting coach's own attendance/leave/swap
    history. Never touches another coach's data or fee/salary/receipt records —
    those stay admin-controlled financial records (see DATA ISOLATION in
    CLAUDE.md)."""
    counts = {
        "attendance": db.query(StudentAttendance).filter(StudentAttendance.coach_id == current_user.id).delete(),
        "coach_attendance": db.query(CoachAttendance).filter(CoachAttendance.coach_id == current_user.id).delete(),
        "leave": db.query(CoachLeave).filter(CoachLeave.coach_id == current_user.id).delete(),
        "swaps": db.query(CoachSwap)
        .filter((CoachSwap.original_coach_id == current_user.id) | (CoachSwap.covering_coach_id == current_user.id))
        .delete(synchronize_session=False),
    }

    log_action(db, current_user.id, "RESET_MY_DATA", "User", current_user.id, details=str(counts))
    db.commit()
    return {"detail": "Your attendance, leave, and swap history has been reset.", "deleted": counts}
