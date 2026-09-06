from datetime import datetime, date
from typing import List, Optional

from pydantic import BaseModel

from app.models.compliance import LateStatus


class ClassNotConductedRequest(BaseModel):
    class_id: int
    reason: str


class ClassSkipReasonOut(BaseModel):
    id: int
    class_id: int
    coach_id: int
    reason: str
    created_at: datetime

    class Config:
        from_attributes = True


class LateReasonRequest(BaseModel):
    class_id: int
    reason: str


class LateDecisionRequest(BaseModel):
    decision_note: Optional[str] = None


class AttendanceSubmissionOut(BaseModel):
    id: int
    class_id: int
    coach_id: int
    submitted_at: Optional[datetime]
    is_late: bool
    late_reason: Optional[str]
    late_status: LateStatus
    created_at: datetime

    class Config:
        from_attributes = True


class AttendanceSubmissionAdminOut(AttendanceSubmissionOut):
    coach_name: str
    activity_name: str
    class_date: date


class ClassPhotoUploadRequest(BaseModel):
    class_id: int
    photo_base64: str


class ClassPhotoOut(BaseModel):
    id: int
    class_id: int
    coach_id: int
    created_at: datetime

    class Config:
        from_attributes = True


class ComplianceRow(BaseModel):
    """One scheduled class and where it stands in the attendance-compliance lifecycle."""

    class_id: int
    activity_name: str
    coach_id: int
    coach_name: str
    class_date: date
    end_time: str
    state: str  # SUBMITTED | PENDING | DELAYED | NOT_CONDUCTED | LATE_APPROVED | LATE_REJECTED
    skip_reason: Optional[str] = None
    late_reason: Optional[str] = None


class ComplianceSummary(BaseModel):
    submitted: int
    pending: int
    delayed: int
    not_conducted: int
    late_approved: int
    late_rejected: int
    rows: List[ComplianceRow]
