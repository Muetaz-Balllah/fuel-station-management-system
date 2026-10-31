from datetime import datetime, time, timedelta, timezone
from decimal import Decimal

from sqlmodel import Session, select

from assets.levels import as_decimal, station_timezone
from assets.models import InventoryMovement, Nozzle, Pump, Tank
from stations.models import FuelProduct, Station
from users.models import User
from utils import utcnow


def seed_demo_assets(session: Session, station: Station, actor_username: str) -> None:
    """Demo layout from the tanks mock. Volumes match the ledger rows written here."""
    existing = session.exec(select(Tank).where(Tank.station_id == station.id)).first()
    if existing is not None:
        return
    actor = session.exec(
        select(User).where(User.station_id == station.id, User.username == actor_username)
    ).first()
    products = {
        row.code: row
        for row in session.exec(select(FuelProduct).where(FuelProduct.station_id == station.id)).all()
    }
    if "G95" not in products or "DIESEL" not in products:
        return
    tz = station_timezone(station.timezone)
    now = utcnow()
    cards = (
        _card("T-01", "خزان بنزين 95", "G95", "25000", "19000", "PUMP-01", "active", "2850", -1, 8, 30,
              (("N1", "يمين", "ready", "680150"), ("N2", "يسار", "ready", "565152"))),
        _card("T-02", "خزان بنزين 95", "G95", "25000", "17000", "PUMP-02", "active", "1350", -1, 8, 30,
              (("N1", "يمين", "ready", "450110"), ("N2", "يسار", "ready", "442000"))),
        _card("TD-01", "خزان ديزل", "DIESEL", "50000", "11000", "PUMP-D1", "maintenance", "6200", -3, 8, 0,
              (("N1", "شاحنات ثقيلة", "valve_check", "2100000"), ("N2", "ربع (الدقيق)", "calibrating", "2012050"))),
        _card("TD-02", "خزان ديزل", "DIESEL", "50000", "42000", "PUMP-D2", "active", "6300", 0, 6, 15,
              (("N1", "يمين", "ready", "1990200"), ("N2", "يسار", "ready", "1990240"))),
    )
    for spec in cards:
        product = products[spec["product"]]
        current = as_decimal(spec["current"])
        draw = as_decimal(spec["today"])
        tank = Tank(
            station_id=station.id,
            product_id=product.id,
            code=spec["tank_code"],
            name=spec["tank_name"],
            capacity_liters=as_decimal(spec["capacity"]),
            current_liters=current,
            is_demo=True,
        )
        session.add(tank)
        session.flush()
        pump = Pump(
            station_id=station.id,
            tank_id=tank.id,
            code=spec["pump_code"],
            name=f"وحدة مضخة {spec['pump_code']}",
            status=spec["status"],
            is_demo=True,
        )
        session.add(pump)
        session.flush()
        first_nozzle = None
        for code, label, status, meter in spec["nozzles"]:
            nozzle = Nozzle(
                station_id=station.id,
                pump_id=pump.id,
                code=code,
                label=label,
                status=status,
                current_meter=as_decimal(meter),
            )
            session.add(nozzle)
            session.flush()
            if first_nozzle is None:
                first_nozzle = nozzle
        received = current + draw
        receipt_at = _local(now, tz, spec["receipt_offset"], spec["hour"], spec["minute"])
        session.add(
            InventoryMovement(
                station_id=station.id,
                tank_id=tank.id,
                movement_type="supply_receipt",
                liters_delta=received,
                balance_after=received,
                source_type="demo",
                note="بيانات تجريبية",
                created_by=actor.id if actor else None,
                created_at=receipt_at,
            )
        )
        session.add(
            InventoryMovement(
                station_id=station.id,
                tank_id=tank.id,
                nozzle_id=first_nozzle.id if first_nozzle else None,
                movement_type="shift_sale",
                liters_delta=-draw,
                balance_after=current,
                source_type="demo",
                note="بيانات تجريبية",
                created_by=actor.id if actor else None,
                created_at=now,
            )
        )


def _card(tank_code, tank_name, product, capacity, current, pump_code, status, today, offset, hour, minute, nozzles):
    return {
        "tank_code": tank_code,
        "tank_name": tank_name,
        "product": product,
        "capacity": capacity,
        "current": current,
        "pump_code": pump_code,
        "status": status,
        "today": today,
        "receipt_offset": offset,
        "hour": hour,
        "minute": minute,
        "nozzles": nozzles,
    }


def _local(now: datetime, tz, day_offset: int, hour: int, minute: int) -> datetime:
    local_day = now.astimezone(tz).date() + timedelta(days=day_offset)
    local = datetime.combine(local_day, time(hour, minute), tzinfo=tz)
    return local.astimezone(timezone.utc)
