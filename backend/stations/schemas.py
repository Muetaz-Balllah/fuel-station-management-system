from datetime import date

from pydantic import BaseModel


class StationPublic(BaseModel):
    id: str
    code: str
    name: str
    license_number: str
    license_expires_on: date
    latitude: float | None
    longitude: float | None
    timezone: str
    logo_url: str | None = None


class StationUpdate(BaseModel):
    name: str | None = None
    license_number: str | None = None
    license_expires_on: date | None = None
    latitude: float | None = None
    longitude: float | None = None
