from typing import List

from pydantic import BaseModel


class DashboardSummary(BaseModel):
    total_students: int
    total_coaches: int
    total_activities: int
    total_classes_this_month: int
    monthly_revenue: float
    unpaid_fees_count: int


class FeeStatusGraphResponse(BaseModel):
    paid: int
    unpaid: int
    overdue: int


class ActivityAttendancePoint(BaseModel):
    activity_id: int
    activity_name: str
    student_count: int
    avg_attendance_pct: float


class ActivityAttendanceResponse(BaseModel):
    points: List[ActivityAttendancePoint]
