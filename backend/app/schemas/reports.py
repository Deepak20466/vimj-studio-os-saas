from typing import List, Optional

from pydantic import BaseModel


class MonthlyPoint(BaseModel):
    label: str
    value: float


class AttendanceGraphResponse(BaseModel):
    user_id: int
    points: List[MonthlyPoint]


class ActivityBreakdown(BaseModel):
    activity_id: int
    activity_name: str
    student_count: int
    total_classes: int
    total_attendance_marks: int
    total_present: int
    total_absent: int
    avg_attendance_pct: float
    revenue: float
    revenue_collected: float


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


class ActivityCoachBreakdown(BaseModel):
    coach_id: int
    coach_name: str
    total_classes: int
    avg_attendance_pct: float


class BatchStudentSummary(BaseModel):
    id: int
    name: str
    phone: Optional[str]
    fee_status: str


class BatchBreakdown(BaseModel):
    group_key: str
    batch_id: Optional[int]
    location: str
    start_time: str
    end_time: str
    days_of_week: List[str]
    coach_id: Optional[int]
    coach_name: str
    student_count: int
    total_classes: int
    present_count: int
    absent_count: int
    attendance_pct: float
    fee_paid_count: int
    fee_unpaid_count: int
    fee_revenue: float
    students: List[BatchStudentSummary]


class SessionPeriodBreakdown(BaseModel):
    session_period: str
    total_students: int
    total_coaches: int
    total_present: int
    total_absent: int
    attendance_pct: float
    fee_paid_count: int
    fee_unpaid_count: int
    fee_revenue: float
    batches: List[BatchBreakdown]


class ActivityDetailReport(BaseModel):
    activity_id: int
    activity_name: str
    student_count: int
    total_classes: int
    total_present: int
    total_absent: int
    attendance_pct: float
    revenue_collected: float
    fee_paid_count: int
    fee_unpaid_count: int
    attendance_graph: List[MonthlyPoint]
    coach_breakdown: List[ActivityCoachBreakdown]
    session_breakdown: List[SessionPeriodBreakdown] = []
