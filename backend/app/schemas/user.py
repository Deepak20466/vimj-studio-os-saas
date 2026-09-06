from datetime import datetime, date
from typing import Optional

from pydantic import BaseModel, EmailStr, Field

from app.models.user import UserRole


class UserBase(BaseModel):
    email: EmailStr
    name: str
    phone: Optional[str] = None


class UserCreate(UserBase):
    """Used by the /coaches create endpoint, which sets the role from the route itself."""

    password: str = Field(min_length=8)


class StudentCreate(BaseModel):
    """Used by /students create. Admin may create freely; a coach must pass an
    activity_id they're linked to (via CoachActivity), which auto-enrolls the student.

    Students never log in (see CLAUDE.md), so email and password are optional here —
    only name and the two phone numbers are mandatory. If omitted, a non-usable
    placeholder email and a random password are generated so the shared `users` table's
    NOT NULL columns are satisfied without implying the student can ever sign in.
    """

    email: Optional[EmailStr] = None
    name: str
    phone: str
    phone_secondary: str
    password: Optional[str] = Field(default=None, min_length=8)
    activity_id: Optional[int] = None
    additional_details: Optional[str] = None


class UserUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    phone_secondary: Optional[str] = None
    is_active: Optional[bool] = None
    password: Optional[str] = Field(default=None, min_length=8)


class SelfAccountUpdate(BaseModel):
    """Used by the logged-in admin to change their own login email and/or password."""

    email: Optional[EmailStr] = None
    current_password: str
    new_password: Optional[str] = Field(default=None, min_length=8)


class UserOut(UserBase):
    id: int
    role: UserRole
    is_active: bool
    phone_secondary: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class UserDetailsUpdate(BaseModel):
    address: Optional[str] = None
    dob: Optional[date] = None
    profile_photo: Optional[str] = None
    additional_details: Optional[str] = None
