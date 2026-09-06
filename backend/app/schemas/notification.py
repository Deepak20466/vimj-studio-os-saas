from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class NotificationOut(BaseModel):
    id: int
    type: str
    title: str
    message: str
    link: Optional[str]
    delay_minutes: Optional[int]
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class NotificationListResponse(BaseModel):
    items: List[NotificationOut]
    unread_count: int
