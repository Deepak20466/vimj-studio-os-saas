from typing import List

from pydantic import BaseModel


class MonthlyPoint(BaseModel):
    label: str
    value: float


class AttendanceGraphResponse(BaseModel):
    user_id: int
    points: List[MonthlyPoint]


class ActivityBreakdown(BaseModel):
    activity_name: str
    total_classes: int
    avg_attendance_pct: float
    revenue: float


class FeeStatusGraphResponse(BaseModel):
    paid: int
    unpaid: int
    overdue: int


class HundredPercentCoach(BaseModel):
    coach_id: int
    coach_name: str
    attendance_pct: float


class MonthlyAnalysis(BaseModel):
    month: int
    year: int
    total_students: int
    total_coaches: int
    total_classes: int
    monthly_revenue: float
    attendance_rate: float
    activity_breakdown: List[ActivityBreakdown]
    prev_month_revenue: float
    prev_month_attendance_rate: float


class StudentReport(BaseModel):
    student_id: int
    name: str
    total_classes: int
    present: int
    absent: int
    leave: int
    attendance_pct: float
    fees_paid: int
    fees_unpaid: int
    outstanding_balance: float


class CoachReport(BaseModel):
    coach_id: int
    name: str
    total_classes: int
    days_present: int
    days_absent: int
    leaves_taken: int
    student_attendance_pct: float
