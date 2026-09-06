from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func

from app.database import Base


class AcademySettings(Base):
    """Singleton row (id=1) holding academy "About" details shown in the admin dashboard."""

    __tablename__ = "academy_settings"

    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False, default="VIMJ Studio")
    address = Column(Text, nullable=True)
    phone = Column(String(32), nullable=True)
    email = Column(String(255), nullable=True)
    description = Column(Text, nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
