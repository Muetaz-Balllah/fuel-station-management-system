import uuid
from datetime import date, datetime

from sqlalchemy import UniqueConstraint
from sqlmodel import Field, SQLModel

from utils import utcnow


class ShiftSession(SQLModel, table=True):
    __tablename__ = "shift_sessions"
    __table_args__ = (
        UniqueConstraint(
            "station_id",
            "template_id",
            "business_date",
            name="uq_shift_sessions_station_template_date",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    template_id: uuid.UUID = Field(foreign_key="shift_templates.id", index=True)
    supervisor_id: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    code: str = Field(max_length=32)
    business_date: date = Field(index=True)
    status: str = Field(default="open", max_length=32)
    starts_at: datetime
    ends_at: datetime
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class Attendance(SQLModel, table=True):
    __tablename__ = "attendances"
    __table_args__ = (
        UniqueConstraint("session_id", "user_id", name="uq_attendances_session_user"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    session_id: uuid.UUID = Field(foreign_key="shift_sessions.id", index=True)
    user_id: uuid.UUID = Field(foreign_key="users.id", index=True)
    recorded_by: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    status: str = Field(default="assigned", max_length=32)
    note: str | None = None
    check_in_at: datetime | None = None
    check_out_at: datetime | None = None
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class ShiftAssignment(SQLModel, table=True):
    __tablename__ = "shift_assignments"
    __table_args__ = (
        UniqueConstraint("attendance_id", "nozzle_id", name="uq_shift_assignments_attendance_nozzle"),
        UniqueConstraint("session_id", "nozzle_id", name="uq_shift_assignments_session_nozzle"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    session_id: uuid.UUID = Field(foreign_key="shift_sessions.id", index=True)
    attendance_id: uuid.UUID = Field(foreign_key="attendances.id", index=True)
    nozzle_id: uuid.UUID = Field(foreign_key="nozzles.id", index=True)
    created_at: datetime = Field(default_factory=utcnow)
