import hashlib
import secrets
import uuid
from datetime import datetime, timedelta

import bcrypt
import jwt

from config import settings
from errors import AppError
from utils import utcnow


def hash_password(password: str) -> str:
    _reject_oversized(password)
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, password_hash: str) -> bool:
    if len(password.encode()) > 72:
        return False
    return bcrypt.checkpw(password.encode(), password_hash.encode())


def _reject_oversized(password: str) -> None:
    if len(password.encode()) > 72:
        raise AppError(
            "PASSWORD_TOO_LONG",
            "كلمة المرور أطول من الحد المسموح.",
            422,
        )


def create_access_token(*, user_id: uuid.UUID, station_id: uuid.UUID, role_code: str) -> tuple[str, int, str]:
    minutes = settings.access_token_minutes
    expires = utcnow() + timedelta(minutes=minutes)
    jti = str(uuid.uuid4())
    payload = {
        "sub": str(user_id),
        "station_id": str(station_id),
        "role": role_code,
        "typ": "access",
        "jti": jti,
        "exp": expires,
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm="HS256")
    return token, minutes * 60, jti


def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError as exc:
        raise AppError(
            "INVALID_TOKEN",
            "انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.",
            401,
        ) from exc
    if payload.get("typ") != "access" or "sub" not in payload:
        raise AppError(
            "INVALID_TOKEN",
            "انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.",
            401,
        )
    return payload


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def refresh_expiry(remember_me: bool) -> datetime:
    days = settings.refresh_token_remember_days if remember_me else settings.refresh_token_days
    return utcnow() + timedelta(days=days)
