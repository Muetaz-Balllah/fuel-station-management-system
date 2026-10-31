from datetime import date, time
from decimal import Decimal

from sqlmodel import Session, select

from core.security import hash_password
from enums import PermissionCode, RoleCode
from stations.models import FuelPrice, FuelProduct, ShiftTemplate, Station
from users.models import Permission, Role, RolePermission, User

# The mock prints 2024-12-31, which is already past. The live station is licensed
# through the next renewal so Phase 7's 30-day warning does not fire on a fresh seed.
_LICENSE_EXPIRES = date(2027, 12, 31)

_ROLE_NAMES = {
    RoleCode.SYSTEM_ADMIN: "مدير النظام",
    RoleCode.STATION_MANAGER: "مدير المحطة",
    RoleCode.OPERATOR: "موظف",
}

_ROLE_GRANTS = {
    RoleCode.SYSTEM_ADMIN: PermissionCode.ALL,
    RoleCode.STATION_MANAGER: PermissionCode.ALL,
    RoleCode.OPERATOR: [PermissionCode.SHIFTS_OPERATE],
}


def seed(session: Session, settings) -> None:
    station = session.exec(select(Station).where(Station.code == "ST-104")).first()
    if station is None:
        station = Station(
            code="ST-104",
            name="محطة طريق المطار - طرابلس",
            license_number="LY-4492-TPS",
            license_expires_on=_LICENSE_EXPIRES,
            latitude=32.8872,
            longitude=13.1913,
            timezone="Africa/Tripoli",
        )
        session.add(station)
        session.flush()

    roles: dict[str, Role] = {}
    for code, name in _ROLE_NAMES.items():
        role = session.exec(select(Role).where(Role.code == code)).first()
        if role is None:
            role = Role(code=code, name_ar=name, is_system=True)
            session.add(role)
            session.flush()
        roles[code] = role

    permissions: dict[str, Permission] = {}
    for code in PermissionCode.ALL:
        permission = session.exec(
            select(Permission).where(Permission.code == code)
        ).first()
        if permission is None:
            permission = Permission(code=code)
            session.add(permission)
            session.flush()
        permissions[code] = permission

    for role_code, grants in _ROLE_GRANTS.items():
        role = roles[role_code]
        existing = session.exec(
            select(RolePermission).where(RolePermission.role_id == role.id)
        ).all()
        held = {row.permission_id for row in existing}
        for grant in grants:
            permission = permissions[grant]
            if permission.id not in held:
                session.add(
                    RolePermission(role_id=role.id, permission_id=permission.id)
                )

    _ensure_user(
        session,
        station=station,
        role=roles[RoleCode.SYSTEM_ADMIN],
        username=settings.seed_admin_username,
        password=settings.seed_admin_password,
        employee_code="EMP-0000",
        full_name="مدير النظام",
        job_title="مدير النظام",
        email="admin@station.local",
    )
    _ensure_user(
        session,
        station=station,
        role=roles[RoleCode.STATION_MANAGER],
        username=settings.seed_manager_username,
        password=settings.seed_manager_password,
        employee_code="EMP-0001",
        full_name="أحمد المصراتي",
        job_title="مدير المحطة",
        email="manager@station.local",
    )
    _ensure_user(
        session,
        station=station,
        role=roles[RoleCode.OPERATOR],
        username=settings.seed_operator_username,
        password=settings.seed_operator_password,
        employee_code="EMP-0122",
        full_name="محمد مصطفى القذافي",
        job_title="فني مضخات ووردية",
        email="operator@station.local",
    )
    _ensure_catalog(session, station, settings.seed_admin_username)
    if settings.seed_demo_assets:
        from assets.seed import seed_demo_assets

        seed_demo_assets(session, station, settings.seed_manager_username)
    from supply.seed import seed_suppliers

    seed_suppliers(session, station)
    session.commit()


def _ensure_user(
    session: Session,
    *,
    station: Station,
    role: Role,
    username: str,
    password: str,
    employee_code: str,
    full_name: str,
    job_title: str,
    email: str,
) -> None:
    found = session.exec(
        select(User).where(
            User.station_id == station.id,
            User.username == username,
        )
    ).first()
    if found is not None:
        return
    session.add(
        User(
            station_id=station.id,
            role_id=role.id,
            employee_code=employee_code,
            full_name=full_name,
            username=username,
            email=email,
            password_hash=hash_password(password),
            job_title=job_title,
            is_active=True,
        )
    )


def _ensure_catalog(session: Session, station: Station, admin_username: str) -> None:
    session.flush()
    admin = session.exec(
        select(User).where(
            User.station_id == station.id,
            User.username == admin_username,
        )
    ).first()
    existing = session.exec(
        select(FuelProduct).where(FuelProduct.station_id == station.id)
    ).first()
    if existing is None:
        created: list[FuelProduct] = []
        for code, name, order in (
            ("G95", "بنزين 95", 1),
            ("G98", "بنزين 98", 2),
            ("DIESEL", "ديزل", 3),
            ("KEROSENE", "كيروسين", 4),
        ):
            product = FuelProduct(
                station_id=station.id,
                code=code,
                name_ar=name,
                sort_order=order,
            )
            session.add(product)
            created.append(product)
        session.flush()
        gasoline = next(item for item in created if item.code == "G95")
        session.add(
            FuelPrice(
                product_id=gasoline.id,
                price_per_liter=Decimal("0.150"),
                created_by=admin.id if admin else None,
            )
        )
    templates = session.exec(
        select(ShiftTemplate).where(ShiftTemplate.station_id == station.id)
    ).first()
    if templates is None:
        session.add(
            ShiftTemplate(
                station_id=station.id,
                name_ar="صباحية",
                starts_at=time(8, 0),
                ends_at=time(16, 0),
                grace_minutes=10,
                sort_order=1,
            )
        )
        session.add(
            ShiftTemplate(
                station_id=station.id,
                name_ar="مسائية",
                starts_at=time(16, 0),
                ends_at=time(0, 0),
                grace_minutes=10,
                sort_order=2,
            )
        )
