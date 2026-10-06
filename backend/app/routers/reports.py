from datetime import date
from decimal import Decimal
from calendar import monthrange
from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.database import get_db
from app.security import require_admin_or_coach
from app.models.user import User, UserRole
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.attendance import StudentAttendance
from app.models.enrollment import StudentEnrollment
from app.models.fee import StudentFee, FeeStatus
from app.models.coach_activity import CoachActivity
from app.services.export import rows_to_pdf

router = APIRouter(prefix="/reports", tags=["reports"])

@router.get("")
def report(month: int = Query(ge=1, le=12), year: int = Query(ge=2000, le=2100), kind: str = "summary", fmt: str = "json", day: int | None = Query(default=None, ge=1, le=31), db: Session = Depends(get_db), current_user: User = Depends(require_admin_or_coach)):
    start, end = date(year, month, 1), date(year, month, monthrange(year, month)[1])
    activities_query = db.query(Activity)
    if current_user.role == UserRole.COACH:
        activities_query = activities_query.join(CoachActivity).filter(CoachActivity.coach_id == current_user.id)
    activities = {a.id: {"activity": a.name, "present": 0, "absent": 0, "leave": 0, "not_confirm": 0, "revenue": Decimal("0")} for a in activities_query.all()}
    records_query = db.query(StudentAttendance).join(ClassSession).filter(ClassSession.date >= start, ClassSession.date <= end)
    if current_user.role == UserRole.COACH:
        records_query = records_query.filter(StudentAttendance.coach_id == current_user.id)
    if day:
        if day > monthrange(year, month)[1]:
            raise HTTPException(status_code=400, detail="Day is outside the selected month")
        records_query = records_query.filter(ClassSession.date == date(year, month, day))
    records = records_query.order_by(ClassSession.date, StudentAttendance.id).all()
    students = []
    for r in records:
        if r.class_session.activity_id in activities:
            activities[r.class_session.activity_id][r.status.value.lower()] += 1
        students.append([r.class_session.date.isoformat(), r.student.name, r.class_session.activity.name, r.status.value, r.approval_status.value])
    total = Decimal("0")
    products = Decimal("0")
    unassigned = Decimal("0")
    fees = db.query(StudentFee).filter(StudentFee.month == month, StudentFee.year == year, StudentFee.status == FeeStatus.PAID).all() if current_user.role == UserRole.ADMIN else []
    for fee in fees:
        amount = fee.amount + fee.product_amount
        total += amount
        products += fee.product_amount
        ids = [aid for (aid,) in db.query(StudentEnrollment.activity_id).filter(StudentEnrollment.student_id == fee.student_id).all()]
        if not ids:
            unassigned += amount
        else:
            # Split multi-activity student payments equally; never count the same payment twice.
            share = (amount / len(ids)).quantize(Decimal("0.01"))
            for i, aid in enumerate(ids):
                activities[aid]["revenue"] += amount - share * (len(ids) - 1) if i == len(ids) - 1 else share
    class_query = db.query(ClassSession).filter(ClassSession.date >= start, ClassSession.date <= end)
    if current_user.role == UserRole.COACH:
        class_query = class_query.filter(ClassSession.coach_id == current_user.id)
    if day:
        class_query = class_query.filter(ClassSession.date == date(year, month, day))
    class_sessions = class_query.join(StudentAttendance, StudentAttendance.class_id == ClassSession.id).distinct().all()
    class_count_by_day = {}
    for cls in class_sessions:
        key = cls.date.isoformat()
        class_count_by_day[key] = class_count_by_day.get(key, 0) + 1
    for record in records:
        class_count_by_day.setdefault(record.class_session.date.isoformat(), 0)
    fee_query = db.query(StudentFee).filter(StudentFee.month == month, StudentFee.year == year)
    if current_user.role == UserRole.COACH:
        coach_student_ids = select(StudentEnrollment.student_id).join(
            CoachActivity, CoachActivity.activity_id == StudentEnrollment.activity_id
        ).filter(CoachActivity.coach_id == current_user.id).distinct()
        fee_query = fee_query.filter(StudentFee.student_id.in_(coach_student_ids))
    fee_records = fee_query.order_by(StudentFee.student_id).all()
    fee_paid_total = sum((f.amount + f.product_amount for f in fee_records if f.status == FeeStatus.PAID), Decimal("0"))
    fee_pending_total = sum((f.balance_amount for f in fee_records if f.balance_amount > 0), Decimal("0"))
    fee_rows_paid = [[f.student.name if f.student else "Unknown", f"{month:02d}/{year}", f.amount + f.product_amount, f.paid_date or "-"] for f in fee_records if f.status == FeeStatus.PAID]
    fee_rows_pending = [[f.student.name if f.student else "Unknown", f"{month:02d}/{year}", f.balance_amount, f.status.value] for f in fee_records if f.balance_amount > 0]
    result = {"month": month, "year": year, "day": day, "classes_done": len(class_sessions), "classes_by_day": class_count_by_day, "fee_paid_total": fee_paid_total, "fee_pending_total": fee_pending_total, "fee_paid_count": len(fee_rows_paid), "fee_pending_count": len(fee_rows_pending), "total_revenue": total, "product_revenue": products, "unassigned_revenue": unassigned, "activities": list(activities.values()), "students": students, "revenue_basis": "Paid fees for the selected billing month; multi-activity payments split equally."}
    if fmt != "pdf":
        return result
    if kind == "students":
        headers, rows = ["Date", "Student", "Activity", "Status", "Approval"], students
    elif kind == "students_summary":
        headers, rows = ["Date", "Student", "Activity", "Status", "Approval"], students
    elif kind == "attendance":
        headers = ["Activity", "Present", "Absent", "Leave", "Not Confirm"]
        rows = [[a["activity"], a["present"], a["absent"], a["leave"], a["not_confirm"]] for a in activities.values()]
    elif kind == "revenue":
        headers = ["Activity", "Revenue (Rs)"]
        rows = [[a["activity"], a["revenue"]] for a in activities.values()] + [["Unassigned", unassigned], ["Overall revenue", total], ["Products included", products]]
    elif kind == "classes":
        headers, rows = ["Date", "Classes Done"], [[d, count] for d, count in sorted(class_count_by_day.items())]
        rows.append(["Total", len(class_sessions)])
    elif kind == "classes_detail":
        headers = ["Class Time", "Activity", "Student", "Status", "Approval"]
        rows = []
        session_records = {}
        for record in records:
            session_records.setdefault(record.class_id, []).append(record)
        for cls in class_sessions:
            time_label = f"{cls.start_time.strftime('%H:%M')} - {cls.end_time.strftime('%H:%M')}"
            class_records = session_records.get(cls.id, [])
            if not class_records:
                rows.append([time_label, cls.activity.name if cls.activity else "Unknown", "No attendance marked", "-", "-"])
            else:
                for record in class_records:
                    rows.append([time_label, cls.activity.name if cls.activity else "Unknown", record.student.name if record.student else "Unknown", record.status.value, record.approval_status.value])
        rows.append(["Total classes", len(class_sessions), "Student attendance records", len(records), ""])
    elif kind == "attendance_summary":
        headers = ["Date", "Classes Done", "Student Attendance Records"]
        rows = [[d, count, sum(1 for r in records if r.class_session.date.isoformat() == d)] for d, count in sorted(class_count_by_day.items())]
        rows.append(["Total", len(class_sessions), len(records)])
    elif kind == "fees_paid":
        headers, rows = ["Student", "Period", "Amount Paid", "Paid Date"], fee_rows_paid
        rows.append(["TOTAL", "", fee_paid_total, ""])
    elif kind == "fees_pending":
        headers, rows = ["Student", "Period", "Balance Pending", "Status"], fee_rows_pending
        rows.append(["TOTAL", "", fee_pending_total, ""])
    else:
        raise HTTPException(status_code=400, detail="Unknown report kind")
    title_period = date(year, month, day).isoformat() if kind in {"classes", "classes_detail"} and day else f"{month:02d}/{year}"
    summary_note = f"<br/><font size=9>Completed classes: {len(class_sessions)}; student attendance records: {len(records)}.</font>" if kind == "students_summary" else ""
    pdf = rows_to_pdf(f"{kind.replace('_', ' ').title()} report - {title_period}" + summary_note + ("<br/><font size=9>Paid fees by billing month; multi-activity payments split equally.</font>" if kind == "revenue" else ""), headers, rows)
    suffix = f"_{date(year, month, day).isoformat()}" if kind in {"classes", "classes_detail"} and day else f"_{year}_{month:02d}"
    return StreamingResponse(pdf, media_type="application/pdf", headers={"Content-Disposition": f"attachment; filename={kind}{suffix}.pdf"})
