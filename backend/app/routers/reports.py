from datetime import date
from decimal import Decimal
from calendar import monthrange
from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from app.database import get_db
from app.security import require_admin
from app.models.user import User
from app.models.activity import Activity
from app.models.class_session import ClassSession
from app.models.attendance import StudentAttendance
from app.models.enrollment import StudentEnrollment
from app.models.fee import StudentFee, FeeStatus
from app.services.export import rows_to_pdf

router = APIRouter(prefix="/reports", tags=["reports"])

@router.get("")
def report(month: int = Query(ge=1, le=12), year: int = Query(ge=2000, le=2100), kind: str = "summary", fmt: str = "json", db: Session = Depends(get_db), _: User = Depends(require_admin)):
    start, end = date(year, month, 1), date(year, month, monthrange(year, month)[1])
    activities = {a.id: {"activity": a.name, "present": 0, "absent": 0, "leave": 0, "not_confirm": 0, "revenue": Decimal("0")} for a in db.query(Activity).all()}
    records = db.query(StudentAttendance).join(ClassSession).filter(ClassSession.date >= start, ClassSession.date <= end).order_by(ClassSession.date, StudentAttendance.id).all()
    students = []
    for r in records:
        activities[r.class_session.activity_id][r.status.value.lower()] += 1
        students.append([r.class_session.date.isoformat(), r.student.name, r.class_session.activity.name, r.status.value, r.approval_status.value])
    total = Decimal("0")
    products = Decimal("0")
    unassigned = Decimal("0")
    fees = db.query(StudentFee).filter(StudentFee.month == month, StudentFee.year == year, StudentFee.status == FeeStatus.PAID).all()
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
    result = {"month": month, "year": year, "total_revenue": total, "product_revenue": products, "unassigned_revenue": unassigned, "activities": list(activities.values()), "students": students, "revenue_basis": "Paid fees for the selected billing month; multi-activity payments split equally."}
    if fmt != "pdf":
        return result
    if kind == "students":
        headers, rows = ["Date", "Student", "Activity", "Status", "Approval"], students
    elif kind == "attendance":
        headers = ["Activity", "Present", "Absent", "Leave", "Not Confirm"]
        rows = [[a["activity"], a["present"], a["absent"], a["leave"], a["not_confirm"]] for a in activities.values()]
    elif kind == "revenue":
        headers = ["Activity", "Revenue (Rs)"]
        rows = [[a["activity"], a["revenue"]] for a in activities.values()] + [["Unassigned", unassigned], ["Overall revenue", total], ["Products included", products]]
    else:
        raise HTTPException(status_code=400, detail="Unknown report kind")
    pdf = rows_to_pdf(f"{kind.title()} report - {month:02d}/{year}" + ("<br/><font size=9>Paid fees by billing month; multi-activity payments split equally.</font>" if kind == "revenue" else ""), headers, rows)
    return StreamingResponse(pdf, media_type="application/pdf", headers={"Content-Disposition": f"attachment; filename={kind}_{year}_{month:02d}.pdf"})
