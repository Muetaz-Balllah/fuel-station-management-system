import uuid

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from auth.services import _revoke_all
from core.cache import session_cache
from core.deps import permission_codes
from core.security import hash_password
from enums import PermissionCode, RoleCode
from errors import AppError
from users.audit import write_audit
from users.models import Permission, Role, RolePermission, User
from users.schemas import PermissionReplace, RolePublic, StaffPublic, UserCreate, UserUpdate
from utils import utcnow

_ROLE_ORDER = [RoleCode.SYSTEM_ADMIN, RoleCode.STATION_MANAGER, RoleCode.OPERATOR]


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
        role_row = session.exec(select(Role).where(Role.code == role)).first()
        if role_row is None:
            return [], 0
        statement = statement.where(User.role_id == role_row.id)
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
    role = _role_by_code(session, payload.role_code)
    _guard_admin_assignment(session, actor, role)
    email = _clean_email(payload.email)
    user = User(
        station_id=actor.station_id,
        role_id=role.id,
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
        detail={"username": username, "role_code": role.code},
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
        role = _role_by_code(session, data["role_code"])
        _guard_admin_assignment(session, actor, role)
        if target.role_id != role.id:
            target.role_id = role.id
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


def list_roles(session: Session) -> list[RolePublic]:
    rows = session.exec(select(Role)).all()
    order = {code: index for index, code in enumerate(_ROLE_ORDER)}
    rows.sort(key=lambda row: order.get(row.code, 99))
    return [
        RolePublic(
            id=str(row.id),
            code=row.code,
            name_ar=row.name_ar,
            permissions=permission_codes(session, row.id),
        )
        for row in rows
    ]


def replace_permissions(
    session: Session,
    actor: User,
    role_id: uuid.UUID,
    payload: PermissionReplace,
) -> RolePublic:
    role = session.get(Role, role_id)
    if role is None:
        raise AppError("ROLE_NOT_FOUND", "تعذر العثور على الدور.", 404)
    unknown = [code for code in payload.permissions if code not in PermissionCode.ALL]
    if unknown:
        raise AppError("VALIDATION_ERROR", "صلاحية غير معروفة.", 422)
    if role.code == RoleCode.SYSTEM_ADMIN and PermissionCode.USERS_MANAGE not in payload.permissions:
        raise AppError(
            "VALIDATION_ERROR",
            "لا يمكن سحب صلاحية إدارة المستخدمين من مدير النظام.",
            422,
        )
    existing = session.exec(
        select(RolePermission).where(RolePermission.role_id == role.id)
    ).all()
    for row in existing:
        session.delete(row)
    session.flush()
    for code in dict.fromkeys(payload.permissions):
        permission = session.exec(select(Permission).where(Permission.code == code)).first()
        if permission is None:
            raise AppError("VALIDATION_ERROR", "صلاحية غير معروفة.", 422)
        session.add(RolePermission(role_id=role.id, permission_id=permission.id))
    holders = session.exec(select(User).where(User.role_id == role.id)).all()
    write_audit(
        session,
        actor_id=actor.id,
        action="role_permissions_replaced",
        entity="role",
        entity_id=str(role.id),
        detail={"permissions": payload.permissions},
    )
    for holder in holders:
        session_cache.revoke_user(str(holder.id))
    session.commit()
    return RolePublic(
        id=str(role.id),
        code=role.code,
        name_ar=role.name_ar,
        permissions=permission_codes(session, role.id),
    )


def _staff(session: Session, user: User) -> StaffPublic:
    role = session.get(Role, user.role_id)
    return StaffPublic(
        id=str(user.id),
        employee_code=user.employee_code,
        full_name=user.full_name,
        username=user.username,
        email=user.email,
        job_title=user.job_title,
        role_code=role.code if role else "",
        role_name_ar=role.name_ar if role else "",
        is_active=user.is_active,
        is_maintenance=user.is_maintenance,
        last_login_at=user.last_login_at,
    )


def _role_by_code(session: Session, code: str) -> Role:
    role = session.exec(select(Role).where(Role.code == code.strip())).first()
    if role is None:
        raise AppError("VALIDATION_ERROR", "الدور المحدد غير موجود.", 422)
    return role


def _guard_admin_assignment(session: Session, actor: User, role: Role) -> None:
    if role.code != RoleCode.SYSTEM_ADMIN:
        return
    actor_role = session.get(Role, actor.role_id)
    if actor_role is None or actor_role.code != RoleCode.SYSTEM_ADMIN:
        raise AppError(
            "FORBIDDEN",
            "فقط مدير النظام يستطيع تعيين دور مدير النظام.",
            403,
        )


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
