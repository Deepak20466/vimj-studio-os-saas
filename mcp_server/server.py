"""Local stdio MCP tools for an explicitly configured VIMJ admin account."""

from __future__ import annotations

import os
import sys
from datetime import date as date_type
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
sys.path.insert(0, str(BACKEND))
load_dotenv(BACKEND / ".env", override=False)

from fastmcp import FastMCP
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models.attendance import (
    AttendanceApprovalStatus,
    AttendanceStatus,
    StudentAttendance,
)
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.fee import FeeStatus, StudentFee
from app.models.user import User, UserRole
from app.services.audit import log_action
from app.services.insights import batch_analytics, fee_defaulters

mcp = FastMCP("VIMJ Studio OS SaaS Admin Tools")


def _open_admin_session() -> tuple[Session, User]:
    """Open a database session and resolve the configured, active admin principal."""
    email = os.getenv("VIMJ_MCP_ADMIN_EMAIL", "").strip().lower()
    if not email:
        raise PermissionError(
            "Set VIMJ_MCP_ADMIN_EMAIL in backend/.env to an active admin account before using MCP tools."
        )
    db = SessionLocal()
    admin = (
        db.query(User)
        .filter(User.email == email, User.role == UserRole.ADMIN, User.is_active.is_(True))
        .first()
    )
    if admin is None:
        db.close()
        raise PermissionError("The configured MCP account is not an active VIMJ admin.")
    return db, admin


def _close_session(db: Session) -> None:
    db.close()


@mcp.tool
def get_todays_absentees() -> dict:
    """List students explicitly marked ABSENT for today's scheduled classes."""
    today = date_type.today()
    db, _ = _open_admin_session()
    try:
        rows = (
            db.query(StudentAttendance, ClassSession, User)
            .join(ClassSession, ClassSession.id == StudentAttendance.class_id)
            .join(User, User.id == StudentAttendance.student_id)
            .filter(ClassSession.date == today, StudentAttendance.status == AttendanceStatus.ABSENT)
            .order_by(ClassSession.start_time, User.name)
            .all()
        )
        return {
            "date": today.isoformat(),
            "absentees": [
                {
                    "student_id": student.id,
                    "student_name": student.name,
                    "class_id": class_session.id,
                    "activity": class_session.activity.name if class_session.activity else "Unknown",
                    "status": attendance.status.value,
                }
                for attendance, class_session, student in rows
            ],
        }
    finally:
        _close_session(db)


@mcp.tool
def get_fee_defaulters(days_overdue: int = 7) -> dict:
    """List students whose fee balance is more than days_overdue late, with total pending."""
    if days_overdue < 0:
        raise ValueError("days_overdue must be zero or greater")
    db, _ = _open_admin_session()
    try:
        return fee_defaulters(db, days_overdue=days_overdue)
    finally:
        _close_session(db)


@mcp.tool
def mark_attendance(student_id: int, status: str, date: str) -> dict:
    """Admin-mark one student's scheduled attendance as Present, Absent, or Leave.

    The date must use YYYY-MM-DD. The tool requires exactly one matching class
    session for the student's enrolled activities on that date; ambiguous dates
    are rejected so the wrong class is never marked.
    """
    try:
        attendance_date = date_type.fromisoformat(date)
    except ValueError as exc:
        raise ValueError("date must use YYYY-MM-DD") from exc
    normalized_status = status.strip().upper()
    allowed = {"PRESENT", "ABSENT", "LEAVE"}
    if normalized_status not in allowed:
        raise ValueError("status must be Present, Absent, or Leave")
    attendance_status = AttendanceStatus[normalized_status]

    db, admin = _open_admin_session()
    try:
        student = (
            db.query(User)
            .filter(User.id == student_id, User.role == UserRole.STUDENT, User.is_active.is_(True))
            .first()
        )
        if student is None:
            raise ValueError("Active student not found")
        classes = (
            db.query(ClassSession)
            .join(StudentEnrollment, StudentEnrollment.activity_id == ClassSession.activity_id)
            .filter(StudentEnrollment.student_id == student_id, ClassSession.date == attendance_date)
            .order_by(ClassSession.start_time, ClassSession.id)
            .all()
        )
        if not classes:
            raise ValueError("No scheduled class found for this student's enrolled activities on that date")
        if len(classes) != 1:
            raise ValueError("More than one class matches this date; attendance was not changed")
        class_session = classes[0]
        record = (
            db.query(StudentAttendance)
            .filter(StudentAttendance.student_id == student_id, StudentAttendance.class_id == class_session.id)
            .first()
        )
        if record is None:
            record = StudentAttendance(
                student_id=student_id,
                class_id=class_session.id,
                coach_id=class_session.coach_id,
            )
            db.add(record)
        record.status = attendance_status
        record.coach_id = class_session.coach_id
        record.marked_manually = 1
        record.approval_status = AttendanceApprovalStatus.APPROVED
        db.flush()
        log_action(db, admin.id, "MCP_MARK_ATTENDANCE", "StudentAttendance", record.id)
        db.commit()
        return {
            "status": "marked",
            "student_id": student_id,
            "class_id": class_session.id,
            "attendance_status": attendance_status.value,
            "date": attendance_date.isoformat(),
        }
    except Exception:
        db.rollback()
        raise
    finally:
        _close_session(db)


@mcp.tool
def create_fee_reminder(student_id: int) -> dict:
    """Queue a free mock WhatsApp reminder for the student's unpaid fee records."""
    db, admin = _open_admin_session()
    try:
        student = (
            db.query(User)
            .filter(User.id == student_id, User.role == UserRole.STUDENT, User.is_active.is_(True))
            .first()
        )
        if student is None:
            raise ValueError("Active student not found")
        fees = (
            db.query(StudentFee)
            .filter(
                StudentFee.student_id == student_id,
                StudentFee.status.in_([FeeStatus.UNPAID, FeeStatus.OVERDUE]),
                StudentFee.balance_amount > 0,
            )
            .order_by(StudentFee.due_date, StudentFee.id)
            .all()
        )
        if not fees:
            return {"status": "not_queued", "student_id": student_id, "detail": "No pending fees found"}
        for fee in fees:
            log_action(
                db,
                admin.id,
                "QUEUE_MOCK_REMINDER",
                "StudentFee",
                fee.id,
                details=f"MCP mock WhatsApp reminder queued for student {student_id}",
            )
        db.commit()
        return {"status": "queued", "student_id": student_id, "fee_ids": [fee.id for fee in fees], "channel": "mock_whatsapp"}
    except Exception:
        db.rollback()
        raise
    finally:
        _close_session(db)


@mcp.tool
def get_batch_analytics() -> dict:
    """Return estimated batch profitability, attendance-drop batches, and revenue at risk."""
    db, _ = _open_admin_session()
    try:
        return batch_analytics(db)
    finally:
        _close_session(db)


if __name__ == "__main__":
    mcp.run(transport="stdio")
