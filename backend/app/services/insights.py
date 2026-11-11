"""Local, rule-based revenue and attendance insights shared by the API and MCP."""

from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import case, func
from sqlalchemy.orm import Session

from app.models.activity import Activity
from app.models.attendance import AttendanceStatus, StudentAttendance
from app.models.batch import Batch
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.fee import FeeStatus, StudentFee
from app.models.user import User, UserRole


def _number(value) -> float:
    return round(float(value or 0), 2)


def overdue_fees(db: Session, days_overdue: int = 7, today: date | None = None):
    today = today or date.today()
    cutoff = today - timedelta(days=days_overdue)
    return (
        db.query(StudentFee)
        .filter(
            StudentFee.status.in_([FeeStatus.UNPAID, FeeStatus.OVERDUE]),
            StudentFee.balance_amount > 0,
            StudentFee.due_date < cutoff,
        )
        .order_by(StudentFee.due_date, StudentFee.id)
        .all()
    )


def fee_defaulters(db: Session, days_overdue: int = 7, today: date | None = None) -> dict:
    fees = overdue_fees(db, days_overdue, today)
    student_ids = {fee.student_id for fee in fees}
    students = {
        user.id: user.name
        for user in db.query(User).filter(User.id.in_(student_ids)).all()
    } if student_ids else {}

    by_student: dict[int, dict] = {}
    for fee in fees:
        row = by_student.setdefault(
            fee.student_id,
            {"student_id": fee.student_id, "student_name": students.get(fee.student_id, "Unknown"), "pending_amount": 0.0, "fee_ids": [], "fees": []},
        )
        balance = _number(fee.balance_amount)
        row["pending_amount"] = _number(row["pending_amount"] + balance)
        row["fee_ids"].append(fee.id)
        row["fees"].append({"fee_id": fee.id, "month": fee.month, "year": fee.year, "due_date": fee.due_date.isoformat(), "pending_amount": balance})

    return {
        "days_overdue": days_overdue,
        "students": list(by_student.values()),
        "total_pending": _number(sum((Decimal(str(row["pending_amount"])) for row in by_student.values()), Decimal("0"))),
    }


def _batch_attendance_rate(db: Session, class_session: ClassSession) -> float | None:
    records = (
        db.query(StudentAttendance)
        .filter(
            StudentAttendance.class_id == class_session.id,
            StudentAttendance.status != AttendanceStatus.NOT_CONFIRM,
        )
        .all()
    )
    if not records:
        return None
    present = sum(record.status == AttendanceStatus.PRESENT for record in records)
    return (present / len(records)) * 100


def batch_analytics(db: Session, today: date | None = None) -> dict:
    today = today or date.today()
    activities = {activity.id: activity for activity in db.query(Activity).all()}
    enrollments: dict[int, int] = {}
    for activity_id, count in (
        db.query(StudentEnrollment.activity_id, func.count(StudentEnrollment.id))
        .group_by(StudentEnrollment.activity_id)
        .all()
    ):
        enrollments[activity_id] = int(count)

    batches = db.query(Batch).filter(Batch.is_active.is_(True)).order_by(Batch.id).all()
    active_counts: dict[int, int] = {}
    for batch in batches:
        active_counts[batch.activity_id] = active_counts.get(batch.activity_id, 0) + 1

    batch_ids = [batch.id for batch in batches]
    sessions_by_batch: dict[int, list[tuple[int, date]]] = {}
    attendance_rate_by_session: dict[int, float] = {}
    if batch_ids:
        sessions = (
            db.query(ClassSession.id, ClassSession.batch_id, ClassSession.date)
            .filter(ClassSession.batch_id.in_(batch_ids), ClassSession.date <= today)
            .order_by(ClassSession.date.desc(), ClassSession.start_time.desc())
            .all()
        )
        session_ids = [class_session_id for class_session_id, _, _ in sessions]
        for class_session_id, batch_id, session_date in sessions:
            sessions_by_batch.setdefault(batch_id, []).append((class_session_id, session_date))

        if session_ids:
            attendance_counts = (
                db.query(
                    StudentAttendance.class_id,
                    func.count(StudentAttendance.id),
                    func.sum(
                        case(
                            (StudentAttendance.status == AttendanceStatus.PRESENT, 1),
                            else_=0,
                        )
                    ),
                )
                .filter(
                    StudentAttendance.class_id.in_(session_ids),
                    StudentAttendance.status != AttendanceStatus.NOT_CONFIRM,
                )
                .group_by(StudentAttendance.class_id)
                .all()
            )
            attendance_rate_by_session = {
                class_id: present_count / record_count * 100
                for class_id, record_count, present_count in attendance_counts
                if record_count
            }

    rows: list[dict] = []
    drop_rows: list[dict] = []
    for batch in batches:
        activity = activities.get(batch.activity_id)
        if activity is None:
            continue
        name = f"{activity.name} · {batch.session_period.value.title()}"
        rates_by_session = []
        for class_session_id, session_date in sessions_by_batch.get(batch.id, []):
            rate = attendance_rate_by_session.get(class_session_id)
            if rate is not None:
                rates_by_session.append((session_date, rate))
        rates_by_session.sort(key=lambda item: item[0])

        recent_rates = [rate for _, rate in rates_by_session[-3:]]
        attendance_pct = sum(recent_rates) / len(recent_rates) if recent_rates else 0.0
        rates_by_weekday: dict[int, list[float]] = {}
        for session_date, rate in rates_by_session:
            rates_by_weekday.setdefault(session_date.weekday(), []).append(rate)
        weekday_names = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
        drop_trends = []
        for weekday, weekday_rates in rates_by_weekday.items():
            if len(weekday_rates) < 6:
                continue
            baseline_rates = weekday_rates[-6:-3]
            weekday_recent_rates = weekday_rates[-3:]
            baseline_pct = sum(baseline_rates) / 3
            latest_pct = sum(weekday_recent_rates) / 3
            if baseline_pct > 0 and all(rate < baseline_pct * 0.7 for rate in weekday_recent_rates):
                drop_trends.append((weekday_names[weekday], baseline_pct, latest_pct))
        dropped = bool(drop_trends)
        drop_pct = max((baseline - latest for _, baseline, latest in drop_trends), default=0.0)
        drop_ratio = max(((baseline - latest) / baseline for _, baseline, latest in drop_trends), default=0.0)

        activity_batch_count = max(active_counts.get(batch.activity_id, 1), 1)
        monthly_fee = Decimal(str(activity.monthly_fee or 0))
        roster_size = enrollments.get(batch.activity_id, 0)
        # Fees belong to activities, not individual batches. Divide the activity's
        # projected tuition evenly across its active batches as an estimate.
        estimated_profit = (monthly_fee * roster_size) / activity_batch_count
        revenue_at_risk = estimated_profit * Decimal(str(drop_ratio))
        row = {
            "batch_id": batch.id,
            "batch_name": name,
            "estimated_profit": _number(estimated_profit),
            "attendance_pct": round(attendance_pct, 2),
            "attendance_drop_pct": round(drop_pct, 2),
            "attendance_drop_weekdays": [weekday for weekday, _, _ in drop_trends],
            "revenue_at_risk": _number(revenue_at_risk),
        }
        rows.append(row)
        if dropped:
            drop_rows.append(row)

    most_profitable = max(rows, key=lambda row: row["estimated_profit"], default=None)
    return {
        "most_profitable_batch": most_profitable,
        "attendance_drop_batches": drop_rows,
        "total_revenue_at_risk": _number(sum((Decimal(str(row["revenue_at_risk"])) for row in drop_rows), Decimal("0"))),
        "batches": rows,
    }


def _month_offsets(today: date, count: int = 3) -> list[tuple[int, int]]:
    month, year = today.month, today.year
    result = []
    for _ in range(count):
        result.append((month, year))
        month -= 1
        if month == 0:
            month, year = 12, year - 1
    return list(reversed(result))


def revenue_risk_insights(
    db: Session,
    today: date | None = None,
    period: str | None = None,
    selected_date: date | None = None,
    selected_month: int | None = None,
    selected_year: int | None = None,
) -> dict:
    today = today or date.today()
    selected_date = selected_date or today
    selected_month = selected_month or selected_date.month
    selected_year = selected_year or selected_date.year
    if period == "month":
        reference_date = date(selected_year, selected_month, 1) + timedelta(days=32)
        reference_date = reference_date.replace(day=1) - timedelta(days=1)
    elif period == "year":
        reference_date = date(selected_year, 12, 31)
    elif period == "day":
        reference_date = selected_date
    else:
        reference_date = today

    def in_period(fee: StudentFee) -> bool:
        if period == "month":
            return fee.month == selected_month and fee.year == selected_year
        if period == "year":
            return fee.year == selected_year
        if period == "day":
            return fee.due_date <= selected_date
        return True

    selected_overdue = [
        fee for fee in overdue_fees(db, days_overdue=7, today=reference_date)
        if in_period(fee)
    ]
    selected_fee_ids = {fee.id for fee in selected_overdue}
    all_defaults = fee_defaulters(db, days_overdue=7, today=reference_date)
    defaults = {"days_overdue": 7, "students": [], "total_pending": 0.0}
    for row in all_defaults["students"]:
        selected_fees = [fee for fee in row["fees"] if fee["fee_id"] in selected_fee_ids]
        if selected_fees:
            amount = _number(sum(
                (Decimal(str(fee["pending_amount"])) for fee in selected_fees),
                Decimal("0"),
            ))
            defaults["students"].append({
                **row,
                "fees": selected_fees,
                "fee_ids": [fee["fee_id"] for fee in selected_fees],
                "pending_amount": amount,
            })
    defaults["total_pending"] = _number(sum(
        (fee.balance_amount for fee in selected_overdue), Decimal("0")
    ))
    batch_data = batch_analytics(db, today=reference_date)
    default_fee_ids = [fee_id for row in defaults["students"] for fee_id in row["fee_ids"]]
    default_student_ids = [row["student_id"] for row in defaults["students"]]
    drop_batch_ids = {row["batch_id"] for row in batch_data["attendance_drop_batches"]}
    drop_student_ids = sorted({
        enrollment.student_id
        for enrollment in db.query(StudentEnrollment).join(Batch, Batch.activity_id == StudentEnrollment.activity_id)
        .filter(Batch.id.in_(drop_batch_ids)).all()
    }) if drop_batch_ids else []

    months = _month_offsets(reference_date, 3)
    monthly_collections = []
    for month, year in months:
        fees = (
            db.query(StudentFee)
            .filter(StudentFee.status == FeeStatus.PAID, StudentFee.month == month, StudentFee.year == year)
            .all()
        )
        monthly_collections.append(sum((fee.amount + fee.product_amount for fee in fees), Decimal("0")))
    forecast = _number(sum(monthly_collections, Decimal("0")) / 3)

    drop_names = [row["batch_name"] for row in batch_data["attendance_drop_batches"]]
    if defaults["students"]:
        default_message = f"{len(defaults['students'])} student(s) have fees overdue by more than 7 days."
    else:
        default_message = "No fees are overdue by more than 7 days."
    if drop_names:
        attendance_message = "Attendance is down more than 30% across three recent same-weekday sessions in: " + ", ".join(drop_names) + "."
    else:
        attendance_message = "No batch has a sustained attendance drop above 30%."

    total_at_risk = _number(Decimal(str(defaults["total_pending"])) + Decimal(str(batch_data["total_revenue_at_risk"])))
    students_pending = [fee for fee in (
        db.query(StudentFee)
        .filter(StudentFee.status.in_([FeeStatus.UNPAID, FeeStatus.OVERDUE]), StudentFee.balance_amount > 0)
        .all()
    ) if in_period(fee)]
    attendance_query = db.query(StudentAttendance).join(
        ClassSession, ClassSession.id == StudentAttendance.class_id
    ).filter(StudentAttendance.status == AttendanceStatus.PRESENT)
    if period in (None, "day"):
        attendance_query = attendance_query.filter(ClassSession.date == selected_date)
    elif period == "month":
        attendance_query = attendance_query.filter(
            ClassSession.date >= date(selected_year, selected_month, 1),
            ClassSession.date <= reference_date,
        )
    elif period == "year":
        attendance_query = attendance_query.filter(
            ClassSession.date >= date(selected_year, 1, 1),
            ClassSession.date <= reference_date,
        )
    today_present = attendance_query.count()

    risks = [
        {
            "type": "fee_default",
            "message": default_message,
            "revenue_at_risk": defaults["total_pending"],
            "student_ids": default_student_ids,
            "fee_ids": default_fee_ids,
            "students": defaults["students"],
        },
        {
            "type": "attendance_drop",
            "message": attendance_message,
            "revenue_at_risk": batch_data["total_revenue_at_risk"],
            "student_ids": drop_student_ids,
            "fee_ids": [],
            "batches": batch_data["attendance_drop_batches"],
        },
        {
            "type": "revenue_forecast",
            "message": f"Rule-based forecast from the last three monthly collections: Rs {forecast:,.2f}.",
            "revenue_at_risk": 0.0,
            "student_ids": [],
            "fee_ids": [],
        },
    ]
    result = {
        "risks": risks,
        "forecast": {
            "next_month_revenue": forecast,
            "months_used": [f"{year}-{month:02d}" for month, year in months],
            "monthly_collections": [
                {"month": f"{year}-{month:02d}", "collected": _number(amount)}
                for (month, year), amount in zip(months, monthly_collections)
            ],
        },
        "summary": {"total_at_risk": total_at_risk},
        "kpis": {
            "total_students": db.query(User).filter(User.role == UserRole.STUDENT).count(),
            "today_present": today_present,
            "fee_pending_amount": _number(sum((fee.balance_amount for fee in students_pending), Decimal("0"))),
        },
        "batch_analytics": batch_data,
    }
    if period is not None:
        result["period"] = {
            "type": period,
            "date": selected_date.isoformat(),
            "month": selected_month,
            "year": selected_year,
        }
    return result
