from datetime import datetime

from pydantic import BaseModel


class StaffPublic(BaseModel):
    id: str
    employee_code: str
    full_name: str
    username: str
    email: str | None
    job_title: str
    role_code: str
    role_name_ar: str
    is_active: bool
    is_maintenance: bool
    photo_url: str | None = None
    last_login_at: datetime | None


class UserCreate(BaseModel):
    full_name: str
    username: str
    email: str | None = None
    job_title: str = ""
    role_code: str
    password: str
    is_maintenance: bool = False


class UserUpdate(BaseModel):
    full_name: str | None = None
    username: str | None = None
    email: str | None = None
    job_title: str | None = None
    role_code: str | None = None
    is_active: bool | None = None
    is_maintenance: bool | None = None
    password: str | None = None


class RolePublic(BaseModel):
    id: str
    code: str
    name_ar: str
    permissions: list[str]
