import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import Column, Numeric, UniqueConstraint
from sqlmodel import Field, SQLModel

from utils import utcnow


class ShiftDuty(SQLModel, table=True):
    __tablename__ = "shift_duties"
    __table_args__ = (
        UniqueConstraint("session_id", "user_id", name="uq_shift_duties_session_user"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    session_id: uuid.UUID = Field(foreign_key="shift_sessions.id", index=True)
    user_id: uuid.UUID = Field(foreign_key="users.id", index=True)
    attendance_id: uuid.UUID = Field(foreign_key="attendances.id", index=True)
    rostered_user_id: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    status: str = Field(default="open", max_length=32)
    opened_at: datetime = Field(default_factory=utcnow)
    submitted_at: datetime | None = None
    approved_at: datetime | None = None
    approved_by: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    reject_reason: str | None = None
    cash_handed: Decimal | None = Field(default=None, sa_column=Column(Numeric(14, 2)))
    expected_cash: Decimal | None = Field(default=None, sa_column=Column(Numeric(14, 2)))
    variance: Decimal | None = Field(default=None, sa_column=Column(Numeric(14, 2)))
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class ShiftReading(SQLModel, table=True):
    __tablename__ = "shift_readings"
    __table_args__ = (
        UniqueConstraint("duty_id", "nozzle_id", name="uq_shift_readings_duty_nozzle"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    duty_id: uuid.UUID = Field(foreign_key="shift_duties.id", index=True)
    nozzle_id: uuid.UUID = Field(foreign_key="nozzles.id", index=True)
    price_id: uuid.UUID | None = Field(default=None, foreign_key="fuel_prices.id")
    opening_meter: Decimal = Field(sa_column=Column(Numeric(16, 3), nullable=False))
    closing_meter: Decimal | None = Field(default=None, sa_column=Column(Numeric(16, 3)))
    liters: Decimal | None = Field(default=None, sa_column=Column(Numeric(14, 3)))
    unit_price: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    line_amount: Decimal | None = Field(default=None, sa_column=Column(Numeric(14, 2)))
    meter_adjusted: bool = False
    previous_meter: Decimal | None = Field(default=None, sa_column=Column(Numeric(16, 3)))
    meter_reason: str | None = Field(default=None, max_length=300)
    adjusted_by: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    rollover: bool = False
    rollover_at: Decimal | None = Field(default=None, sa_column=Column(Numeric(16, 3)))
    created_at: datetime = Field(default_factory=utcnow)


class NozzleMeterAdjustment(SQLModel, table=True):
    __tablename__ = "nozzle_meter_adjustments"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    nozzle_id: uuid.UUID = Field(foreign_key="nozzles.id", index=True)
    duty_id: uuid.UUID | None = Field(default=None, foreign_key="shift_duties.id", index=True)
    actor_id: uuid.UUID = Field(foreign_key="users.id", index=True)
    previous_meter: Decimal = Field(sa_column=Column(Numeric(16, 3), nullable=False))
    new_meter: Decimal = Field(sa_column=Column(Numeric(16, 3), nullable=False))
    reason: str = Field(max_length=300)
    created_at: datetime = Field(default_factory=utcnow)


class Notification(SQLModel, table=True):
    __tablename__ = "notifications"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    user_id: uuid.UUID | None = Field(default=None, foreign_key="users.id", index=True)
    kind: str = Field(max_length=32)
    title: str = Field(max_length=200)
    body: str
    entity_type: str | None = Field(default=None, max_length=32)
    entity_id: str | None = Field(default=None, max_length=64)
    read_at: datetime | None = None
    created_at: datetime = Field(default_factory=utcnow)
