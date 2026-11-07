import uuid
from datetime import datetime

from sqlalchemy import UniqueConstraint
from sqlmodel import Field, SQLModel

from utils import utcnow


class User(SQLModel, table=True):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("station_id", "username", name="uq_users_station_username"),
        UniqueConstraint(
            "station_id", "employee_code", name="uq_users_station_employee_code"
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    station_id: uuid.UUID = Field(foreign_key="stations.id", index=True)
    role: str = Field(index=True, max_length=32)
    employee_code: str = Field(max_length=32)
    full_name: str = Field(max_length=200)
    username: str = Field(index=True, max_length=64)
    email: str | None = Field(default=None, max_length=200)
    password_hash: str = Field(max_length=255)
    job_title: str = Field(default="", max_length=120)
    photo_url: str | None = Field(default=None, max_length=300)
    is_active: bool = True
    is_maintenance: bool = False
    failed_login_count: int = 0
    locked_until: datetime | None = None
    last_login_at: datetime | None = None
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class RefreshToken(SQLModel, table=True):
    __tablename__ = "refresh_tokens"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(foreign_key="users.id", index=True)
    token_hash: str = Field(unique=True, index=True, max_length=64)
    access_jti: str | None = Field(default=None, max_length=64)
    expires_at: datetime
    revoked_at: datetime | None = None
    created_at: datetime = Field(default_factory=utcnow)


class AuditLog(SQLModel, table=True):
    __tablename__ = "audit_log"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    actor_id: uuid.UUID | None = Field(default=None, index=True)
    action: str = Field(max_length=64)
    entity: str = Field(max_length=64)
    entity_id: str | None = Field(default=None, max_length=64)
    detail: str | None = None
    created_at: datetime = Field(default_factory=utcnow)
