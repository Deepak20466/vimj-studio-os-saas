from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class ChatMessage(Base):
    """A message in the admin<->coach chat thread.

    Threads are keyed by coach_id: every message between "the admin team" and a given
    coach lives in that coach's single thread, so any admin can see and reply to it
    (matching the ADMIN role's full-visibility permissions), while a coach only ever
    sees their own thread (data isolation, enforced in the router).
    """

    __tablename__ = "chat_messages"

    id = Column(Integer, primary_key=True, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    sender_role = Column(String(20), nullable=False)
    message = Column(Text, nullable=False)
    is_read = Column(Boolean, default=False, nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    coach = relationship("User", foreign_keys=[coach_id])
    sender = relationship("User", foreign_keys=[sender_id])
