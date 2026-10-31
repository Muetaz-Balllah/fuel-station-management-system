import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlmodel import Session, select

from alerts import note_tank_crossing
from assets.levels import (
    as_decimal,
    format_qty,
    level_band,
    percent_of,
    receipt_label,
    station_timezone,
)
from assets.models import InventoryMovement, Nozzle, Pump, Tank
from errors import AppError
from stations.models import FuelProduct, Station
from users.audit import write_audit
from users.models import User
from utils import as_utc, utcnow

PUMP_LABELS = {
    "active": "نشطة",
    "maintenance": "صيانة",
    "inactive": "متوقفة",
}
NOZZLE_LABELS = {
    "ready": "جاهز",
    "valve_check": "فحص الصمام",
    "calibrating": "معايرة عداد",
    "inactive": "متوقف",
}
BAND_LABELS = {
    "stable": "مستقر",
    "warning": "تحذير",
    "critical": "حرج",
    "maintenance": "يحتاج صيانة",
}
MOVEMENT_LABELS = {
    "opening_balance": "رصيد افتتاحي",
    "supply_receipt": "توريد",
    "shift_sale": "وردية منتهية (تفريغ مسدس)",
    "adjustment": "تسوية",
}


def list_tanks(session: Session, user: User) -> list[dict]:
    tanks = _tanks(session, user.station_id)
    pumps = _pumps(session, user.station_id)
    by_tank = {pump.tank_id: pump for pump in pumps}
    return [_tank_public(session, tank, by_tank.get(tank.id), user) for tank in tanks]


def create_tank(session: Session, user: User, payload) -> dict:
    name = payload.name.strip()
    if not name:
        raise AppError("VALIDATION_ERROR", "اسم الخزان مطلوب.", 422)
    product = _product(session, user, payload.product_id)
    capacity = _positive(payload.capacity_liters, "سعة الخزان يجب أن تكون أكبر من صفر.")
    tank = Tank(
        station_id=user.station_id,
        product_id=product.id,
        code=_next_tank_code(session, user.station_id, product.code),
        name=name,
        capacity_liters=capacity,
        current_liters=Decimal("0.000"),
    )
    session.add(tank)
    session.flush()
    write_audit(
        session,
        actor_id=user.id,
        action="tank_created",
        entity="tank",
        entity_id=str(tank.id),
        detail={"code": tank.code},
    )
    session.commit()
    session.refresh(tank)
    return _tank_public(session, tank, None, user)


def update_tank(session: Session, user: User, tank_id: uuid.UUID, payload) -> dict:
    tank = _tank(session, user, tank_id)
    data = payload.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        name = data["name"].strip()
        if not name:
            raise AppError("VALIDATION_ERROR", "اسم الخزان مطلوب.", 422)
        tank.name = name
    if "critical_percent" in data and data["critical_percent"] is not None:
        tank.critical_percent = data["critical_percent"]
    if "warning_percent" in data and data["warning_percent"] is not None:
        tank.warning_percent = data["warning_percent"]
    if tank.critical_percent < 1 or tank.critical_percent > 99:
        raise AppError("VALIDATION_ERROR", "حد الحرج يجب أن يكون بين 1 و 99.", 422)
    if tank.warning_percent <= tank.critical_percent or tank.warning_percent > 100:
        raise AppError("VALIDATION_ERROR", "حد التحذير يجب أن يكون أعلى من حد الحرج.", 422)
    if "is_active" in data and data["is_active"] is not None:
        tank.is_active = data["is_active"]
    tank.updated_at = utcnow()
    session.add(tank)
    write_audit(
        session,
        actor_id=user.id,
        action="tank_updated",
        entity="tank",
        entity_id=str(tank.id),
        detail=None,
    )
    session.commit()
    session.refresh(tank)
    pump = session.exec(select(Pump).where(Pump.tank_id == tank.id)).first()
    return _tank_public(session, tank, pump, user)


def adjust_tank(session: Session, user: User, tank_id: uuid.UUID, payload) -> dict:
    note = payload.note.strip()
    if not note:
        raise AppError("VALIDATION_ERROR", "اكتب سبب التسوية.", 422)
    delta = _delta(payload.liters_delta)
    tank = _tank(session, user, tank_id)
    before = as_decimal(tank.current_liters)
    balance = before + delta
    capacity = as_decimal(tank.capacity_liters)
    if balance < 0 or balance > capacity:
        raise AppError(
            "BALANCE_OUT_OF_RANGE",
            "الكمية تخرج عن سعة الخزان أو تجعل الرصيد سالباً.",
            422,
        )
    tank.current_liters = balance
    tank.updated_at = utcnow()
    session.add(tank)
    note_tank_crossing(session, tank, before, balance)
    session.add(
        InventoryMovement(
            station_id=user.station_id,
            tank_id=tank.id,
            movement_type="adjustment",
            liters_delta=delta,
            balance_after=balance,
            source_type="adjustment",
            note=note,
            created_by=user.id,
        )
    )
    write_audit(
        session,
        actor_id=user.id,
        action="tank_adjusted",
        entity="tank",
        entity_id=str(tank.id),
        detail={"liters_delta": format_qty(delta), "balance_after": format_qty(balance)},
    )
    session.commit()
    session.refresh(tank)
    pump = session.exec(select(Pump).where(Pump.tank_id == tank.id)).first()
    return _tank_public(session, tank, pump, user)


def list_pumps(session: Session, user: User) -> list[dict]:
    pumps = _pumps(session, user.station_id)
    return [_pump_public(session, pump) for pump in pumps]


def create_pump(session: Session, user: User, payload) -> dict:
    code = payload.code.strip().upper()
    if not code:
        raise AppError("VALIDATION_ERROR", "رمز المضخة مطلوب.", 422)
    tank = _tank(session, user, uuid.UUID(payload.tank_id))
    taken = session.exec(select(Pump).where(Pump.tank_id == tank.id)).first()
    if taken is not None:
        raise AppError(
            "TANK_ALREADY_LINKED",
            "هذا الخزان مرتبط بمضخة أخرى. كل مضخة لها خزان مستقل.",
            409,
        )
    duplicate = session.exec(
        select(Pump).where(Pump.station_id == user.station_id, Pump.code == code)
    ).first()
    if duplicate is not None:
        raise AppError("DUPLICATE_PUMP", "رمز المضخة مستخدم بالفعل.", 409)
    pump = Pump(
        station_id=user.station_id,
        tank_id=tank.id,
        code=code,
        name=f"وحدة مضخة {code}",
        status="active",
    )
    session.add(pump)
    session.flush()
    write_audit(
        session,
        actor_id=user.id,
        action="pump_created",
        entity="pump",
        entity_id=str(pump.id),
        detail={"code": code, "tank_id": str(tank.id)},
    )
    session.commit()
    session.refresh(pump)
    return _pump_public(session, pump)


def update_pump(session: Session, user: User, pump_id: uuid.UUID, payload) -> dict:
    pump = _pump(session, user, pump_id)
    if payload.status not in PUMP_LABELS:
        raise AppError("VALIDATION_ERROR", "حالة المضخة غير معروفة.", 422)
    pump.status = payload.status
    pump.updated_at = utcnow()
    session.add(pump)
    write_audit(
        session,
        actor_id=user.id,
        action="pump_updated",
        entity="pump",
        entity_id=str(pump.id),
        detail={"status": pump.status},
    )
    session.commit()
    session.refresh(pump)
    return _pump_public(session, pump)


def create_nozzle(session: Session, user: User, pump_id: uuid.UUID, payload) -> dict:
    pump = _pump(session, user, pump_id)
    code = payload.code.strip().upper()
    label = payload.label.strip()
    if not code or not label:
        raise AppError("VALIDATION_ERROR", "رمز المسدس وجهته مطلوبان.", 422)
    if payload.status not in NOZZLE_LABELS:
        raise AppError("VALIDATION_ERROR", "حالة المسدس غير معروفة.", 422)
    existing = session.exec(
        select(Nozzle).where(Nozzle.pump_id == pump.id, Nozzle.code == code)
    ).first()
    if existing is not None:
        raise AppError("DUPLICATE_NOZZLE", "رمز المسدس مستخدم على هذه المضخة.", 409)
    meter = _meter(payload.initial_meter)
    nozzle = Nozzle(
        station_id=user.station_id,
        pump_id=pump.id,
        code=code,
        label=label,
        status=payload.status,
        current_meter=meter,
    )
    session.add(nozzle)
    session.flush()
    write_audit(
        session,
        actor_id=user.id,
        action="nozzle_created",
        entity="nozzle",
        entity_id=str(nozzle.id),
        detail={"code": code, "pump_id": str(pump.id), "meter": format_qty(meter)},
    )
    session.commit()
    session.refresh(nozzle)
    return _nozzle_public(nozzle)


def update_nozzle(session: Session, user: User, nozzle_id: uuid.UUID, payload) -> dict:
    nozzle = session.get(Nozzle, nozzle_id)
    if nozzle is None or nozzle.station_id != user.station_id:
        raise AppError("NOZZLE_NOT_FOUND", "تعذر العثور على المسدس.", 404)
    data = payload.model_dump(exclude_unset=True)
    if "label" in data and data["label"] is not None:
        label = data["label"].strip()
        if not label:
            raise AppError("VALIDATION_ERROR", "جهة المسدس مطلوبة.", 422)
        nozzle.label = label
    if "status" in data and data["status"] is not None:
        if data["status"] not in NOZZLE_LABELS:
            raise AppError("VALIDATION_ERROR", "حالة المسدس غير معروفة.", 422)
        nozzle.status = data["status"]
    nozzle.updated_at = utcnow()
    session.add(nozzle)
    write_audit(
        session,
        actor_id=user.id,
        action="nozzle_updated",
        entity="nozzle",
        entity_id=str(nozzle.id),
        detail=None,
    )
    session.commit()
    session.refresh(nozzle)
    return _nozzle_public(nozzle)


def board(session: Session, user: User) -> dict:
    station = session.get(Station, user.station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    now = utcnow()
    tanks = _tanks(session, user.station_id)
    pumps = _pumps(session, user.station_id)
    products = session.exec(
        select(FuelProduct)
        .where(FuelProduct.station_id == user.station_id, FuelProduct.is_active == True)  # noqa: E712
        .order_by(FuelProduct.sort_order)
    ).all()
    linked = {pump.tank_id for pump in pumps}
    cards = []
    for pump in pumps:
        tank = next((item for item in tanks if item.id == pump.tank_id), None)
        if tank is None:
            continue
        nozzles = session.exec(
            select(Nozzle).where(Nozzle.pump_id == pump.id).order_by(Nozzle.code)
        ).all()
        cards.append(_card(session, pump, tank, nozzles, user, tz, now))
    free = [
        _tank_public(session, tank, None, user)
        for tank in tanks
        if tank.id not in linked and tank.is_active
    ]
    return {
        "products": [{"id": str(item.id), "code": item.code, "name_ar": item.name_ar} for item in products],
        "cards": cards,
        "free_tanks": free,
        "demo": any(pump.is_demo for pump in pumps),
    }


def list_events(
    session: Session,
    user: User,
    *,
    product_id: str | None,
    date_from: str | None,
    date_to: str | None,
    limit: int,
    offset: int,
) -> tuple[list[dict], int]:
    if limit < 1 or limit > 100 or offset < 0:
        raise AppError("VALIDATION_ERROR", "حدود الصفحة غير صالحة.", 422)
    statement = select(InventoryMovement).where(InventoryMovement.station_id == user.station_id)
    if product_id:
        product = _product(session, user, product_id)
        tank_ids = [
            tank.id
            for tank in session.exec(select(Tank).where(Tank.product_id == product.id)).all()
        ]
        if not tank_ids:
            return [], 0
        statement = statement.where(InventoryMovement.tank_id.in_(tank_ids))  # type: ignore[attr-defined]
    rows = session.exec(statement.order_by(InventoryMovement.created_at.desc())).all()
    start = _parse_date(date_from)
    end = _parse_date(date_to)
    if start or end:
        kept = []
        for row in rows:
            moment = as_utc(row.created_at)
            if moment is None:
                continue
            if start and moment.date() < start:
                continue
            if end and moment.date() > end:
                continue
            kept.append(row)
        rows = kept
    page = rows[offset : offset + limit]
    return [_event_public(session, row) for row in page], len(rows)


def _card(session, pump, tank, nozzles, user, tz, now) -> dict:
    product = session.get(FuelProduct, tank.product_id)
    percent = percent_of(tank.current_liters, tank.capacity_liters)
    band = "maintenance" if pump.status == "maintenance" else level_band(
        percent, tank.critical_percent, tank.warning_percent
    )
    return {
        "pump": _pump_public(session, pump),
        "tank": {
            **_tank_body(session, tank, product, tz, now),
            "percent": percent,
            "level_band": level_band(percent, tank.critical_percent, tank.warning_percent),
            "card_band": band,
            "card_band_label": BAND_LABELS[band],
        },
        "nozzles": [_nozzle_public(item) for item in nozzles],
    }


def _tank_public(session, tank: Tank, pump: Pump | None, user: User) -> dict:
    station = session.get(Station, user.station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    product = session.get(FuelProduct, tank.product_id)
    percent = percent_of(tank.current_liters, tank.capacity_liters)
    band = level_band(percent, tank.critical_percent, tank.warning_percent)
    body = _tank_body(session, tank, product, tz, utcnow())
    body.update(
        {
            "percent": percent,
            "level_band": band,
            "level_band_label": BAND_LABELS[band],
            "pump": None
            if pump is None
            else {"id": str(pump.id), "code": pump.code, "status": pump.status},
        }
    )
    return body


def _tank_body(session, tank: Tank, product: FuelProduct | None, tz, now: datetime) -> dict:
    return {
        "id": str(tank.id),
        "code": tank.code,
        "name": tank.name,
        "product_id": str(tank.product_id),
        "product_name": product.name_ar if product else "",
        "product_code": product.code if product else "",
        "capacity_liters": format_qty(tank.capacity_liters),
        "current_liters": format_qty(tank.current_liters),
        "critical_percent": tank.critical_percent,
        "warning_percent": tank.warning_percent,
        "is_active": tank.is_active,
        "is_demo": tank.is_demo,
        "last_receipt_at": _iso(_last_receipt(session, tank.id)),
        "last_receipt_label": receipt_label(_last_receipt(session, tank.id), now, tz),
        "today_liters": format_qty(_today_draw(session, tank.id, now, tz)),
    }


def _pump_public(session, pump: Pump) -> dict:
    tank = session.get(Tank, pump.tank_id)
    count = session.exec(select(Nozzle).where(Nozzle.pump_id == pump.id)).all()
    return {
        "id": str(pump.id),
        "code": pump.code,
        "name": pump.name,
        "status": pump.status,
        "status_label": PUMP_LABELS.get(pump.status, pump.status),
        "tank_id": str(pump.tank_id),
        "tank_code": tank.code if tank else "",
        "is_demo": pump.is_demo,
        "nozzle_count": len(count),
    }


def _nozzle_public(nozzle: Nozzle) -> dict:
    return {
        "id": str(nozzle.id),
        "pump_id": str(nozzle.pump_id),
        "code": nozzle.code,
        "label": nozzle.label,
        "status": nozzle.status,
        "status_label": NOZZLE_LABELS.get(nozzle.status, nozzle.status),
        "current_meter": format_qty(nozzle.current_meter),
    }


def _event_public(session: Session, row: InventoryMovement) -> dict:
    tank = session.get(Tank, row.tank_id)
    pump = session.exec(select(Pump).where(Pump.tank_id == row.tank_id)).first() if tank else None
    nozzle = session.get(Nozzle, row.nozzle_id) if row.nozzle_id else None
    actor = session.get(User, row.created_by) if row.created_by else None
    path = _path(pump, tank, nozzle)
    moment = as_utc(row.created_at)
    return {
        "id": str(row.id),
        "created_at": _iso(moment),
        "path": path,
        "movement_type": row.movement_type,
        "movement_label": MOVEMENT_LABELS.get(row.movement_type, row.movement_type),
        "liters_delta": format_qty(row.liters_delta),
        "balance_after": format_qty(row.balance_after),
        "note": row.note,
        "actor_name": actor.full_name if actor else "",
        "product_id": str(tank.product_id) if tank else None,
        "tank_code": tank.code if tank else "",
        "pump_code": pump.code if pump else "",
        "nozzle_code": nozzle.code if nozzle else "",
    }


def _path(pump: Pump | None, tank: Tank | None, nozzle: Nozzle | None) -> str:
    parts = []
    if pump is not None:
        parts.append(f"مضخة {pump.code}")
    if tank is not None:
        parts.append(f"خزان مستقل {tank.code}")
    if nozzle is not None:
        parts.append(f"مسدس {nozzle.code}")
    return " ← ".join(parts)


def _last_receipt(session: Session, tank_id: uuid.UUID) -> datetime | None:
    rows = session.exec(
        select(InventoryMovement)
        .where(
            InventoryMovement.tank_id == tank_id,
            InventoryMovement.movement_type == "supply_receipt",
        )
        .order_by(InventoryMovement.created_at.desc())
    ).all()
    if not rows:
        return None
    return as_utc(rows[0].created_at)


def _today_draw(session: Session, tank_id: uuid.UUID, now: datetime, tz) -> Decimal:
    today = now.astimezone(tz).date()
    rows = session.exec(
        select(InventoryMovement).where(
            InventoryMovement.tank_id == tank_id,
            InventoryMovement.movement_type == "shift_sale",
        )
    ).all()
    total = Decimal("0.000")
    for row in rows:
        moment = as_utc(row.created_at)
        if moment is None or moment.astimezone(tz).date() != today:
            continue
        total += abs(as_decimal(row.liters_delta))
    return total


def _tanks(session: Session, station_id: uuid.UUID) -> list[Tank]:
    return list(
        session.exec(select(Tank).where(Tank.station_id == station_id).order_by(Tank.code)).all()
    )


def _pumps(session: Session, station_id: uuid.UUID) -> list[Pump]:
    return list(
        session.exec(select(Pump).where(Pump.station_id == station_id).order_by(Pump.code)).all()
    )


def _tank(session: Session, user: User, tank_id: uuid.UUID) -> Tank:
    tank = session.get(Tank, tank_id)
    if tank is None or tank.station_id != user.station_id:
        raise AppError("TANK_NOT_FOUND", "تعذر العثور على الخزان.", 404)
    return tank


def _pump(session: Session, user: User, pump_id: uuid.UUID) -> Pump:
    pump = session.get(Pump, pump_id)
    if pump is None or pump.station_id != user.station_id:
        raise AppError("PUMP_NOT_FOUND", "تعذر العثور على المضخة.", 404)
    return pump


def _product(session: Session, user: User, product_id: str) -> FuelProduct:
    try:
        parsed = uuid.UUID(product_id)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "المنتج غير صالح.", 422) from exc
    product = session.get(FuelProduct, parsed)
    if product is None or product.station_id != user.station_id:
        raise AppError("PRODUCT_NOT_FOUND", "تعذر العثور على المنتج.", 404)
    return product


def _next_tank_code(session: Session, station_id: uuid.UUID, product_code: str) -> str:
    prefix = "TD" if product_code == "DIESEL" else "T"
    rows = session.exec(select(Tank.code).where(Tank.station_id == station_id)).all()
    numbers = []
    for code in rows:
        if isinstance(code, str) and code.startswith(prefix + "-"):
            try:
                numbers.append(int(code.split("-", 1)[1]))
            except ValueError:
                continue
    return f"{prefix}-{(max(numbers) if numbers else 0) + 1:02d}"


def _positive(raw: str, message: str) -> Decimal:
    try:
        value = as_decimal(raw)
    except Exception as exc:
        raise AppError("VALIDATION_ERROR", message, 422) from exc
    if value <= 0:
        raise AppError("VALIDATION_ERROR", message, 422)
    return value


def _delta(raw: str) -> Decimal:
    try:
        value = as_decimal(raw)
    except Exception as exc:
        raise AppError("VALIDATION_ERROR", "كمية التسوية غير صالحة.", 422) from exc
    if value == 0:
        raise AppError("VALIDATION_ERROR", "أدخل كمية مختلفة عن الصفر.", 422)
    return value


def _meter(raw: str) -> Decimal:
    try:
        value = as_decimal(raw)
    except Exception as exc:
        raise AppError("VALIDATION_ERROR", "قراءة العداد غير صالحة.", 422) from exc
    if value < 0:
        raise AppError("VALIDATION_ERROR", "قراءة العداد لا تكون سالبة.", 422)
    return value


def _parse_date(value: str | None):
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "صيغة التاريخ يجب أن تكون سنة-شهر-يوم.", 422) from exc


def _iso(moment: datetime | None) -> str | None:
    if moment is None:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).isoformat()
