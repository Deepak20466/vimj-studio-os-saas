from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class ChatMessageCreate(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    coach_id: Optional[int] = None  # required when the sender is an admin; ignored for a coach (always their own thread)


class ChatMessageOut(BaseModel):
    id: int
    coach_id: int
    sender_id: int
    sender_role: str
    sender_name: str
    message: str
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class ChatThreadOut(BaseModel):
    coach_id: int
    coach_name: str
    last_message: Optional[str]
    last_message_at: Optional[datetime]
    unread_count: int


class ChatUnreadCountOut(BaseModel):
    unread_count: int
