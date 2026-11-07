import uuid

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from auth.services import _revoke_all
from core.cache import session_cache
from core.security import hash_password
from enums import ROLE_NAMES, RoleCode, permissions_for
from errors import AppError
from users.audit import write_audit
from users.models import User
from users.schemas import RolePublic, StaffPublic, UserCreate, UserUpdate
from utils import utcnow

_ROLE_ORDER = [RoleCode.STATION_MANAGER, RoleCode.OPERATOR]


def list_staff(
    session: Session,
    actor: User,
    *,
    search: str | None,
    role: str,
    limit: int,
    offset: int,
) -> tuple[list[StaffPublic], int]:
    if limit < 1 or limit > 100 or offset < 0:
        raise AppError("VALIDATION_ERROR", "حدود الصفحة غير صالحة.", 422)
    statement = select(User).where(User.station_id == actor.station_id)
    if role == "maintenance":
        statement = statement.where(User.is_maintenance == True)  # noqa: E712
    elif role and role != "all":
        if role not in ROLE_NAMES:
            return [], 0
        statement = statement.where(User.role == role)
    rows = session.exec(statement.order_by(User.full_name)).all()
    needle = (search or "").strip().casefold()
    if needle:
        rows = [
            row
            for row in rows
            if needle in row.full_name.casefold()
            or needle in row.username.casefold()
            or needle in (row.email or "").casefold()
            or needle in row.employee_code.casefold()
        ]
    page = rows[offset : offset + limit]
    return [_staff(session, row) for row in page], len(rows)


def create_staff(session: Session, actor: User, payload: UserCreate) -> StaffPublic:
    full_name = payload.full_name.strip()
    username = payload.username.strip()
    if not full_name or not username:
        raise AppError("VALIDATION_ERROR", "الاسم واسم المستخدم مطلوبان.", 422)
    _check_password(payload.password)
    role = _role_code(payload.role_code)
    email = _clean_email(payload.email)
    user = User(
        station_id=actor.station_id,
        role=role,
        employee_code=_next_employee_code(session, actor.station_id),
        full_name=full_name,
        username=username,
        email=email,
        password_hash=hash_password(payload.password),
        job_title=payload.job_title.strip(),
        is_active=True,
        is_maintenance=payload.is_maintenance,
    )
    session.add(user)
    try:
        session.flush()
    except IntegrityError as exc:
        session.rollback()
        raise AppError("DUPLICATE_USER", "اسم المستخدم مستخدم بالفعل في هذه المحطة.", 409) from exc
    write_audit(
        session,
        actor_id=actor.id,
        action="user_created",
        entity="user",
        entity_id=str(user.id),
        detail={"username": username, "role_code": role},
    )
    session.commit()
    session.refresh(user)
    return _staff(session, user)


def update_staff(session: Session, actor: User, user_id: uuid.UUID, payload: UserUpdate) -> StaffPublic:
    target = session.get(User, user_id)
    if target is None or target.station_id != actor.station_id:
        raise AppError("USER_NOT_FOUND", "تعذر العثور على المستخدم.", 404)
    data = payload.model_dump(exclude_unset=True)
    revoke = False
    if "full_name" in data and data["full_name"] is not None:
        name = data["full_name"].strip()
        if not name:
            raise AppError("VALIDATION_ERROR", "الاسم مطلوب.", 422)
        target.full_name = name
    if "username" in data and data["username"] is not None:
        username = data["username"].strip()
        if not username:
            raise AppError("VALIDATION_ERROR", "اسم المستخدم مطلوب.", 422)
        target.username = username
    if "email" in data:
        target.email = _clean_email(data["email"])
    if "job_title" in data and data["job_title"] is not None:
        target.job_title = data["job_title"].strip()
    if "is_maintenance" in data and data["is_maintenance"] is not None:
        target.is_maintenance = data["is_maintenance"]
    if "role_code" in data and data["role_code"] is not None:
        role = _role_code(data["role_code"])
        if target.role != role:
            target.role = role
            revoke = True
    if "is_active" in data and data["is_active"] is not None:
        if data["is_active"] is False and target.id == actor.id:
            raise AppError("VALIDATION_ERROR", "لا يمكنك إيقاف حسابك.", 422)
        if target.is_active != data["is_active"]:
            target.is_active = data["is_active"]
            revoke = True
    if "password" in data and data["password"]:
        _check_password(data["password"])
        target.password_hash = hash_password(data["password"])
        target.failed_login_count = 0
        target.locked_until = None
        revoke = True
    target.updated_at = utcnow()
    session.add(target)
    if revoke:
        _revoke_all(session, target.id)
        session_cache.revoke_user(str(target.id))
    write_audit(
        session,
        actor_id=actor.id,
        action="user_updated",
        entity="user",
        entity_id=str(target.id),
        detail={"revoked_sessions": revoke},
    )
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise AppError("DUPLICATE_USER", "اسم المستخدم مستخدم بالفعل في هذه المحطة.", 409) from exc
    session.refresh(target)
    return _staff(session, target)


def list_roles() -> list[RolePublic]:
    return [
        RolePublic(
            id=code,
            code=code,
            name_ar=ROLE_NAMES[code],
            permissions=permissions_for(code),
        )
        for code in _ROLE_ORDER
    ]


def save_photo(session: Session, actor: User, target_id: uuid.UUID, upload) -> StaffPublic:
    from stations.services import store_image

    target = session.get(User, target_id)
    if target is None or target.station_id != actor.station_id:
        raise AppError("USER_NOT_FOUND", "تعذر العثور على الموظف.", 404)
    if target.id != actor.id:
        if "users.manage" not in permissions_for(actor.role):
            raise AppError("FORBIDDEN", "ليست لديك صلاحية لتعديل صورة هذا الحساب.", 403)
    target.photo_url = store_image(upload, f"user-{target.id}")
    target.updated_at = utcnow()
    session.add(target)
    write_audit(
        session,
        actor_id=actor.id,
        action="user_photo_updated",
        entity="user",
        entity_id=str(target.id),
        detail={"photo_url": target.photo_url},
    )
    session.commit()
    session.refresh(target)
    return _staff(session, target)


def _staff(session: Session, user: User) -> StaffPublic:
    return StaffPublic(
        id=str(user.id),
        employee_code=user.employee_code,
        full_name=user.full_name,
        username=user.username,
        email=user.email,
        job_title=user.job_title,
        role_code=user.role,
        role_name_ar=ROLE_NAMES.get(user.role, user.role),
        is_active=user.is_active,
        is_maintenance=user.is_maintenance,
        photo_url=user.photo_url,
        last_login_at=user.last_login_at,
    )


def _role_code(code: str) -> str:
    cleaned = code.strip()
    if cleaned not in ROLE_NAMES:
        raise AppError("VALIDATION_ERROR", "الدور المحدد غير موجود.", 422)
    return cleaned


def _check_password(password: str) -> None:
    if len(password) < 8:
        raise AppError("VALIDATION_ERROR", "كلمة المرور يجب ألا تقل عن 8 أحرف.", 422)


def _clean_email(email: str | None) -> str | None:
    if email is None:
        return None
    cleaned = email.strip()
    return cleaned or None


def _next_employee_code(session: Session, station_id: uuid.UUID) -> str:
    rows = session.exec(select(User.employee_code).where(User.station_id == station_id)).all()
    numbers = []
    for code in rows:
        if isinstance(code, str) and code.startswith("EMP-"):
            try:
                numbers.append(int(code[4:]))
            except ValueError:
                continue
    return f"EMP-{(max(numbers) if numbers else 0) + 1:04d}"
