from datetime import date
from decimal import Decimal

from sqlmodel import Session, select

from core.security import hash_password
from enums import RoleCode
from stations.models import FuelPrice, FuelProduct, Station
from users.models import User

# The mock prints 2024-12-31, which is already past. The live station is licensed
# through the next renewal so Phase 7's 30-day warning does not fire on a fresh seed.
_LICENSE_EXPIRES = date(2027, 12, 31)

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

    _ensure_user(
        session,
        station=station,
        role=RoleCode.STATION_MANAGER,
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
        role=RoleCode.OPERATOR,
        username=settings.seed_operator_username,
        password=settings.seed_operator_password,
        employee_code="EMP-0122",
        full_name="محمد مصطفى القذافي",
        job_title="فني مضخات ووردية",
        email="operator@station.local",
    )
    _ensure_catalog(session, station, settings.seed_manager_username)
    if settings.seed_demo_assets:
        from assets.seed import seed_initial_assets

        seed_initial_assets(session, station, settings.seed_manager_username)
    from supply.seed import seed_suppliers

    seed_suppliers(session, station)
    session.commit()


def _ensure_user(
    session: Session,
    *,
    station: Station,
    role: str,
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
            role=role,
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
