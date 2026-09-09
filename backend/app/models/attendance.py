import enum

from sqlalchemy import Column, Integer, ForeignKey, DateTime, Enum, Numeric, LargeBinary, Date, Time
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class AttendanceStatus(str, enum.Enum):
    PRESENT = "PRESENT"
    ABSENT = "ABSENT"
    LEAVE = "LEAVE"


class CoachAttendanceStatus(str, enum.Enum):
    PRESENT = "PRESENT"
    ABSENT = "ABSENT"
    LEAVE = "LEAVE"
    INCOMPLETE = "INCOMPLETE"  # entered but never exited / never marked


class StudentAttendance(Base):
    __tablename__ = "student_attendance"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    class_id = Column(Integer, ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(Enum(AttendanceStatus), nullable=False)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    location_lat = Column(Numeric(9, 6), nullable=True)
    location_lng = Column(Numeric(9, 6), nullable=True)
    selfie_photo = Column(LargeBinary, nullable=True)
    marked_manually = Column(Numeric, default=0)  # 0/1 flag: admin manual entry vs coach geofenced entry
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    student = relationship("User", foreign_keys=[student_id])
    coach = relationship("User", foreign_keys=[coach_id])
    class_session = relationship("ClassSession", back_populates="student_attendance")

    @property
    def has_selfie(self) -> bool:
        return self.selfie_photo is not None


class CoachAttendance(Base):
    __tablename__ = "coach_attendance"

    id = Column(Integer, primary_key=True, index=True)
    coach_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    date = Column(Date, nullable=False, index=True)
    entry_time = Column(DateTime(timezone=True), nullable=True)
    exit_time = Column(DateTime(timezone=True), nullable=True)
    entry_lat = Column(Numeric(9, 6), nullable=True)
    entry_lng = Column(Numeric(9, 6), nullable=True)
    exit_lat = Column(Numeric(9, 6), nullable=True)
    exit_lng = Column(Numeric(9, 6), nullable=True)
    activity_id = Column(Integer, ForeignKey("activities.id", ondelete="SET NULL"), nullable=True)
    status = Column(Enum(CoachAttendanceStatus), nullable=False, default=CoachAttendanceStatus.INCOMPLETE)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    coach = relationship("User", foreign_keys=[coach_id])
    activity = relationship("Activity")
