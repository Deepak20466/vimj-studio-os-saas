from datetime import date, datetime, time
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel

from app.models.attendance import AttendanceStatus, CoachAttendanceStatus, AttendanceApprovalStatus


class MarkStudentAttendanceRequest(BaseModel):
    student_id: int
    class_id: int
    status: AttendanceStatus
    location_lat: Decimal
    location_lng: Decimal
    selfie_base64: Optional[str] = None


class ManualAttendanceRequest(BaseModel):
    student_id: int
    class_id: int
    status: AttendanceStatus


class StudentAttendanceOut(BaseModel):
    id: int
    student_id: int
    class_id: int
    status: AttendanceStatus
    coach_id: Optional[int]
    timestamp: datetime
    location_lat: Optional[Decimal]
    location_lng: Optional[Decimal]
    has_selfie: bool = False
    approval_status: AttendanceApprovalStatus

    class Config:
        from_attributes = True


class StudentAttendanceUpdate(BaseModel):
    status: AttendanceStatus


class AttendanceReviewRequest(BaseModel):
    note: Optional[str] = None


class StudentAttendanceAdminOut(BaseModel):
    id: int
    student_id: int
    student_name: str
    class_id: int
    activity_id: int
    activity_name: str
    coach_id: Optional[int]
    coach_name: Optional[str]
    status: AttendanceStatus
    class_date: date
    timestamp: datetime
    marked_manually: bool
    has_selfie: bool = False
    approval_status: AttendanceApprovalStatus


class CoachEntryExitRequest(BaseModel):
    location_lat: Decimal
    location_lng: Decimal
    activity_id: Optional[int] = None


class CoachAttendanceOut(BaseModel):
    id: int
    coach_id: int
    date: datetime
    entry_time: Optional[datetime]
    exit_time: Optional[datetime]
    status: CoachAttendanceStatus

    class Config:
        from_attributes = True


class CoachAttendanceAdminOut(BaseModel):
    id: int
    coach_id: int
    coach_name: str
    date: date
    entry_time: Optional[datetime]
    exit_time: Optional[datetime]
    status: CoachAttendanceStatus


class CoachAttendanceManualCreate(BaseModel):
    coach_id: int
    date: date
    entry_time: Optional[time] = None
    exit_time: Optional[time] = None
    status: CoachAttendanceStatus = CoachAttendanceStatus.PRESENT


class CoachAttendanceManualUpdate(BaseModel):
    entry_time: Optional[time] = None
    exit_time: Optional[time] = None
    status: Optional[CoachAttendanceStatus] = None


class MissingCoachOut(BaseModel):
    coach_id: int
    coach_name: str
    class_id: int
    activity_name: str
    date: str
    end_time: str
