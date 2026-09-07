from sqlalchemy import Column, Integer, String, DateTime, Numeric
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class Activity(Base):
    __tablename__ = "activities"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    capacity = Column(Integer, nullable=False, default=0)
    location_lat = Column(Numeric(9, 6), nullable=True)
    location_lng = Column(Numeric(9, 6), nullable=True)
    monthly_fee = Column(Numeric(10, 2), nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    classes = relationship("ClassSession", back_populates="activity", passive_deletes=True)
