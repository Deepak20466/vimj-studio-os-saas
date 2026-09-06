from sqlalchemy.orm import Session

from app.models.coach_activity import CoachActivity
from app.models.enrollment import StudentEnrollment


def coach_may_bill_student(db: Session, coach_id: int, student_id: int) -> bool:
    """A coach may bill (fee receipt / fee reminder) a student enrolled in one of the coach's assigned activities."""
    student_activity_ids = {
        row[0]
        for row in db.query(StudentEnrollment.activity_id).filter(StudentEnrollment.student_id == student_id).all()
    }
    if not student_activity_ids:
        return False
    coach_activity_ids = {
        row[0] for row in db.query(CoachActivity.activity_id).filter(CoachActivity.coach_id == coach_id).all()
    }
    return bool(student_activity_ids & coach_activity_ids)
