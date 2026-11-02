import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

from sqlmodel import Session, select

from alerts import note_tank_crossing
from assets.levels import as_decimal, format_qty, station_timezone
from assets.models import InventoryMovement, Tank
from errors import AppError
from stations.models import FuelProduct, Station
from supply.models import Supplier, SupplyOrder
from users.audit import write_audit
from users.models import User
from utils import as_utc, utcnow

_WEEKDAYS = ["الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت", "الأحد"]
_STATUS = {
    "pending": "قيد الانتظار",
    "received": "تم الاستلام",
    "cancelled": "ملغي",
}


def list_suppliers(session: Session, user: User) -> list[dict]:
    rows = session.exec(
        select(Supplier).where(Supplier.station_id == user.station_id).order_by(Supplier.name)
    ).all()
    return [_supplier_public(session, row, recent=False) for row in rows]


def create_supplier(session: Session, user: User, payload) -> dict:
    name = payload.name.strip()
    if not name:
        raise AppError("VALIDATION_ERROR", "اسم المورد مطلوب.", 422)
    duplicate = session.exec(
        select(Supplier).where(Supplier.station_id == user.station_id, Supplier.name == name)
    ).first()
    if duplicate is not None:
        raise AppError("DUPLICATE_SUPPLIER", "هذا المورد مسجّل بالفعل.", 409)
    row = Supplier(
        station_id=user.station_id,
        name=name,
        headquarters=(payload.headquarters or "").strip(),
        contact_name=(payload.contact_name or "").strip(),
        phone=(payload.phone or "").strip(),
        max_daily_liters=_liters(payload.max_daily_liters, "سعة التوريد"),
        is_active=True,
    )
    if row.max_daily_liters <= 0:
        raise AppError("VALIDATION_ERROR", "سعة التوريد اليومية يجب أن تكون أكبر من صفر.", 422)
    session.add(row)
    session.commit()
    session.refresh(row)
    return _supplier_public(session, row, recent=False)


def update_supplier(session: Session, user: User, supplier_id: str, payload) -> dict:
    row = _supplier(session, user, supplier_id)
    data = payload.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        name = data["name"].strip()
        if not name:
            raise AppError("VALIDATION_ERROR", "اسم المورد مطلوب.", 422)
        row.name = name
    if "headquarters" in data and data["headquarters"] is not None:
        row.headquarters = data["headquarters"].strip()
    if "contact_name" in data and data["contact_name"] is not None:
        row.contact_name = data["contact_name"].strip()
    if "phone" in data and data["phone"] is not None:
        row.phone = data["phone"].strip()
    if "max_daily_liters" in data and data["max_daily_liters"] is not None:
        daily = _liters(data["max_daily_liters"], "سعة التوريد")
        if daily <= 0:
            raise AppError("VALIDATION_ERROR", "سعة التوريد اليومية يجب أن تكون أكبر من صفر.", 422)
        row.max_daily_liters = daily
    if "is_active" in data and data["is_active"] is not None:
        row.is_active = data["is_active"]
    row.updated_at = utcnow()
    session.add(row)
    session.commit()
    session.refresh(row)
    return _supplier_public(session, row, recent=True)


def get_supplier(session: Session, user: User, supplier_id: str) -> dict:
    return _supplier_public(session, _supplier(session, user, supplier_id), recent=True)


def summary(session: Session, user: User) -> dict:
    tz = _tz(session, user)
    today = datetime.now(tz).date()
    orders = _orders(session, user.station_id)
    delivered = Decimal("0.000")
    active = 0
    pending = 0
    for order in orders:
        created = as_utc(order.created_at)
        created_day = created.astimezone(tz).date() if created else None
        in_month = created_day is not None and created_day.year == today.year and created_day.month == today.month
        if in_month and order.status != "cancelled":
            active += 1
        if in_month and order.status == "pending":
            pending += 1
        if order.status == "received" and order.received_at is not None and order.received_liters is not None:
            received_day = as_utc(order.received_at).astimezone(tz).date()
            if received_day.year == today.year and received_day.month == today.month:
                delivered += as_decimal(order.received_liters)
    suppliers = session.exec(select(Supplier).where(Supplier.station_id == user.station_id)).all()
    return {
        "delivered_liters": format_qty(delivered),
        "active_orders": active,
        "pending_orders": pending,
        "active_suppliers": sum(1 for item in suppliers if item.is_active),
        "week": _week(orders, today, tz),
    }


def list_orders(
    session: Session,
    user: User,
    page: int | None = None,
    page_size: int | None = None,
) -> dict:
    from core.pagination import page_bounds, slice_page

    rows = _orders(session, user.station_id)
    rows.sort(key=lambda item: as_utc(item.created_at) or utcnow(), reverse=True)
    items = [_order_public(session, row) for row in rows]
    safe_page, safe_size = page_bounds(page, page_size, default_size=20, max_size=100)
    sliced, total = slice_page(items, safe_page, safe_size)
    return {"items": sliced, "total": total, "page": safe_page, "page_size": safe_size}


def create_order(session: Session, user: User, payload) -> dict:
    supplier = _supplier(session, user, payload.supplier_id)
    if not supplier.is_active:
        raise AppError("SUPPLIER_INACTIVE", "هذا المورد غير نشط.", 409)
    tank = _tank(session, user, payload.tank_id)
    if not tank.is_active:
        raise AppError("TANK_INACTIVE", "الخزان غير نشط.", 409)
    product = _product(session, user, payload.product_id)
    if tank.product_id != product.id:
        raise AppError("PRODUCT_MISMATCH", "الخزان لا يطابق نوع الوقود المختار.", 409)
    liters = _liters(payload.ordered_liters, "الكمية")
    if liters <= 0:
        raise AppError("VALIDATION_ERROR", "الكمية المطلوبة يجب أن تكون أكبر من صفر.", 422)
    if liters > as_decimal(supplier.max_daily_liters):
        raise AppError("OVER_DAILY_CAP", "الكمية تتجاوز سعة التوريد اليومية لهذا المورد.", 422)
    code = _next_code(session, user.station_id)
    order = SupplyOrder(
        station_id=user.station_id,
        supplier_id=supplier.id,
        tank_id=tank.id,
        product_id=product.id,
        code=code,
        ordered_liters=liters,
        status="pending",
        expected_on=_parse_date(payload.expected_on),
        notes=(payload.notes or "").strip() or None,
        created_by=user.id,
    )
    session.add(order)
    write_audit(
        session,
        actor_id=user.id,
        action="supply_order_created",
        entity="supply_order",
        entity_id=code,
        detail={"tank_id": str(tank.id), "ordered_liters": format_qty(liters)},
    )
    session.commit()
    session.refresh(order)
    return _order_public(session, order)


def receive_order(session: Session, user: User, order_id: str, payload) -> dict:
    order = _order(session, user, order_id)
    if order.status != "pending":
        raise AppError("ORDER_CLOSED", "لا يمكن استلام طلب ليس قيد الانتظار.", 409)
    raw = payload.received_liters if payload is not None else None
    liters = as_decimal(order.ordered_liters) if not raw else _liters(raw, "الكمية المستلمة")
    if liters <= 0:
        raise AppError("VALIDATION_ERROR", "الكمية المستلمة يجب أن تكون أكبر من صفر.", 422)
    tank = _lock_tank(session, order.tank_id)
    if tank.product_id != order.product_id:
        raise AppError("PRODUCT_MISMATCH", "الخزان لا يطابق نوع الوقود في الطلب.", 409)
    before = as_decimal(tank.current_liters)
    balance = before + liters
    if balance > as_decimal(tank.capacity_liters):
        raise AppError(
            "CAPACITY_EXCEEDED",
            "الكمية تتجاوز السعة المتبقية في الخزان. الطلب يبقى قيد الانتظار.",
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
            movement_type="supply_receipt",
            liters_delta=liters,
            balance_after=balance,
            source_type="order",
            source_id=str(order.id),
            note=order.code,
            created_by=user.id,
        )
    )
    order.status = "received"
    order.received_liters = liters
    order.received_at = utcnow()
    order.received_by = user.id
    order.updated_at = utcnow()
    session.add(order)
    write_audit(
        session,
        actor_id=user.id,
        action="supply_order_received",
        entity="supply_order",
        entity_id=str(order.id),
        detail={"received_liters": format_qty(liters), "balance_after": format_qty(balance)},
    )
    session.commit()
    session.refresh(order)
    return _order_public(session, order)


def cancel_order(session: Session, user: User, order_id: str) -> dict:
    order = _order(session, user, order_id)
    if order.status == "received":
        raise AppError("ORDER_CLOSED", "لا يمكن إلغاء طلب تم استلامه.", 409)
    if order.status == "cancelled":
        raise AppError("ORDER_CLOSED", "هذا الطلب ملغى بالفعل.", 409)
    order.status = "cancelled"
    order.cancelled_at = utcnow()
    order.updated_at = utcnow()
    session.add(order)
    write_audit(
        session,
        actor_id=user.id,
        action="supply_order_cancelled",
        entity="supply_order",
        entity_id=str(order.id),
        detail=None,
    )
    session.commit()
    session.refresh(order)
    return _order_public(session, order)


def _week(orders: list[SupplyOrder], today, tz) -> list[dict]:
    offset = (today.weekday() - 5) % 7
    start = today - timedelta(days=offset)
    days = []
    for index in range(7):
        day = start + timedelta(days=index)
        total = Decimal("0.000")
        for order in orders:
            if order.status != "received" or order.received_at is None or order.received_liters is None:
                continue
            if as_utc(order.received_at).astimezone(tz).date() == day:
                total += as_decimal(order.received_liters)
        days.append({"date": day.isoformat(), "label": _WEEKDAYS[day.weekday()], "liters": format_qty(total)})
    return days


def save_supplier_logo(session: Session, user: User, supplier_id: str, upload) -> dict:
    from stations.services import store_image

    row = _supplier(session, user, supplier_id)
    row.logo_url = store_image(upload, f"supplier-{row.id}")
    row.updated_at = utcnow()
    session.add(row)
    session.commit()
    session.refresh(row)
    return _supplier_public(session, row, recent=True)


def _supplier_public(session: Session, row: Supplier, *, recent: bool) -> dict:
    body = {
        "id": str(row.id),
        "name": row.name,
        "headquarters": row.headquarters,
        "contact_name": row.contact_name,
        "phone": row.phone,
        "max_daily_liters": format_qty(row.max_daily_liters),
        "is_active": row.is_active,
        "logo_url": row.logo_url,
        "reliability": _reliability(session, row),
    }
    if recent:
        orders = session.exec(
            select(SupplyOrder)
            .where(SupplyOrder.supplier_id == row.id)
            .order_by(SupplyOrder.created_at.desc())
        ).all()
        body["recent_orders"] = [_order_public(session, item) for item in orders[:5]]
    return body


def _reliability(session: Session, supplier: Supplier) -> int | None:
    cutoff = utcnow() - timedelta(days=90)
    rows = session.exec(select(SupplyOrder).where(SupplyOrder.supplier_id == supplier.id)).all()
    received = 0
    cancelled = 0
    for order in rows:
        if order.status == "received" and order.received_at is not None and as_utc(order.received_at) >= cutoff:
            received += 1
        elif order.status == "cancelled" and order.cancelled_at is not None and as_utc(order.cancelled_at) >= cutoff:
            cancelled += 1
    total = received + cancelled
    if total == 0:
        return None
    ratio = (Decimal(received) / Decimal(total)) * Decimal(100)
    return int(ratio.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _order_public(session: Session, order: SupplyOrder) -> dict:
    supplier = session.get(Supplier, order.supplier_id)
    tank = session.get(Tank, order.tank_id)
    product = session.get(FuelProduct, order.product_id)
    actor = session.get(User, order.received_by) if order.received_by else None
    return {
        "id": str(order.id),
        "code": order.code,
        "supplier_id": str(order.supplier_id),
        "supplier_name": supplier.name if supplier else "",
        "tank_id": str(order.tank_id),
        "tank_name": tank.name if tank else "",
        "tank_code": tank.code if tank else "",
        "product_id": str(order.product_id),
        "product_name": product.name_ar if product else "",
        "ordered_liters": format_qty(order.ordered_liters),
        "received_liters": format_qty(order.received_liters) if order.received_liters is not None else None,
        "status": order.status,
        "status_label": _STATUS.get(order.status, order.status),
        "expected_on": order.expected_on.isoformat(),
        "notes": order.notes,
        "received_at": _iso(as_utc(order.received_at)),
        "received_by_name": actor.full_name if actor else None,
    }


def _orders(session: Session, station_id: uuid.UUID) -> list[SupplyOrder]:
    return session.exec(select(SupplyOrder).where(SupplyOrder.station_id == station_id)).all()


def _next_code(session: Session, station_id: uuid.UUID) -> str:
    count = len(_orders(session, station_id))
    return f"ORD-{count + 1:04d}"


def _supplier(session: Session, user: User, raw: str) -> Supplier:
    row = session.get(Supplier, _uuid(raw, "المورد غير معروف."))
    if row is None or row.station_id != user.station_id:
        raise AppError("SUPPLIER_NOT_FOUND", "تعذر العثور على المورد.", 404)
    return row


def _order(session: Session, user: User, raw: str) -> SupplyOrder:
    row = session.get(SupplyOrder, _uuid(raw, "الطلب غير معروف."))
    if row is None or row.station_id != user.station_id:
        raise AppError("ORDER_NOT_FOUND", "تعذر العثور على الطلب.", 404)
    return row


def _tank(session: Session, user: User, raw: str) -> Tank:
    row = session.get(Tank, _uuid(raw, "الخزان غير معروف."))
    if row is None or row.station_id != user.station_id:
        raise AppError("TANK_NOT_FOUND", "تعذر العثور على الخزان.", 404)
    return row


def _product(session: Session, user: User, raw: str) -> FuelProduct:
    row = session.get(FuelProduct, _uuid(raw, "نوع الوقود غير معروف."))
    if row is None or row.station_id != user.station_id:
        raise AppError("PRODUCT_NOT_FOUND", "تعذر العثور على نوع الوقود.", 404)
    return row


def _lock_tank(session: Session, tank_id: uuid.UUID) -> Tank:
    statement = select(Tank).where(Tank.id == tank_id)
    bind = session.get_bind()
    if bind is not None and bind.dialect.name != "sqlite":
        statement = statement.with_for_update()
    return session.exec(statement).one()


def _liters(raw: str, label: str) -> Decimal:
    try:
        return as_decimal(str(raw).strip())
    except Exception as exc:
        raise AppError("VALIDATION_ERROR", f"{label} غير صالحة.", 422) from exc


def _parse_date(raw: str):
    try:
        return datetime.strptime(raw, "%Y-%m-%d").date()
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "صيغة التاريخ يجب أن تكون سنة-شهر-يوم.", 422) from exc


def _uuid(raw: str, message: str) -> uuid.UUID:
    try:
        return uuid.UUID(raw)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", message, 422) from exc


def _tz(session: Session, user: User):
    station = session.get(Station, user.station_id)
    return station_timezone(station.timezone if station else "Africa/Tripoli")


def _iso(moment: datetime | None) -> str | None:
    if moment is None:
        return None
    return moment.astimezone(timezone.utc).isoformat()
