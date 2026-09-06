import calendar
from collections import defaultdict
from datetime import date, time
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import extract, func, case
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.batch import Batch
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
    ActivityDetailReport,
    ActivityCoachBreakdown,
    BatchBreakdown,
    BatchStudentSummary,
    SessionPeriodBreakdown,
)
from app.security import get_current_user, require_admin, require_coach
from app.services.export import rows_to_csv, rows_to_pdf, build_coach_monthly_report_pdf

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

    # Fees aren't tracked per-activity in this schema, so a student's paid fee for the
    # month is attributed proportionally across every activity they're enrolled in.
    enrollments = db.query(StudentEnrollment).all()
    student_activity_ids: dict = defaultdict(set)
    for e in enrollments:
        student_activity_ids[e.student_id].add(e.activity_id)
    paid_by_student = {f.student_id: float(f.amount) for f in fees}
    revenue_collected_by_activity: dict = defaultdict(float)
    for student_id, activity_ids in student_activity_ids.items():
        amount = paid_by_student.get(student_id, 0.0)
        if amount and activity_ids:
            share = amount / len(activity_ids)
            for aid in activity_ids:
                revenue_collected_by_activity[aid] += share

    activities = db.query(Activity).all()
    breakdown = []
    for activity in activities:
        act_classes = [c for c in classes if c.activity_id == activity.id]
        act_class_ids = [c.id for c in act_classes]
        act_records = [r for r in records if r.class_id in act_class_ids]
        act_present = sum(1 for r in act_records if r.status == AttendanceStatus.PRESENT)
        act_absent = sum(1 for r in act_records if r.status == AttendanceStatus.ABSENT)
        act_pct = round((act_present / len(act_records)) * 100, 2) if act_records else 0.0
        enrolled_count = db.query(StudentEnrollment).filter(StudentEnrollment.activity_id == activity.id).count()
        act_revenue = float(activity.monthly_fee) * enrolled_count
        breakdown.append(
            ActivityBreakdown(
                activity_id=activity.id,
                activity_name=activity.name,
                student_count=enrolled_count,
                total_classes=len(act_classes),
                total_attendance_marks=len(act_records),
                total_present=act_present,
                total_absent=act_absent,
                avg_attendance_pct=act_pct,
                revenue=act_revenue,
                revenue_collected=round(revenue_collected_by_activity.get(activity.id, 0.0), 2),
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


@router.get("/activity/{activity_id}", response_model=ActivityDetailReport)
def activity_report(
    activity_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    activity = db.query(Activity).filter(Activity.id == activity_id).first()
    if not activity:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Activity not found")

    student_count = db.query(StudentEnrollment).filter(StudentEnrollment.activity_id == activity_id).count()
    classes = db.query(ClassSession).filter(ClassSession.activity_id == activity_id).all()
    class_ids = [c.id for c in classes]
    records = db.query(StudentAttendance).filter(StudentAttendance.class_id.in_(class_ids)).all() if class_ids else []
    present = sum(1 for r in records if r.status == AttendanceStatus.PRESENT)
    absent = sum(1 for r in records if r.status == AttendanceStatus.ABSENT)
    pct = round((present / len(records)) * 100, 2) if records else 0.0

    student_ids = [
        row[0]
        for row in db.query(StudentEnrollment.student_id).filter(StudentEnrollment.activity_id == activity_id).all()
    ]
    fees = db.query(StudentFee).filter(StudentFee.student_id.in_(student_ids)).all() if student_ids else []
    fee_paid_count = sum(1 for f in fees if f.status == FeeStatus.PAID)
    fee_unpaid_count = sum(1 for f in fees if f.status != FeeStatus.PAID)

    enrollments = db.query(StudentEnrollment).all()
    student_activity_ids: dict = defaultdict(set)
    for e in enrollments:
        student_activity_ids[e.student_id].add(e.activity_id)
    paid_fees = db.query(StudentFee).filter(StudentFee.status == FeeStatus.PAID, StudentFee.student_id.in_(student_ids)).all() if student_ids else []
    revenue_collected = 0.0
    for f in paid_fees:
        activity_ids = student_activity_ids.get(f.student_id, set())
        if activity_ids:
            revenue_collected += float(f.amount) / len(activity_ids)

    rows = (
        db.query(
            extract("year", StudentAttendance.timestamp).label("y"),
            extract("month", StudentAttendance.timestamp).label("m"),
            func.count(StudentAttendance.id).label("total"),
            func.sum(case((StudentAttendance.status == AttendanceStatus.PRESENT, 1), else_=0)).label("present"),
        )
        .filter(StudentAttendance.class_id.in_(class_ids))
        .group_by("y", "m")
        .order_by("y", "m")
        .all()
        if class_ids
        else []
    )
    graph_points = []
    for row in rows:
        total = row.total or 0
        row_present = row.present or 0
        row_pct = round((row_present / total) * 100, 2) if total else 0.0
        graph_points.append(MonthlyPoint(label=f"{calendar.month_abbr[int(row.m)]} {int(row.y)}", value=row_pct))

    coach_ids = {c.coach_id for c in classes}
    coach_breakdown = []
    for coach_id in coach_ids:
        coach = db.query(User).filter(User.id == coach_id).first()
        if not coach:
            continue
        coach_classes = [c for c in classes if c.coach_id == coach_id]
        coach_class_ids = [c.id for c in coach_classes]
        coach_records = [r for r in records if r.class_id in coach_class_ids]
        coach_present = sum(1 for r in coach_records if r.status == AttendanceStatus.PRESENT)
        coach_pct = round((coach_present / len(coach_records)) * 100, 2) if coach_records else 0.0
        coach_breakdown.append(
            ActivityCoachBreakdown(
                coach_id=coach_id,
                coach_name=coach.name,
                total_classes=len(coach_classes),
                avg_attendance_pct=coach_pct,
            )
        )

    # Batch/session-period breakdown: morning/afternoon/evening, each recurring slot shown
    # separately with its own roster, attendance and fee status. Classes created through the
    # Batches page carry a `session_period` (Morning/Afternoon/Evening) directly; classes created
    # ad hoc on the Activities page have no Batch at all, so their period is derived from the
    # class's own start time and they're grouped by (coach, start_time, end_time) instead of a
    # batch id — this way every class shows up here, not just batch-scheduled ones. A group's
    # "students" are derived from who has an attendance record against one of its class sessions,
    # since enrollment is tracked per-activity (not per-batch/slot) in this schema.
    batches_by_id = {b.id: b for b in db.query(Batch).filter(Batch.activity_id == activity_id).all()}
    today = date.today()
    fees_by_student = {
        f.student_id: f
        for f in db.query(StudentFee)
        .filter(StudentFee.student_id.in_(student_ids), StudentFee.month == today.month, StudentFee.year == today.year)
        .all()
    } if student_ids else {}

    def derive_period(t) -> str:
        if t < time(12, 0):
            return "MORNING"
        if t < time(17, 0):
            return "AFTERNOON"
        return "EVENING"

    groups: dict = {}
    group_order: list = []
    for c in classes:
        batch = batches_by_id.get(c.batch_id) if c.batch_id else None
        if batch:
            group_key = f"batch-{batch.id}"
            period = batch.session_period.value
            location = batch.location
            days_of_week = batch.days_of_week.split(",")
            coach_id = batch.coach_id
            batch_id_out = batch.id
        else:
            group_key = f"adhoc-{c.coach_id}-{c.start_time}-{c.end_time}"
            period = derive_period(c.start_time)
            location = "Not scheduled via Batches"
            days_of_week = []
            coach_id = c.coach_id
            batch_id_out = None

        if group_key not in groups:
            group_order.append(group_key)
            groups[group_key] = {
                "period": period,
                "location": location,
                "start_time": c.start_time,
                "end_time": c.end_time,
                "days_of_week": days_of_week,
                "coach_id": coach_id,
                "batch_id": batch_id_out,
                "class_ids": [],
            }
        groups[group_key]["class_ids"].append(c.id)

    session_groups: dict = defaultdict(list)
    for group_key in group_order:
        g = groups[group_key]
        group_class_ids = g["class_ids"]
        group_records = [r for r in records if r.class_id in group_class_ids]
        group_present = sum(1 for r in group_records if r.status == AttendanceStatus.PRESENT)
        group_absent = sum(1 for r in group_records if r.status == AttendanceStatus.ABSENT)
        group_pct = round((group_present / len(group_records)) * 100, 2) if group_records else 0.0

        group_student_ids = sorted({r.student_id for r in group_records})
        group_students = db.query(User).filter(User.id.in_(group_student_ids)).all() if group_student_ids else []
        student_summaries = []
        group_fee_paid = 0
        group_fee_unpaid = 0
        group_fee_revenue = 0.0
        for s in group_students:
            fee = fees_by_student.get(s.id)
            fee_status = fee.status.value if fee else "UNPAID"
            if fee_status == FeeStatus.PAID.value:
                group_fee_paid += 1
                if fee:
                    group_fee_revenue += float(fee.amount)
            else:
                group_fee_unpaid += 1
            student_summaries.append(
                BatchStudentSummary(id=s.id, name=s.name, phone=s.phone, fee_status=fee_status)
            )

        coach = db.query(User).filter(User.id == g["coach_id"]).first() if g["coach_id"] else None
        session_groups[g["period"]].append(
            BatchBreakdown(
                group_key=group_key,
                batch_id=g["batch_id"],
                location=g["location"],
                start_time=str(g["start_time"]),
                end_time=str(g["end_time"]),
                days_of_week=g["days_of_week"],
                coach_id=g["coach_id"],
                coach_name=coach.name if coach else "Unassigned",
                student_count=len(group_student_ids),
                total_classes=len(group_class_ids),
                present_count=group_present,
                absent_count=group_absent,
                attendance_pct=group_pct,
                fee_paid_count=group_fee_paid,
                fee_unpaid_count=group_fee_unpaid,
                fee_revenue=round(group_fee_revenue, 2),
                students=student_summaries,
            )
        )

    period_order = ["MORNING", "AFTERNOON", "EVENING"]
    session_breakdown = []
    for period in period_order:
        if period not in session_groups:
            continue
        period_batches = session_groups[period]
        period_student_ids = {s.id for b in period_batches for s in b.students}
        period_coach_ids = {b.coach_id for b in period_batches if b.coach_id}
        period_present = sum(b.present_count for b in period_batches)
        period_absent = sum(b.absent_count for b in period_batches)
        period_total_marks = period_present + period_absent
        period_pct = round((period_present / period_total_marks) * 100, 2) if period_total_marks else 0.0
        period_fee_paid = sum(1 for b in period_batches for s in b.students if s.fee_status == FeeStatus.PAID.value)
        period_fee_unpaid = sum(1 for b in period_batches for s in b.students if s.fee_status != FeeStatus.PAID.value)
        period_revenue = sum(b.fee_revenue for b in period_batches)

        session_breakdown.append(
            SessionPeriodBreakdown(
                session_period=period,
                total_students=len(period_student_ids),
                total_coaches=len(period_coach_ids),
                total_present=period_present,
                total_absent=period_absent,
                attendance_pct=period_pct,
                fee_paid_count=period_fee_paid,
                fee_unpaid_count=period_fee_unpaid,
                fee_revenue=round(period_revenue, 2),
                batches=period_batches,
            )
        )

    return ActivityDetailReport(
        activity_id=activity.id,
        activity_name=activity.name,
        student_count=student_count,
        total_classes=len(classes),
        total_present=present,
        total_absent=absent,
        attendance_pct=pct,
        revenue_collected=round(revenue_collected, 2),
        fee_paid_count=fee_paid_count,
        fee_unpaid_count=fee_unpaid_count,
        attendance_graph=graph_points,
        coach_breakdown=coach_breakdown,
        session_breakdown=session_breakdown,
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


@router.get("/export/coach-monthly")
def export_coach_monthly_report(
    month: int = Query(default=None, ge=1, le=12),
    year: int = Query(default=None),
    fmt: str = "pdf",
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    """Coach's own monthly report: students grouped by activity, with attendance & fee status.

    Data isolation (requirement #6): always scoped to `current_user`'s own classes, never
    another coach's — there is no coach_id parameter here.
    """
    today = date.today()
    month = month or today.month
    year = year or today.year

    classes = (
        db.query(ClassSession)
        .filter(
            ClassSession.coach_id == current_user.id,
            extract("month", ClassSession.date) == month,
            extract("year", ClassSession.date) == year,
        )
        .all()
    )
    class_ids = [c.id for c in classes]
    records = db.query(StudentAttendance).filter(StudentAttendance.class_id.in_(class_ids)).all() if class_ids else []

    classes_by_activity: dict = defaultdict(list)
    for c in classes:
        classes_by_activity[c.activity_id].append(c)
    activity_ids = list(classes_by_activity.keys())
    activities = {a.id: a for a in db.query(Activity).filter(Activity.id.in_(activity_ids)).all()} if activity_ids else {}

    student_ids = sorted({r.student_id for r in records})
    students = {s.id: s for s in db.query(User).filter(User.id.in_(student_ids)).all()} if student_ids else {}
    fees = {
        f.student_id: f
        for f in db.query(StudentFee)
        .filter(StudentFee.student_id.in_(student_ids), StudentFee.month == month, StudentFee.year == year)
        .all()
    } if student_ids else {}

    sections = []
    for activity_id, activity_classes in classes_by_activity.items():
        activity = activities.get(activity_id)
        activity_class_ids = [c.id for c in activity_classes]
        activity_records = [r for r in records if r.class_id in activity_class_ids]

        records_by_student: dict = defaultdict(list)
        for r in activity_records:
            records_by_student[r.student_id].append(r)

        student_rows = []
        for sid, recs in records_by_student.items():
            student = students.get(sid)
            present = sum(1 for r in recs if r.status == AttendanceStatus.PRESENT)
            absent = sum(1 for r in recs if r.status == AttendanceStatus.ABSENT)
            leave = sum(1 for r in recs if r.status == AttendanceStatus.LEAVE)
            total = len(recs)
            pct = round((present / total) * 100, 2) if total else 0.0
            fee = fees.get(sid)
            student_rows.append(
                {
                    "name": student.name if student else "Unknown",
                    "total": total,
                    "present": present,
                    "absent": absent,
                    "leave": leave,
                    "attendance_pct": pct,
                    "fee_status": fee.status.value if fee else "UNPAID",
                    "fee_amount": float(fee.amount) if fee else 0.0,
                }
            )
        student_rows.sort(key=lambda x: x["name"])
        sections.append({"activity_name": activity.name if activity else "Unknown", "students": student_rows})

    sections.sort(key=lambda s: s["activity_name"])

    if fmt == "csv":
        headers = ["Activity", "Student", "Total Classes", "Present", "Absent", "Leave", "Attendance %", "Fee Status", "Fee Amount"]
        rows = [
            [s["activity_name"], st["name"], st["total"], st["present"], st["absent"], st["leave"], st["attendance_pct"], st["fee_status"], st["fee_amount"]]
            for s in sections
            for st in s["students"]
        ]
        buffer = rows_to_csv(headers, rows)
        filename = f"coach_{current_user.id}_monthly_{year}_{month:02d}.csv"
        return Response(content=buffer.read(), media_type="text/csv", headers={"Content-Disposition": f"attachment; filename={filename}"})

    buffer = build_coach_monthly_report_pdf(coach_name=current_user.name, month=month, year=year, sections=sections)
    filename = f"coach_{current_user.id}_monthly_{year}_{month:02d}.pdf"
    return Response(content=buffer.read(), media_type="application/pdf", headers={"Content-Disposition": f"attachment; filename={filename}"})
