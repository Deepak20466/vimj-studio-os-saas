from datetime import datetime, date, time
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel


class ActivityBase(BaseModel):
    name: str
    capacity: int = 0
    location_lat: Optional[Decimal] = None
    location_lng: Optional[Decimal] = None
    monthly_fee: Decimal = Decimal("0")


class ActivityCreate(ActivityBase):
    pass


class ActivityUpdate(BaseModel):
    name: Optional[str] = None
    capacity: Optional[int] = None
    location_lat: Optional[Decimal] = None
    location_lng: Optional[Decimal] = None
    monthly_fee: Optional[Decimal] = None


class ActivityOut(ActivityBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


class ClassCreate(BaseModel):
    activity_id: int
    coach_id: int
    date: date
    start_time: time
    end_time: time


class ClassUpdate(BaseModel):
    coach_id: Optional[int] = None
    date: Optional[date] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None


class ClassOut(BaseModel):
    id: int
    activity_id: int
    coach_id: int
    date: date
    start_time: time
    end_time: time

    class Config:
        from_attributes = True


class EnrollmentCreate(BaseModel):
    student_id: int
    activity_id: int
