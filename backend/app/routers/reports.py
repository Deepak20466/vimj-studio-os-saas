import calendar
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import extract, func, case
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.attendance import StudentAttendance, AttendanceStatus, CoachAttendance
from app.models.fee import StudentFee, FeeStatus
from app.models.leave import CoachLeave, LeaveStatus
from app.schemas.reports import (
    AttendanceGraphResponse,
    MonthlyPoint,
    FeeStatusGraphResponse,
    HundredPercentCoach,
    MonthlyAnalysis,
    ActivityBreakdown,
    StudentReport,
    CoachReport,
)
from app.security import get_current_user, require_admin
from app.services.export import rows_to_csv, rows_to_pdf

router = APIRouter(prefix="/reports", tags=["reports"])


def _assert_can_view(current_user: User, target_id: int, coach: bool):
    if current_user.role == UserRole.ADMIN:
        return
    if coach and current_user.role == UserRole.COACH and current_user.id == target_id:
        return
    if not coach and current_user.role == UserRole.STUDENT and current_user.id == target_id:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this report")


@router.get("/student/{student_id}", response_model=StudentReport)
def student_report(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_can_view(current_user, student_id, coach=False)
    student = db.query(User).filter(User.id == student_id, User.role == UserRole.STUDENT).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")

    records = db.query(StudentAttendance).filter(StudentAttendance.student_id == student_id).all()
    present = sum(1 for r in records if r.status == AttendanceStatus.PRESENT)
    absent = sum(1 for r in records if r.status == AttendanceStatus.ABSENT)
    leave = sum(1 for r in records if r.status == AttendanceStatus.LEAVE)
    total = len(records)
    pct = round((present / total) * 100, 2) if total else 0.0

    fees = db.query(StudentFee).filter(StudentFee.student_id == student_id).all()
    fees_paid = sum(1 for f in fees if f.status == FeeStatus.PAID)
    fees_unpaid = sum(1 for f in fees if f.status != FeeStatus.PAID)
    outstanding = sum(float(f.amount) for f in fees if f.status != FeeStatus.PAID)

    return StudentReport(
        student_id=student_id,
        name=student.name,
        total_classes=total,
        present=present,
        absent=absent,
        leave=leave,
        attendance_pct=pct,
        fees_paid=fees_paid,
        fees_unpaid=fees_unpaid,
        outstanding_balance=outstanding,
    )


@router.get("/coach/{coach_id}", response_model=CoachReport)
def coach_report(
    coach_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_can_view(current_user, coach_id, coach=True)
    coach = db.query(User).filter(User.id == coach_id, User.role == UserRole.COACH).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach not found")

    class_ids = [row[0] for row in db.query(ClassSession.id).filter(ClassSession.coach_id == coach_id).all()]
    total_classes = len(class_ids)

    coach_att = db.query(CoachAttendance).filter(CoachAttendance.coach_id == coach_id).all()
    days_present = sum(1 for r in coach_att if r.status.value == "PRESENT")
    days_absent = sum(1 for r in coach_att if r.status.value in ("ABSENT", "INCOMPLETE"))

    leaves_taken = (
        db.query(CoachLeave)
        .filter(CoachLeave.coach_id == coach_id, CoachLeave.status == LeaveStatus.APPROVED)
        .count()
    )

    student_records = (
        db.query(StudentAttendance).filter(StudentAttendance.class_id.in_(class_ids)).all()
        if class_ids
        else []
    )
    present = sum(1 for r in student_records if r.status == AttendanceStatus.PRESENT)
    pct = round((present / len(student_records)) * 100, 2) if student_records else 0.0

    return CoachReport(
        coach_id=coach_id,
        name=coach.name,
        total_classes=total_classes,
        days_present=days_present,
        days_absent=days_absent,
        leaves_taken=leaves_taken,
        student_attendance_pct=pct,
    )


@router.get("/attendance-graph/{user_id}", response_model=AttendanceGraphResponse)
def attendance_graph(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role == UserRole.ADMIN or current_user.id == user_id:
        pass
    else:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    rows = (
        db.query(
            extract("year", StudentAttendance.timestamp).label("y"),
            extract("month", StudentAttendance.timestamp).label("m"),
            func.count(StudentAttendance.id).label("total"),
            func.sum(
                case((StudentAttendance.status == AttendanceStatus.PRESENT, 1), else_=0)
            ).label("present"),
        )
        .filter(StudentAttendance.student_id == user_id)
        .group_by("y", "m")
        .order_by("y", "m")
        .all()
    )

    points = []
    for row in rows:
        total = row.total or 0
        present = row.present or 0
        pct = round((present / total) * 100, 2) if total else 0.0
        label = f"{calendar.month_abbr[int(row.m)]} {int(row.y)}"
        points.append(MonthlyPoint(label=label, value=pct))

    return AttendanceGraphResponse(user_id=user_id, points=points)


@router.get("/fee-status-graph", response_model=FeeStatusGraphResponse)
def fee_status_graph(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    paid = db.query(StudentFee).filter(StudentFee.status == FeeStatus.PAID).count()
    unpaid = db.query(StudentFee).filter(StudentFee.status == FeeStatus.UNPAID).count()
    overdue = db.query(StudentFee).filter(StudentFee.status == FeeStatus.OVERDUE).count()
    return FeeStatusGraphResponse(paid=paid, unpaid=unpaid, overdue=overdue)


@router.get("/100-percent-coaches/{month}", response_model=List[HundredPercentCoach])
def hundred_percent_coaches(
    month: int,
    year: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    coaches = db.query(User).filter(User.role == UserRole.COACH).all()
    result = []
    for coach in coaches:
        class_ids = [
            row[0]
            for row in db.query(ClassSession.id)
            .filter(
                ClassSession.coach_id == coach.id,
                extract("month", ClassSession.date) == month,
                extract("year", ClassSession.date) == year,
            )
            .all()
        ]
        if not class_ids:
            continue
        records = db.query(StudentAttendance).filter(StudentAttendance.class_id.in_(class_ids)).all()
        if not records:
            continue
        present = sum(1 for r in records if r.status == AttendanceStatus.PRESENT)
        pct = round((present / len(records)) * 100, 2)
        if pct == 100.0:
            result.append(HundredPercentCoach(coach_id=coach.id, coach_name=coach.name, attendance_pct=pct))
    return result


@router.get("/dashboard-summary")
def dashboard_summary(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    today = date.today()
    total_students = db.query(User).filter(User.role == UserRole.STUDENT).count()
    total_coaches = db.query(User).filter(User.role == UserRole.COACH).count()
    total_classes = db.query(ClassSession).filter(
        extract("month", ClassSession.date) == today.month,
        extract("year", ClassSession.date) == today.year,
    ).count()
    revenue = (
        db.query(func.sum(StudentFee.amount))
        .filter(StudentFee.month == today.month, StudentFee.year == today.year, StudentFee.status == FeeStatus.PAID)
        .scalar()
    )
    return {
        "total_students": total_students,
        "total_coaches": total_coaches,
        "total_classes_this_month": total_classes,
        "monthly_revenue": float(revenue or 0),
    }


@router.get("/monthly-analysis", response_model=MonthlyAnalysis)
def monthly_analysis(
    month: int,
    year: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    total_students = db.query(User).filter(User.role == UserRole.STUDENT).count()
    total_coaches = db.query(User).filter(User.role == UserRole.COACH).count()

    classes = (
        db.query(ClassSession)
        .filter(extract("month", ClassSession.date) == month, extract("year", ClassSession.date) == year)
        .all()
    )
    total_classes = len(classes)
    class_ids = [c.id for c in classes]

    records = db.query(StudentAttendance).filter(StudentAttendance.class_id.in_(class_ids)).all() if class_ids else []
    present = sum(1 for r in records if r.status == AttendanceStatus.PRESENT)
    attendance_rate = round((present / len(records)) * 100, 2) if records else 0.0

    fees = db.query(StudentFee).filter(StudentFee.month == month, StudentFee.year == year, StudentFee.status == FeeStatus.PAID).all()
    monthly_revenue = sum(float(f.amount) for f in fees)

    activities = db.query(Activity).all()
    breakdown = []
    for activity in activities:
        act_classes = [c for c in classes if c.activity_id == activity.id]
        act_class_ids = [c.id for c in act_classes]
        act_records = [r for r in records if r.class_id in act_class_ids]
        act_present = sum(1 for r in act_records if r.status == AttendanceStatus.PRESENT)
        act_pct = round((act_present / len(act_records)) * 100, 2) if act_records else 0.0
        enrolled_count = db.query(StudentEnrollment).filter(StudentEnrollment.activity_id == activity.id).count()
        act_revenue = float(activity.monthly_fee) * enrolled_count
        breakdown.append(
            ActivityBreakdown(
                activity_name=activity.name,
                total_classes=len(act_classes),
                avg_attendance_pct=act_pct,
                revenue=act_revenue,
            )
        )

    prev_month = month - 1 if month > 1 else 12
    prev_year = year if month > 1 else year - 1
    prev_fees = db.query(StudentFee).filter(StudentFee.month == prev_month, StudentFee.year == prev_year, StudentFee.status == FeeStatus.PAID).all()
    prev_revenue = sum(float(f.amount) for f in prev_fees)

    prev_classes = (
        db.query(ClassSession)
        .filter(extract("month", ClassSession.date) == prev_month, extract("year", ClassSession.date) == prev_year)
        .all()
    )
    prev_class_ids = [c.id for c in prev_classes]
    prev_records = db.query(StudentAttendance).filter(StudentAttendance.class_id.in_(prev_class_ids)).all() if prev_class_ids else []
    prev_present = sum(1 for r in prev_records if r.status == AttendanceStatus.PRESENT)
    prev_attendance_rate = round((prev_present / len(prev_records)) * 100, 2) if prev_records else 0.0

    return MonthlyAnalysis(
        month=month,
        year=year,
        total_students=total_students,
        total_coaches=total_coaches,
        total_classes=total_classes,
        monthly_revenue=monthly_revenue,
        attendance_rate=attendance_rate,
        activity_breakdown=breakdown,
        prev_month_revenue=prev_revenue,
        prev_month_attendance_rate=prev_attendance_rate,
    )


@router.get("/export/student/{student_id}")
def export_student_report(
    student_id: int,
    fmt: str = "csv",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_can_view(current_user, student_id, coach=False)
    student = db.query(User).filter(User.id == student_id).first()
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")

    records = (
        db.query(StudentAttendance)
        .filter(StudentAttendance.student_id == student_id)
        .order_by(StudentAttendance.timestamp)
        .all()
    )
    headers = ["Date", "Class ID", "Status", "Coach ID"]
    rows = [[r.timestamp.strftime("%Y-%m-%d %H:%M"), r.class_id, r.status.value, r.coach_id] for r in records]

    if fmt == "pdf":
        buffer = rows_to_pdf(f"Attendance Report - {student.name}", headers, rows)
        return Response(content=buffer.read(), media_type="application/pdf", headers={"Content-Disposition": f"attachment; filename=student_{student_id}_report.pdf"})

    buffer = rows_to_csv(headers, rows)
    return Response(content=buffer.read(), media_type="text/csv", headers={"Content-Disposition": f"attachment; filename=student_{student_id}_report.csv"})


@router.get("/export/coach/{coach_id}")
def export_coach_report(
    coach_id: int,
    fmt: str = "csv",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_can_view(current_user, coach_id, coach=True)
    coach = db.query(User).filter(User.id == coach_id).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach not found")

    records = db.query(CoachAttendance).filter(CoachAttendance.coach_id == coach_id).order_by(CoachAttendance.date).all()
    headers = ["Date", "Entry", "Exit", "Status"]
    rows = [
        [str(r.date), r.entry_time.strftime("%H:%M") if r.entry_time else "-", r.exit_time.strftime("%H:%M") if r.exit_time else "-", r.status.value]
        for r in records
    ]

    if fmt == "pdf":
        buffer = rows_to_pdf(f"Attendance Report - {coach.name}", headers, rows)
        return Response(content=buffer.read(), media_type="application/pdf", headers={"Content-Disposition": f"attachment; filename=coach_{coach_id}_report.pdf"})

    buffer = rows_to_csv(headers, rows)
    return Response(content=buffer.read(), media_type="text/csv", headers={"Content-Disposition": f"attachment; filename=coach_{coach_id}_report.csv"})
