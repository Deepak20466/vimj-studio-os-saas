from datetime import datetime, date
from typing import Optional

from pydantic import BaseModel, EmailStr, Field

from app.models.user import UserRole


class UserBase(BaseModel):
    email: EmailStr
    name: str
    phone: Optional[str] = None


class UserCreate(UserBase):
    """Used by /students and /coaches create endpoints, which set the role from the route itself."""

    password: str = Field(min_length=8)


class UserUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    is_active: Optional[bool] = None
    password: Optional[str] = Field(default=None, min_length=8)


class UserOut(UserBase):
    id: int
    role: UserRole
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class UserDetailsUpdate(BaseModel):
    address: Optional[str] = None
    dob: Optional[date] = None
    profile_photo: Optional[str] = None
