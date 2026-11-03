import uuid

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel import Session, select

from core.cache import session_cache
from core.security import decode_access_token
from db import get_session
from errors import AppError
from users.models import Permission, RolePermission, User

bearer = HTTPBearer(auto_error=False)


def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    session: Session = Depends(get_session),
) -> User:
    if credentials is None or not credentials.credentials:
        raise AppError("NOT_AUTHENTICATED", "يلزم تسجيل الدخول للمتابعة.", 401)
    payload = decode_access_token(credentials.credentials)
    try:
        user_id = uuid.UUID(payload["sub"])
    except ValueError as exc:
        raise AppError(
            "INVALID_TOKEN",
            "انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.",
            401,
        ) from exc
    jti = payload.get("jti")
    cached = session_cache.get(jti) if isinstance(jti, str) and jti else None
    if cached is None or cached.get("user_id") != str(user_id):
        raise AppError(
            "SESSION_REVOKED",
            "انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.",
            401,
        )
    user = session.get(User, user_id)
    if user is None or not user.is_active:
        session_cache.revoke(jti)
        raise AppError(
            "ACCOUNT_INACTIVE",
            "هذا الحساب غير نشط. راجع مدير المحطة.",
            401,
        )
    request.state.permissions = tuple(cached.get("permissions") or [])
    request.state.role_code = str(cached.get("role_code") or "")
    return user


def permission_codes(session: Session, role_id: uuid.UUID) -> list[str]:
    rows = session.exec(
        select(Permission.code)
        .join(RolePermission, RolePermission.permission_id == Permission.id)
        .where(RolePermission.role_id == role_id)
    ).all()
    return sorted(rows)


def require_permission(code: str):
    def checker(request: Request, user: User = Depends(get_current_user)) -> User:
        if code not in getattr(request.state, "permissions", ()):
            raise AppError(
                "FORBIDDEN",
                "ليست لديك صلاحية لتنفيذ هذا الإجراء.",
                403,
            )
        return user

    return checker


def require_any_permission(*codes: str):
    def checker(request: Request, user: User = Depends(get_current_user)) -> User:
        granted = getattr(request.state, "permissions", ())
        if not any(code in granted for code in codes):
            raise AppError(
                "FORBIDDEN",
                "ليست لديك صلاحية لتنفيذ هذا الإجراء.",
                403,
            )
        return user

    return checker


def require_role(code: str):
    def checker(request: Request, user: User = Depends(get_current_user)) -> User:
        if getattr(request.state, "role_code", "") != code:
            raise AppError(
                "FORBIDDEN",
                "ليست لديك صلاحية لتنفيذ هذا الإجراء.",
                403,
            )
        return user

    return checker
