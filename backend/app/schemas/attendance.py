from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel

from app.models.attendance import AttendanceStatus, CoachAttendanceStatus


class MarkStudentAttendanceRequest(BaseModel):
    student_id: int
    class_id: int
    status: AttendanceStatus
    location_lat: Decimal
    location_lng: Decimal
    selfie_base64: Optional[str] = None
    late_reason: Optional[str] = None


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
    selfie_photo: Optional[str]

    class Config:
        from_attributes = True


class StudentAttendanceUpdate(BaseModel):
    status: AttendanceStatus


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


class MissingCoachOut(BaseModel):
    coach_id: int
    coach_name: str
    class_id: int
    activity_name: str
    date: str
    end_time: str
