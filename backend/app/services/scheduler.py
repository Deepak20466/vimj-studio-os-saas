import logging
from datetime import date, datetime, timedelta

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.database import SessionLocal
from app.models.attendance import CoachAttendance, CoachAttendanceStatus, StudentAttendance
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.fee import StudentFee, FeeStatus
from app.models.leave import CoachLeave, LeaveStatus
from app.models.salary import CoachSalary
from app.models.user import User, UserRole
from app.services.notifications import notify

logger = logging.getLogger("vimj.scheduler")

scheduler = BackgroundScheduler(timezone="UTC")


def job_monthly_fee_reminders():
    """Runs on the 10th of every month: notify students with unpaid fees for the current period."""
    db = SessionLocal()
    try:
        today = date.today()
        fees = (
            db.query(StudentFee)
            .filter(
                StudentFee.month == today.month,
                StudentFee.year == today.year,
                StudentFee.status != FeeStatus.PAID,
            )
            .all()
        )
        for fee in fees:
            student = db.query(User).filter(User.id == fee.student_id).first()
            if not student or not student.phone:
                continue
            message = (
                f"Hi {student.name}, your VIMJ Studio fee of {fee.amount} for "
                f"{today.month}/{today.year} is due on {fee.due_date}. Please pay at the earliest."
            )
            notify(student.phone, message)
            fee.reminder_sent_at = datetime.utcnow()
        db.commit()
        logger.info("Sent %d fee reminders", len(fees))
    finally:
        db.close()


def job_mark_overdue_fees():
    """Daily: flip UNPAID fees whose due date has passed into OVERDUE."""
    db = SessionLocal()
    try:
        today = date.today()
        updated = (
            db.query(StudentFee)
            .filter(StudentFee.status == FeeStatus.UNPAID, StudentFee.due_date < today)
            .update({StudentFee.status: FeeStatus.OVERDUE})
        )
        db.commit()
        logger.info("Marked %d fees overdue", updated)
    finally:
        db.close()


def job_monthly_salary_notifications():
    """Runs on the 10th of every month: notify coaches their salary is ready for acknowledgment."""
    db = SessionLocal()
    try:
        today = date.today()
        salaries = (
            db.query(CoachSalary)
            .filter(CoachSalary.month == today.month, CoachSalary.year == today.year)
            .all()
        )
        for salary in salaries:
            coach = db.query(User).filter(User.id == salary.coach_id).first()
            if not coach or not coach.phone:
                continue
            message = (
                f"Hi {coach.name}, your VIMJ Studio salary of {salary.amount} for "
                f"{today.month}/{today.year} has been credited. Please acknowledge receipt in the app."
            )
            notify(coach.phone, message)
            salary.notified_at = datetime.utcnow()
        db.commit()
        logger.info("Sent %d salary notifications", len(salaries))
    finally:
        db.close()


def job_coach_attendance_reminders():
    """Runs every minute: reminds coaches 15 min after class end if attendance isn't marked yet."""
    db = SessionLocal()
    try:
        now = datetime.now()
        window_start = now - timedelta(minutes=16)
        window_end = now - timedelta(minutes=15)

        classes = (
            db.query(ClassSession)
            .filter(ClassSession.date == now.date())
            .all()
        )
        for cls in classes:
            class_end_dt = datetime.combine(cls.date, cls.end_time)
            if not (window_start <= class_end_dt <= window_end):
                continue

            enrolled_count = (
                db.query(StudentEnrollment)
                .filter(StudentEnrollment.activity_id == cls.activity_id)
                .count()
            )
            marked_count = (
                db.query(StudentAttendance)
                .filter(StudentAttendance.class_id == cls.id)
                .count()
            )
            if enrolled_count > 0 and marked_count < enrolled_count:
                coach = db.query(User).filter(User.id == cls.coach_id).first()
                if coach and coach.phone:
                    notify(
                        coach.phone,
                        f"Reminder: please mark attendance for your class that ended at {cls.end_time}.",
                    )
        db.commit()
    finally:
        db.close()


def job_end_of_day_missing_report():
    """Runs daily in the evening: compiles coaches who never marked entry/exit and notifies admins."""
    db = SessionLocal()
    try:
        today = date.today()
        coaches_with_classes = (
            db.query(ClassSession.coach_id).filter(ClassSession.date == today).distinct().all()
        )
        coach_ids_today = {row[0] for row in coaches_with_classes}

        marked_ids = {
            row[0]
            for row in db.query(CoachAttendance.coach_id).filter(CoachAttendance.date == today).all()
        }
        on_leave_ids = {
            row[0]
            for row in db.query(CoachLeave.coach_id).filter(
                CoachLeave.status == LeaveStatus.APPROVED,
                CoachLeave.start_date <= today,
                CoachLeave.end_date >= today,
            )
        }

        missing_ids = coach_ids_today - marked_ids - on_leave_ids
        if not missing_ids:
            return

        missing_coaches = db.query(User).filter(User.id.in_(missing_ids)).all()
        names = ", ".join(c.name for c in missing_coaches)

        admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
        for admin in admins:
            if admin.phone:
                notify(admin.phone, f"End-of-day report: coaches with no attendance marked today: {names}")
        logger.info("End-of-day missing report sent for %d coaches", len(missing_coaches))
    finally:
        db.close()


def start_scheduler():
    scheduler.add_job(
        job_monthly_fee_reminders, CronTrigger(day=10, hour=9, minute=0), id="monthly_fee_reminders", replace_existing=True
    )
    scheduler.add_job(
        job_monthly_salary_notifications, CronTrigger(day=10, hour=9, minute=5), id="monthly_salary_notifications", replace_existing=True
    )
    scheduler.add_job(
        job_mark_overdue_fees, CronTrigger(hour=0, minute=30), id="mark_overdue_fees", replace_existing=True
    )
    scheduler.add_job(
        job_coach_attendance_reminders, IntervalTrigger(minutes=1), id="coach_attendance_reminders", replace_existing=True
    )
    scheduler.add_job(
        job_end_of_day_missing_report, CronTrigger(hour=21, minute=0), id="end_of_day_missing_report", replace_existing=True
    )
    scheduler.start()
    logger.info("Scheduler started with %d jobs", len(scheduler.get_jobs()))


def shutdown_scheduler():
    if scheduler.running:
        scheduler.shutdown(wait=False)
