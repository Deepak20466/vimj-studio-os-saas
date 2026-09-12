from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.models.attendance import StudentAttendance, CoachAttendance
from app.models.fee import StudentFee
from app.models.fee_receipt import FeeReceipt
from app.models.fee_reminder_draft import FeeReminderDraft
from app.models.notification import Notification
from app.models.leave import CoachLeave
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
        "fees": db.query(StudentFee).delete(),
        "receipts": db.query(FeeReceipt).delete(),
        "fee_reminders": db.query(FeeReminderDraft).delete(),
        "leave": db.query(CoachLeave).delete(),
        "notifications": db.query(Notification).delete(),
    }

    log_action(db, current_user.id, "RESET_ALL_DATA", "System", details=str(counts))
    db.commit()
    return {"detail": "All attendance, fee, leave, and notification data has been reset.", "deleted": counts}


@router.post("/mine")
def reset_my_data(db: Session = Depends(get_db), current_user: User = Depends(require_coach)):
    """Coach-only: wipe only the requesting coach's own attendance/leave history. Never touches
    another coach's data or any fee/receipt record — those stay admin-controlled financial
    records (see DATA ISOLATION in CLAUDE.md)."""
    counts = {
        "attendance": db.query(StudentAttendance).filter(StudentAttendance.coach_id == current_user.id).delete(),
        "coach_attendance": db.query(CoachAttendance).filter(CoachAttendance.coach_id == current_user.id).delete(),
        "leave": db.query(CoachLeave).filter(CoachLeave.coach_id == current_user.id).delete(),
    }

    log_action(db, current_user.id, "RESET_MY_DATA", "User", current_user.id, details=str(counts))
    db.commit()
    return {"detail": "Your attendance and leave history has been reset.", "deleted": counts}
