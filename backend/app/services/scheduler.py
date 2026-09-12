import logging
from datetime import date, datetime, timedelta

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.database import SessionLocal
from app.models.attendance import CoachAttendance, CoachAttendanceStatus, StudentAttendance
from app.models.batch import Batch
from app.models.class_session import ClassSession
from app.models.enrollment import StudentEnrollment
from app.models.fee import StudentFee, FeeStatus
from app.models.user import User, UserRole
from app.services.batches import generate_sessions_for_batch
from app.services.notifications import notify, notify_and_push, fee_reminder_message

logger = logging.getLogger("vimj.scheduler")

scheduler = BackgroundScheduler(timezone="UTC")

BATCH_AUTO_GENERATE_DAYS_AHEAD = 30


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
            message = fee_reminder_message(student.name, fee.month, fee.year, fee.amount, fee.due_date)
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
                if coach:
                    notify_and_push(
                        db,
                        coach,
                        f"Reminder: please mark attendance for your class that ended at {cls.end_time}.",
                        "Mark attendance",
                        "ATTENDANCE_REMINDER",
                        link="/coach/classes",
                        delay_minutes=15,
                    )
        db.commit()
    finally:
        db.close()


def job_pre_session_attendance_reminder():
    """Runs every minute: 5 min before a class starts, nudges the coach that attendance
    marking for this session is coming up (bell + SMS/WhatsApp on both dashboards)."""
    db = SessionLocal()
    try:
        now = datetime.now()
        window_start = now + timedelta(minutes=5)
        window_end = now + timedelta(minutes=6)

        classes = db.query(ClassSession).filter(ClassSession.date == now.date()).all()
        for cls in classes:
            class_start_dt = datetime.combine(cls.date, cls.start_time)
            if not (window_start <= class_start_dt < window_end):
                continue
            coach = db.query(User).filter(User.id == cls.coach_id).first()
            if not coach:
                continue
            activity_name = cls.activity.name if cls.activity else "class"
            notify_and_push(
                db,
                coach,
                f"Your {activity_name} class starts in 5 minutes at {cls.start_time}. Be ready to mark attendance.",
                "Session starting soon",
                "PRE_SESSION_REMINDER",
                delay_minutes=-5,
            )
        db.commit()
    finally:
        db.close()


def job_coach_before_class_reminder():
    """Runs every minute: reminds coaches 10 min before their class starts."""
    db = SessionLocal()
    try:
        now = datetime.now()
        window_start = now + timedelta(minutes=10)
        window_end = now + timedelta(minutes=11)

        classes = db.query(ClassSession).filter(ClassSession.date == now.date()).all()
        for cls in classes:
            class_start_dt = datetime.combine(cls.date, cls.start_time)
            if not (window_start <= class_start_dt < window_end):
                continue
            coach = db.query(User).filter(User.id == cls.coach_id).first()
            if coach:
                notify_and_push(
                    db,
                    coach,
                    f"Reminder: your {cls.activity.name if cls.activity else 'class'} class starts at {cls.start_time}.",
                    "Class starting soon",
                    "PRE_CLASS_REMINDER",
                    link="/coach/classes",
                    delay_minutes=-10,
                )
        db.commit()
    finally:
        db.close()


def job_coach_entry_missing_alert():
    """Runs every minute: 10 min after a coach's first class of the day starts, alerts admins
    if the coach still hasn't recorded a facility entry (check-in) for today."""
    db = SessionLocal()
    try:
        now = datetime.now()
        today = now.date()
        classes = db.query(ClassSession).filter(ClassSession.date == today).all()
        if not classes:
            return

        first_class_by_coach: dict = {}
        for cls in classes:
            current = first_class_by_coach.get(cls.coach_id)
            if current is None or cls.start_time < current.start_time:
                first_class_by_coach[cls.coach_id] = cls

        admins = None
        for coach_id, cls in first_class_by_coach.items():
            class_start_dt = datetime.combine(cls.date, cls.start_time)
            window_start = class_start_dt + timedelta(minutes=10)
            window_end = class_start_dt + timedelta(minutes=11)
            if not (window_start <= now < window_end):
                continue

            has_entry = (
                db.query(CoachAttendance)
                .filter(
                    CoachAttendance.coach_id == coach_id,
                    CoachAttendance.date == today,
                    CoachAttendance.entry_time.isnot(None),
                )
                .first()
            )
            if has_entry:
                continue

            if admins is None:
                admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
            coach = db.query(User).filter(User.id == coach_id).first()
            coach_name = coach.name if coach else "Unknown coach"
            for admin in admins:
                notify_and_push(
                    db,
                    admin,
                    f"Facility entry not recorded: {coach_name} has not checked in ahead of their "
                    f"{cls.start_time} class today.",
                    "Missing facility entry",
                    "COACH_ENTRY_MISSING",
                    link="/attendance",
                )
        db.commit()
    finally:
        db.close()


def job_coach_exit_missing_alert():
    """Runs every minute: 15 min after a coach's last class of the day ends, alerts admins
    if the coach still hasn't recorded a facility exit (check-out) for today."""
    db = SessionLocal()
    try:
        now = datetime.now()
        today = now.date()
        classes = db.query(ClassSession).filter(ClassSession.date == today).all()
        if not classes:
            return

        last_class_by_coach: dict = {}
        for cls in classes:
            current = last_class_by_coach.get(cls.coach_id)
            if current is None or cls.end_time > current.end_time:
                last_class_by_coach[cls.coach_id] = cls

        admins = None
        for coach_id, cls in last_class_by_coach.items():
            class_end_dt = datetime.combine(cls.date, cls.end_time)
            window_start = class_end_dt + timedelta(minutes=15)
            window_end = class_end_dt + timedelta(minutes=16)
            if not (window_start <= now < window_end):
                continue

            has_exit = (
                db.query(CoachAttendance)
                .filter(
                    CoachAttendance.coach_id == coach_id,
                    CoachAttendance.date == today,
                    CoachAttendance.exit_time.isnot(None),
                )
                .first()
            )
            if has_exit:
                continue

            if admins is None:
                admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
            coach = db.query(User).filter(User.id == coach_id).first()
            coach_name = coach.name if coach else "Unknown coach"
            for admin in admins:
                notify_and_push(
                    db,
                    admin,
                    f"Facility exit not recorded: {coach_name} has not checked out after their "
                    f"{cls.end_time} class today.",
                    "Missing facility exit",
                    "COACH_EXIT_MISSING",
                    link="/attendance",
                )
        db.commit()
    finally:
        db.close()


def job_missed_attendance_admin_alert():
    """Runs every minute: 10 min after class end, alerts admins if attendance still isn't submitted."""
    db = SessionLocal()
    try:
        now = datetime.now()
        window_start = now - timedelta(minutes=11)
        window_end = now - timedelta(minutes=10)

        classes = db.query(ClassSession).filter(ClassSession.date == now.date()).all()
        admins = None
        for cls in classes:
            class_end_dt = datetime.combine(cls.date, cls.end_time)
            if not (window_start <= class_end_dt <= window_end):
                continue

            has_attendance = (
                db.query(StudentAttendance).filter(StudentAttendance.class_id == cls.id).first()
            )
            if has_attendance:
                continue

            if admins is None:
                admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
            coach = db.query(User).filter(User.id == cls.coach_id).first()
            coach_name = coach.name if coach else "Unknown coach"
            activity_name = cls.activity.name if cls.activity else "activity"
            for admin in admins:
                notify_and_push(
                    db,
                    admin,
                    f"Attendance not yet submitted 10 min after class end: {coach_name} ({activity_name}) at {cls.end_time}.",
                    "Missed attendance",
                    "MISSED_ATTENDANCE_ADMIN",
                    delay_minutes=10,
                )
            if coach:
                notify_and_push(
                    db,
                    coach,
                    f"Attendance is still pending for your {activity_name} class that ended at {cls.end_time}. Please mark it now.",
                    "Missed attendance",
                    "MISSED_ATTENDANCE_COACH",
                    delay_minutes=10,
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

        missing_ids = coach_ids_today - marked_ids
        if not missing_ids:
            return

        missing_coaches = db.query(User).filter(User.id.in_(missing_ids)).all()
        names = ", ".join(c.name for c in missing_coaches)

        admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
        for admin in admins:
            notify_and_push(
                db,
                admin,
                f"End-of-day report: coaches with no attendance marked today: {names}",
                "End-of-day report",
                "END_OF_DAY_REPORT",
                link="/attendance",
            )
        db.commit()
        logger.info("End-of-day missing report sent for %d coaches", len(missing_coaches))
    finally:
        db.close()


def job_auto_generate_batch_sessions():
    """Runs daily: rolls every active, coach-assigned batch's recurring schedule forward by
    `BATCH_AUTO_GENERATE_DAYS_AHEAD` days, so admins never have to click "Generate Sessions"
    again once a batch's days/months/time are set — it just keeps applying going forward
    until the batch itself is edited or deactivated."""
    db = SessionLocal()
    try:
        today = date.today()
        horizon = today + timedelta(days=BATCH_AUTO_GENERATE_DAYS_AHEAD)
        batches = db.query(Batch).filter(Batch.is_active.is_(True), Batch.coach_id.isnot(None)).all()
        total_created = 0
        for batch in batches:
            total_created += generate_sessions_for_batch(db, batch, today, horizon)
        db.commit()
        logger.info("Auto-generated %d class session(s) across %d batch(es)", total_created, len(batches))
    finally:
        db.close()


def start_scheduler():
    scheduler.add_job(
        job_monthly_fee_reminders, CronTrigger(day=10, hour=9, minute=0), id="monthly_fee_reminders", replace_existing=True
    )
    scheduler.add_job(
        job_mark_overdue_fees, CronTrigger(hour=0, minute=30), id="mark_overdue_fees", replace_existing=True
    )
    scheduler.add_job(
        job_coach_attendance_reminders, IntervalTrigger(minutes=1), id="coach_attendance_reminders", replace_existing=True
    )
    scheduler.add_job(
        job_pre_session_attendance_reminder, IntervalTrigger(minutes=1), id="pre_session_attendance_reminder", replace_existing=True
    )
    scheduler.add_job(
        job_coach_before_class_reminder, IntervalTrigger(minutes=1), id="coach_before_class_reminder", replace_existing=True
    )
    scheduler.add_job(
        job_coach_entry_missing_alert, IntervalTrigger(minutes=1), id="coach_entry_missing_alert", replace_existing=True
    )
    scheduler.add_job(
        job_coach_exit_missing_alert, IntervalTrigger(minutes=1), id="coach_exit_missing_alert", replace_existing=True
    )
    scheduler.add_job(
        job_end_of_day_missing_report, CronTrigger(hour=21, minute=0), id="end_of_day_missing_report", replace_existing=True
    )
    scheduler.add_job(
        job_missed_attendance_admin_alert, IntervalTrigger(minutes=1), id="missed_attendance_admin_alert", replace_existing=True
    )
    scheduler.add_job(
        job_auto_generate_batch_sessions, CronTrigger(hour=0, minute=15), id="auto_generate_batch_sessions", replace_existing=True
    )
    scheduler.start()
    logger.info("Scheduler started with %d jobs", len(scheduler.get_jobs()))


def shutdown_scheduler():
    if scheduler.running:
        scheduler.shutdown(wait=False)
