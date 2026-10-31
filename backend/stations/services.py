from pathlib import Path

from fastapi import UploadFile
from sqlmodel import Session

from errors import AppError
from stations.models import Station
from stations.schemas import StationPublic, StationUpdate
from users.audit import write_audit
from users.models import User
from utils import utcnow

_MAX_LOGO_BYTES = 2 * 1024 * 1024
_LOGO_TYPES = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/webp": ".webp",
}


def to_public(station: Station) -> StationPublic:
    return StationPublic(
        id=str(station.id),
        code=station.code,
        name=station.name,
        license_number=station.license_number,
        license_expires_on=station.license_expires_on,
        latitude=station.latitude,
        longitude=station.longitude,
        timezone=station.timezone,
        logo_url=station.logo_url,
    )


def get_for_user(session: Session, user: User) -> Station:
    station = session.get(Station, user.station_id)
    if station is None:
        raise AppError("STATION_NOT_FOUND", "تعذر العثور على بيانات المحطة.", 404)
    return station


def update_station(session: Session, user: User, payload: StationUpdate) -> Station:
    station = get_for_user(session, user)
    data = payload.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        name = data["name"].strip()
        if not name:
            raise AppError("VALIDATION_ERROR", "اسم المحطة مطلوب.", 422)
        station.name = name
    if "license_number" in data and data["license_number"] is not None:
        license_number = data["license_number"].strip()
        if not license_number:
            raise AppError("VALIDATION_ERROR", "رقم الترخيص مطلوب.", 422)
        station.license_number = license_number
    if "license_expires_on" in data:
        station.license_expires_on = data["license_expires_on"]
    if "latitude" in data:
        station.latitude = data["latitude"]
    if "longitude" in data:
        station.longitude = data["longitude"]
    station.updated_at = utcnow()
    session.add(station)
    write_audit(
        session,
        actor_id=user.id,
        action="station_updated",
        entity="station",
        entity_id=str(station.id),
        detail=None,
    )
    session.commit()
    session.refresh(station)
    return station


def save_logo(session: Session, user: User, upload: UploadFile) -> Station:
    ext = _logo_extension(upload)
    data = upload.file.read(_MAX_LOGO_BYTES + 1)
    if not data:
        raise AppError("VALIDATION_ERROR", "ملف الشعار فارغ.", 422)
    if len(data) > _MAX_LOGO_BYTES:
        raise AppError("VALIDATION_ERROR", "حجم الشعار يجب ألا يتجاوز 2 ميغابايت.", 422)
    station = get_for_user(session, user)
    folder = Path("uploads")
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob(f"{station.id}.*"):
        old.unlink(missing_ok=True)
    filename = f"{station.id}{ext}"
    (folder / filename).write_bytes(data)
    station.logo_url = f"/uploads/{filename}"
    station.updated_at = utcnow()
    session.add(station)
    write_audit(
        session,
        actor_id=user.id,
        action="station_logo_updated",
        entity="station",
        entity_id=str(station.id),
        detail={"logo_url": station.logo_url},
    )
    session.commit()
    session.refresh(station)
    return station


def _logo_extension(upload: UploadFile) -> str:
    content_type = (upload.content_type or "").split(";")[0].strip().lower()
    ext = _LOGO_TYPES.get(content_type)
    if ext is not None:
        return ext
    name = (upload.filename or "").lower()
    if name.endswith(".png"):
        return ".png"
    if name.endswith(".jpg") or name.endswith(".jpeg"):
        return ".jpg"
    if name.endswith(".webp"):
        return ".webp"
    raise AppError("VALIDATION_ERROR", "صيغة الشعار يجب أن تكون PNG أو JPG أو WEBP.", 422)
