from datetime import timedelta

from sqlmodel import Session, select

from auth.schemas import TokenResponse, UserPublic
from core.cache import session_cache
from core.deps import permission_codes
from core.security import (
    create_access_token,
    hash_password,
    hash_refresh_token,
    new_refresh_token,
    refresh_expiry,
    verify_password,
)
from errors import AppError
from stations.models import Station
from users.audit import write_audit
from users.models import RefreshToken, Role, User
from utils import as_utc, utcnow

_INVALID = "اسم المستخدم أو كلمة المرور غير صحيحة"


def to_public(session: Session, user: User) -> UserPublic:
    station = session.get(Station, user.station_id)
    role = session.get(Role, user.role_id)
    if station is None or role is None:
        raise AppError("ACCOUNT_INVALID", "تعذر تحميل بيانات الحساب.", 500)
    return UserPublic(
        id=str(user.id),
        station_id=str(user.station_id),
        station_name=station.name,
        station_code=station.code,
        employee_code=user.employee_code,
        full_name=user.full_name,
        username=user.username,
        email=user.email,
        job_title=user.job_title,
        role_code=role.code,
        role_name_ar=role.name_ar,
        permissions=permission_codes(session, user.role_id),
        is_maintenance=user.is_maintenance,
        is_active=user.is_active,
        last_login_at=user.last_login_at,
    )


def _issue(session: Session, user: User, remember_me: bool) -> TokenResponse:
    role = session.get(Role, user.role_id)
    if role is None:
        raise AppError("ACCOUNT_INVALID", "تعذر تحميل بيانات الحساب.", 500)
    access, expires_in, jti = create_access_token(
        user_id=user.id,
        station_id=user.station_id,
        role_code=role.code,
    )
    session_cache.store(
        jti=jti,
        user_id=str(user.id),
        role_code=role.code,
        permissions=permission_codes(session, user.role_id),
        ttl_seconds=expires_in,
    )
    raw_refresh = new_refresh_token()
    session.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hash_refresh_token(raw_refresh),
            access_jti=jti,
            expires_at=refresh_expiry(remember_me),
        )
    )
    return TokenResponse(
        access_token=access,
        refresh_token=raw_refresh,
        access_expires_in=expires_in,
        user=to_public(session, user),
    )


def login(session: Session, username: str, password: str, remember_me: bool) -> TokenResponse:
    username = username.strip()
    user = session.exec(select(User).where(User.username == username)).first()
    if user is None:
        write_audit(
            session,
            actor_id=None,
            action="login_failure",
            entity="user",
            entity_id=None,
            detail={"username": username},
        )
        session.commit()
        raise AppError("INVALID_CREDENTIALS", _INVALID, 401)

    if not user.is_active:
        raise AppError(
            "ACCOUNT_INACTIVE",
            "هذا الحساب غير نشط. راجع مدير المحطة.",
            403,
        )

    locked = as_utc(user.locked_until)
    if locked is not None and locked > utcnow():
        raise AppError(
            "ACCOUNT_LOCKED",
            "تم قفل الحساب مؤقتاً لكثرة المحاولات غير الصحيحة. حاول بعد قليل أو اطلب من المدير إعادة التعيين.",
            423,
        )

    if not verify_password(password, user.password_hash):
        from config import settings

        user.failed_login_count += 1
        locked_now = False
        if user.failed_login_count >= settings.lockout_attempts:
            user.locked_until = utcnow() + timedelta(minutes=settings.lockout_minutes)
            user.failed_login_count = 0
            locked_now = True
        user.updated_at = utcnow()
        session.add(user)
        write_audit(
            session,
            actor_id=user.id,
            action="login_locked" if locked_now else "login_failure",
            entity="user",
            entity_id=str(user.id),
            detail=None,
        )
        session.commit()
        raise AppError("INVALID_CREDENTIALS", _INVALID, 401)

    user.failed_login_count = 0
    user.locked_until = None
    user.last_login_at = utcnow()
    user.updated_at = utcnow()
    session.add(user)
    tokens = _issue(session, user, remember_me)
    write_audit(
        session,
        actor_id=user.id,
        action="login_success",
        entity="user",
        entity_id=str(user.id),
        detail={"remember_me": remember_me},
    )
    session.commit()
    return tokens


def refresh(session: Session, raw_token: str) -> TokenResponse:
    token_hash = hash_refresh_token(raw_token)
    row = session.exec(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    ).first()
    if row is None:
        raise AppError(
            "INVALID_REFRESH",
            "انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.",
            401,
        )
    if row.revoked_at is not None:
        _revoke_all(session, row.user_id)
        session_cache.revoke_user(str(row.user_id))
        write_audit(
            session,
            actor_id=row.user_id,
            action="refresh_reuse",
            entity="user",
            entity_id=str(row.user_id),
            detail=None,
        )
        session.commit()
        raise AppError(
            "INVALID_REFRESH",
            "انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.",
            401,
        )
    expires = as_utc(row.expires_at)
    if expires is None or expires <= utcnow():
        raise AppError(
            "INVALID_REFRESH",
            "انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.",
            401,
        )
    user = session.get(User, row.user_id)
    if user is None or not user.is_active:
        raise AppError(
            "ACCOUNT_INACTIVE",
            "هذا الحساب غير نشط. راجع مدير المحطة.",
            401,
        )
    row.revoked_at = utcnow()
    session.add(row)
    if row.access_jti:
        session_cache.revoke(row.access_jti)
    # Remember-me is a client choice. A rotated token keeps the longer window
    # when the stored expiry is still beyond the short session lifetime.
    from config import settings

    remaining = expires - utcnow()
    remember = remaining > timedelta(days=settings.refresh_token_days)
    tokens = _issue(session, user, remember)
    session.commit()
    return tokens


def logout(session: Session, raw_token: str) -> None:
    token_hash = hash_refresh_token(raw_token)
    row = session.exec(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    ).first()
    if row is not None and row.revoked_at is None:
        row.revoked_at = utcnow()
        session.add(row)
        if row.access_jti:
            session_cache.revoke(row.access_jti)
        write_audit(
            session,
            actor_id=row.user_id,
            action="logout",
            entity="user",
            entity_id=str(row.user_id),
            detail=None,
        )
        session.commit()


def change_password(session: Session, user: User, current_password: str, new_password: str) -> None:
    if not verify_password(current_password, user.password_hash):
        raise AppError("INVALID_CREDENTIALS", "كلمة المرور الحالية غير صحيحة.", 401)
    if current_password == new_password:
        raise AppError(
            "PASSWORD_REUSED",
            "اختر كلمة مرور مختلفة عن الحالية.",
            422,
        )
    user.password_hash = hash_password(new_password)
    user.updated_at = utcnow()
    session.add(user)
    _revoke_all(session, user.id)
    session_cache.revoke_user(str(user.id))
    write_audit(
        session,
        actor_id=user.id,
        action="password_changed",
        entity="user",
        entity_id=str(user.id),
        detail=None,
    )
    session.commit()


def _revoke_all(session: Session, user_id) -> None:
    rows = session.exec(
        select(RefreshToken).where(
            RefreshToken.user_id == user_id,
            RefreshToken.revoked_at.is_(None),
        )
    ).all()
    now = utcnow()
    for row in rows:
        row.revoked_at = now
        session.add(row)
