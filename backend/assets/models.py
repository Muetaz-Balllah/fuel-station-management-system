import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import Column, Numeric, UniqueConstraint
from sqlmodel import Field, SQLModel

from utils import utcnow


class Tank(SQLModel, table=True):
    __tablename__ = "tanks"
    __table_args__ = (UniqueConstraint("station_id", "code", name="uq_tanks_station_code"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    product_id: uuid.UUID = Field(foreign_key="fuel_products.id", index=True)
    code: str = Field(max_length=32)
    name: str = Field(max_length=200)
    capacity_liters: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    current_liters: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    critical_percent: int = 15
    warning_percent: int = 40
    is_active: bool = True
    is_demo: bool = False
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class Pump(SQLModel, table=True):
    __tablename__ = "pumps"
    __table_args__ = (UniqueConstraint("station_id", "code", name="uq_pumps_station_code"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    tank_id: uuid.UUID = Field(foreign_key="tanks.id", unique=True, index=True)
    code: str = Field(max_length=32)
    name: str = Field(max_length=200)
    status: str = Field(default="active", max_length=32)
    is_demo: bool = False
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class Nozzle(SQLModel, table=True):
    __tablename__ = "nozzles"
    __table_args__ = (UniqueConstraint("pump_id", "code", name="uq_nozzles_pump_code"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    pump_id: uuid.UUID = Field(foreign_key="pumps.id", index=True)
    code: str = Field(max_length=32)
    label: str = Field(max_length=80)
    status: str = Field(default="ready", max_length=32)
    current_meter: Decimal = Field(sa_column=Column(Numeric(16, 3), nullable=False))
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class InventoryMovement(SQLModel, table=True):
    __tablename__ = "inventory_movements"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    tank_id: uuid.UUID = Field(foreign_key="tanks.id", index=True)
    nozzle_id: uuid.UUID | None = Field(default=None, foreign_key="nozzles.id")
    movement_type: str = Field(max_length=32)
    liters_delta: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    balance_after: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    source_type: str | None = Field(default=None, max_length=32)
    source_id: str | None = Field(default=None, max_length=64)
    note: str | None = None
    created_by: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    created_at: datetime = Field(default_factory=utcnow)
