import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Column, Numeric, UniqueConstraint
from sqlmodel import Field, SQLModel

from utils import utcnow


class Supplier(SQLModel, table=True):
    __tablename__ = "suppliers"
    __table_args__ = (UniqueConstraint("station_id", "name", name="uq_suppliers_station_name"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    name: str = Field(max_length=200)
    headquarters: str = Field(default="", max_length=200)
    contact_name: str = Field(default="", max_length=200)
    phone: str = Field(default="", max_length=40)
    max_daily_liters: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    is_active: bool = True
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class SupplyOrder(SQLModel, table=True):
    __tablename__ = "supply_orders"
    __table_args__ = (UniqueConstraint("station_id", "code", name="uq_supply_orders_station_code"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    supplier_id: uuid.UUID = Field(foreign_key="suppliers.id", index=True)
    tank_id: uuid.UUID = Field(foreign_key="tanks.id", index=True)
    product_id: uuid.UUID = Field(foreign_key="fuel_products.id", index=True)
    code: str = Field(max_length=32)
    ordered_liters: Decimal = Field(sa_column=Column(Numeric(14, 3), nullable=False))
    received_liters: Decimal | None = Field(default=None, sa_column=Column(Numeric(14, 3)))
    status: str = Field(default="pending", max_length=32)
    expected_on: date
    notes: str | None = None
    received_at: datetime | None = None
    received_by: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    cancelled_at: datetime | None = None
    created_by: uuid.UUID | None = Field(default=None, foreign_key="users.id")
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)
