import uuid
from datetime import date, datetime, time
from decimal import Decimal

from sqlalchemy import Column, Numeric, UniqueConstraint
from sqlmodel import Field, SQLModel

from utils import utcnow


class Station(SQLModel, table=True):
    __tablename__ = "stations"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    code: str = Field(index=True, unique=True, max_length=32)
    name: str = Field(max_length=200)
    license_number: str = Field(max_length=64)
    license_expires_on: date
    latitude: float | None = None
    longitude: float | None = None
    timezone: str = Field(default="Africa/Tripoli", max_length=64)
    logo_url: str | None = Field(default=None, max_length=300)
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class FuelProduct(SQLModel, table=True):
    __tablename__ = "fuel_products"
    __table_args__ = (UniqueConstraint("station_id", "code", name="uq_fuel_products_station_code"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    code: str = Field(max_length=32)
    name_ar: str = Field(max_length=120)
    is_active: bool = True
    sort_order: int = 0
    created_at: datetime = Field(default_factory=utcnow)


class FuelPrice(SQLModel, table=True):
    __tablename__ = "fuel_prices"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    product_id: uuid.UUID = Field(foreign_key="fuel_products.id", index=True)
    price_per_liter: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    effective_from: datetime = Field(default_factory=utcnow)
    created_by: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    created_at: datetime = Field(default_factory=utcnow)


class ShiftTemplate(SQLModel, table=True):
    __tablename__ = "shift_templates"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    name_ar: str = Field(max_length=120)
    starts_at: time
    ends_at: time
    grace_minutes: int = 10
    is_active: bool = True
    sort_order: int = 0
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)
