from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import extract, func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.attendance import StudentAttendance, AttendanceStatus
from app.models.fee import StudentFee, FeeStatus
from app.models.user import User, UserRole
from app.schemas.dashboard import (
    DashboardSummary,
    FeeStatusGraphResponse,
    ActivityAttendanceResponse,
    ActivityAttendancePoint,
)
from app.security import require_admin

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/summary", response_model=DashboardSummary)
def dashboard_summary(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    today = date.today()
    total_students = db.query(User).filter(User.role == UserRole.STUDENT).count()
    total_coaches = db.query(User).filter(User.role == UserRole.COACH).count()
    total_activities = db.query(Activity).count()
    total_classes = (
        db.query(ClassSession)
        .filter(extract("month", ClassSession.date) == today.month, extract("year", ClassSession.date) == today.year)
        .count()
    )
    revenue = (
        db.query(func.sum(StudentFee.amount))
        .filter(StudentFee.month == today.month, StudentFee.year == today.year, StudentFee.status == FeeStatus.PAID)
        .scalar()
    )
    unpaid_count = db.query(StudentFee).filter(StudentFee.status.in_([FeeStatus.UNPAID, FeeStatus.OVERDUE])).count()
    return DashboardSummary(
        total_students=total_students,
        total_coaches=total_coaches,
        total_activities=total_activities,
        total_classes_this_month=total_classes,
        monthly_revenue=float(revenue or 0),
        unpaid_fees_count=unpaid_count,
    )


@router.get("/fee-status", response_model=FeeStatusGraphResponse)
def fee_status_chart(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    paid = db.query(StudentFee).filter(StudentFee.status == FeeStatus.PAID).count()
    unpaid = db.query(StudentFee).filter(StudentFee.status == FeeStatus.UNPAID).count()
    overdue = db.query(StudentFee).filter(StudentFee.status == FeeStatus.OVERDUE).count()
    return FeeStatusGraphResponse(paid=paid, unpaid=unpaid, overdue=overdue)


@router.get("/activity-attendance", response_model=ActivityAttendanceResponse)
def activity_attendance_chart(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    """Current month's attendance % per activity, for the Dashboard bar chart."""
    today = date.today()
    activities = db.query(Activity).order_by(Activity.name).all()

    classes = (
        db.query(ClassSession)
        .filter(extract("month", ClassSession.date) == today.month, extract("year", ClassSession.date) == today.year)
        .all()
    )
    classes_by_activity: dict = {}
    for c in classes:
        classes_by_activity.setdefault(c.activity_id, []).append(c.id)

    class_ids = [c.id for c in classes]
    records = db.query(StudentAttendance).filter(StudentAttendance.class_id.in_(class_ids)).all() if class_ids else []
    records_by_class: dict = {}
    for r in records:
        records_by_class.setdefault(r.class_id, []).append(r)

    points = []
    for activity in activities:
        student_count = db.query(StudentEnrollment).filter(StudentEnrollment.activity_id == activity.id).count()
        act_class_ids = classes_by_activity.get(activity.id, [])
        act_records = [r for cid in act_class_ids for r in records_by_class.get(cid, [])]
        present = sum(1 for r in act_records if r.status == AttendanceStatus.PRESENT)
        pct = round((present / len(act_records)) * 100, 2) if act_records else 0.0
        points.append(
            ActivityAttendancePoint(
                activity_id=activity.id,
                activity_name=activity.name,
                student_count=student_count,
                avg_attendance_pct=pct,
            )
        )

    return ActivityAttendanceResponse(points=points)
