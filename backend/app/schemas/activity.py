# `date` is imported under an alias because several models below have a field
# literally named `date` with a default value (`date: Optional[date] = None`).
# Pydantic v2 resolves annotations via typing.get_type_hints() using the class's
# own namespace as part of the lookup, so once a class attribute named `date`
# exists, it shadows the `datetime.date` type for that same class's annotations
# and every such field silently resolves to `NoneType` instead of `date` (any
# non-None value then fails validation with "Input should be None"). Fields
# without a default (e.g. ClassCreate.date below) aren't affected since pydantic
# doesn't set a class attribute for those — only ClassUpdate.date hit this.
from datetime import datetime, time
from datetime import date as _Date
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
    date: _Date
    start_time: time
    end_time: time


class ClassUpdate(BaseModel):
    coach_id: Optional[int] = None
    date: Optional[_Date] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None


class ClassOut(BaseModel):
    id: int
    activity_id: int
    coach_id: int
    date: _Date
    start_time: time
    end_time: time
    has_group_photo: bool = False
    group_photo_uploaded_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class EnrollmentCreate(BaseModel):
    student_id: int
    activity_id: int


class GroupPhotoUpload(BaseModel):
    photo_base64: str
