from datetime import datetime, date, time
from typing import List, Optional

from pydantic import BaseModel, field_validator

from app.models.batch import SessionPeriod

VALID_DAYS = {"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"}
ALL_MONTHS = list(range(1, 13))


def _validate_days(value: List[str]) -> List[str]:
    days = [d.upper() for d in value]
    invalid = set(days) - VALID_DAYS
    if invalid:
        raise ValueError(f"Invalid day(s): {', '.join(sorted(invalid))}")
    return days


def _validate_months(value: List[int]) -> List[int]:
    invalid = [m for m in value if m < 1 or m > 12]
    if invalid:
        raise ValueError(f"Invalid month(s): {', '.join(str(m) for m in invalid)}")
    if not value:
        raise ValueError("Select at least one month")
    return sorted(set(value))


class BatchBase(BaseModel):
    activity_id: int
    coach_id: Optional[int] = None
    location: str
    session_period: SessionPeriod
    start_time: time
    end_time: time
    days_of_week: List[str]
    active_months: List[int] = ALL_MONTHS
    is_active: bool = True

    @field_validator("days_of_week")
    @classmethod
    def _check_days(cls, value: List[str]) -> List[str]:
        return _validate_days(value)

    @field_validator("active_months")
    @classmethod
    def _check_months(cls, value: List[int]) -> List[int]:
        return _validate_months(value)


class BatchCreate(BatchBase):
    pass


class BatchUpdate(BaseModel):
    coach_id: Optional[int] = None
    location: Optional[str] = None
    session_period: Optional[SessionPeriod] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    days_of_week: Optional[List[str]] = None
    active_months: Optional[List[int]] = None
    is_active: Optional[bool] = None

    @field_validator("days_of_week")
    @classmethod
    def _check_days(cls, value):
        if value is None:
            return value
        return _validate_days(value)

    @field_validator("active_months")
    @classmethod
    def _check_months(cls, value):
        if value is None:
            return value
        return _validate_months(value)


class BatchOut(BaseModel):
    id: int
    activity_id: int
    coach_id: Optional[int]
    location: str
    session_period: SessionPeriod
    start_time: time
    end_time: time
    days_of_week: List[str]
    active_months: List[int]
    is_active: bool
    created_at: datetime

    @field_validator("days_of_week", mode="before")
    @classmethod
    def _split_days(cls, value):
        if isinstance(value, str):
            return [d for d in value.split(",") if d]
        return value

    @field_validator("active_months", mode="before")
    @classmethod
    def _split_months(cls, value):
        if isinstance(value, str):
            return [int(m) for m in value.split(",") if m]
        return value

    class Config:
        from_attributes = True


class GenerateSessionsRequest(BaseModel):
    start_date: date
    end_date: date
