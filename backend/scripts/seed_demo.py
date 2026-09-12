"""Populate the database with realistic demo data across all entities.

Run after seed_admin.py: python scripts/seed_demo.py
Idempotent — safe to re-run; skips users/records that already exist.
"""
import sys
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import SessionLocal
from app.models.activity import Activity
from app.models.attendance import (
    AttendanceStatus,
    CoachAttendance,
    CoachAttendanceStatus,
    StudentAttendance,
)
from app.models.class_session import ClassSession
from app.models.coach_activity import CoachActivity
from app.models.enrollment import StudentEnrollment
from app.models.fee import FeeStatus, StudentFee
from app.models.user import User, UserRole
from app.security import hash_password

FACILITY_LAT = 12.9716
FACILITY_LNG = 77.5946

COACHES = [
    ("coach.arjun@vimj.com", "Arjun Rao", "+919800000001"),
    ("coach.meera@vimj.com", "Meera Nair", "+919800000002"),
    ("coach.vikram@vimj.com", "Vikram Singh", "+919800000003"),
]

STUDENTS = [
    ("student.aarav@vimj.com", "Aarav Kumar", "+919800001001"),
    ("student.diya@vimj.com", "Diya Sharma", "+919800001002"),
    ("student.kabir@vimj.com", "Kabir Mehta", "+919800001003"),
    ("student.ishita@vimj.com", "Ishita Patel", "+919800001004"),
    ("student.rohan@vimj.com", "Rohan Gupta", "+919800001005"),
    ("student.sara@vimj.com", "Sara Khan", "+919800001006"),
    ("student.vivaan@vimj.com", "Vivaan Reddy", "+919800001007"),
    ("student.ananya@vimj.com", "Ananya Iyer", "+919800001008"),
]

ACTIVITIES = [
    ("Badminton", 20, Decimal("1500.00")),
    ("Swimming", 15, Decimal("2000.00")),
    ("Football", 25, Decimal("1200.00")),
]

DEFAULT_PASSWORD = "Password123!"


def get_or_create_user(db, email, name, phone, role):
    user = db.query(User).filter(User.email == email).first()
    if user:
        return user
    user = User(
        email=email,
        password_hash=hash_password(DEFAULT_PASSWORD),
        name=name,
        phone=phone,
        role=role,
    )
    db.add(user)
    db.flush()
    return user


def main():
    db = SessionLocal()
    try:
        coaches = [get_or_create_user(db, e, n, p, UserRole.COACH) for e, n, p in COACHES]
        students = [get_or_create_user(db, e, n, p, UserRole.STUDENT) for e, n, p in STUDENTS]
        db.commit()

        activities = []
        for name, capacity, fee in ACTIVITIES:
            act = db.query(Activity).filter(Activity.name == name).first()
            if not act:
                act = Activity(
                    name=name,
                    capacity=capacity,
                    location_lat=FACILITY_LAT,
                    location_lng=FACILITY_LNG,
                    monthly_fee=fee,
                )
                db.add(act)
                db.flush()
            activities.append(act)
        db.commit()

        # Assign each activity's round-robin coach (same pairing the classes loop below
        # uses) so coaches actually see their roster/classes in the dashboard.
        for idx, activity in enumerate(activities):
            coach = coaches[idx % len(coaches)]
            exists = (
                db.query(CoachActivity)
                .filter(CoachActivity.coach_id == coach.id, CoachActivity.activity_id == activity.id)
                .first()
            )
            if not exists:
                db.add(CoachActivity(coach_id=coach.id, activity_id=activity.id))
        db.commit()

        # Enroll students round-robin across activities
        for i, student in enumerate(students):
            activity = activities[i % len(activities)]
            exists = (
                db.query(StudentEnrollment)
                .filter(StudentEnrollment.student_id == student.id, StudentEnrollment.activity_id == activity.id)
                .first()
            )
            if not exists:
                db.add(StudentEnrollment(student_id=student.id, activity_id=activity.id))
        db.commit()

        # Classes for the last 14 days, one per activity per weekday, coach round-robin
        today = date.today()
        class_times = [(time(7, 0), time(8, 0)), (time(17, 0), time(18, 0)), (time(18, 30), time(19, 30))]
        created_classes = []
        for day_offset in range(14, -1, -1):
            d = today - timedelta(days=day_offset)
            if d.weekday() == 6:  # skip Sundays
                continue
            for idx, activity in enumerate(activities):
                coach = coaches[idx % len(coaches)]
                start, end = class_times[idx % len(class_times)]
                existing = (
                    db.query(ClassSession)
                    .filter(
                        ClassSession.activity_id == activity.id,
                        ClassSession.date == d,
                        ClassSession.coach_id == coach.id,
                    )
                    .first()
                )
                if not existing:
                    existing = ClassSession(
                        activity_id=activity.id, coach_id=coach.id, date=d, start_time=start, end_time=end
                    )
                    db.add(existing)
                    db.flush()
                created_classes.append(existing)
        db.commit()

        # Student attendance for past classes (skip today/future), ~90% present
        enrollment_map = {}
        for enr in db.query(StudentEnrollment).all():
            enrollment_map.setdefault(enr.activity_id, []).append(enr.student_id)

        import random

        random.seed(42)
        for cls in created_classes:
            if cls.date >= today:
                continue
            roster = enrollment_map.get(cls.activity_id, [])
            for student_id in roster:
                exists = (
                    db.query(StudentAttendance)
                    .filter(StudentAttendance.class_id == cls.id, StudentAttendance.student_id == student_id)
                    .first()
                )
                if exists:
                    continue
                roll = random.random()
                status = AttendanceStatus.PRESENT if roll < 0.85 else (
                    AttendanceStatus.LEAVE if roll < 0.93 else AttendanceStatus.ABSENT
                )
                db.add(
                    StudentAttendance(
                        student_id=student_id,
                        class_id=cls.id,
                        status=status,
                        coach_id=cls.coach_id,
                        location_lat=FACILITY_LAT,
                        location_lng=FACILITY_LNG,
                        marked_manually=0,
                    )
                )
        db.commit()

        # Coach entry/exit attendance for past days
        coach_class_days = {}
        for cls in created_classes:
            if cls.date >= today:
                continue
            coach_class_days.setdefault((cls.coach_id, cls.date), cls)

        for (coach_id, d), cls in coach_class_days.items():
            exists = (
                db.query(CoachAttendance)
                .filter(CoachAttendance.coach_id == coach_id, CoachAttendance.date == d)
                .first()
            )
            if exists:
                continue
            entry_dt = datetime.combine(d, cls.start_time) - timedelta(minutes=10)
            exit_dt = datetime.combine(d, cls.end_time) + timedelta(minutes=5)
            db.add(
                CoachAttendance(
                    coach_id=coach_id,
                    date=d,
                    entry_time=entry_dt,
                    exit_time=exit_dt,
                    entry_lat=FACILITY_LAT,
                    entry_lng=FACILITY_LNG,
                    exit_lat=FACILITY_LAT,
                    exit_lng=FACILITY_LNG,
                    activity_id=cls.activity_id,
                    status=CoachAttendanceStatus.PRESENT,
                )
            )
        db.commit()

        # Fees: current month + last month, mixed status
        for i, student in enumerate(students):
            for month_offset in (0, 1):
                target = today.replace(day=1) - timedelta(days=1) if month_offset == 1 else today
                month, year = (target.month, target.year) if month_offset == 1 else (today.month, today.year)
                exists = (
                    db.query(StudentFee)
                    .filter(StudentFee.student_id == student.id, StudentFee.month == month, StudentFee.year == year)
                    .first()
                )
                if exists:
                    continue
                activity = activities[i % len(activities)]
                due = date(year, month, 10)
                if month_offset == 1 or i % 3 != 0:
                    status = FeeStatus.PAID
                    paid_date = due
                elif i % 3 == 1:
                    status = FeeStatus.OVERDUE
                    paid_date = None
                else:
                    status = FeeStatus.UNPAID
                    paid_date = None
                db.add(
                    StudentFee(
                        student_id=student.id,
                        month=month,
                        year=year,
                        amount=activity.monthly_fee,
                        status=status,
                        due_date=due,
                        paid_date=paid_date,
                    )
                )
        db.commit()

        print("Demo data seeded.")
        print(f"  Coaches:   {len(coaches)} (password: {DEFAULT_PASSWORD})")
        print(f"  Students:  {len(students)} (password: {DEFAULT_PASSWORD})")
        print(f"  Activities: {len(activities)}")
        print(f"  Classes:   {len(created_classes)}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
