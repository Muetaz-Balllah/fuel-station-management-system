"""Station alerts. Callers commit. This module only adds rows."""

import uuid
from datetime import timedelta

from sqlmodel import Session, select

from assets.levels import percent_of
from assets.models import Tank
from shifts.models import Notification
from stations.models import FuelProduct, Station
from supply.models import SupplyOrder
from utils import as_utc, utcnow


def note_tank_crossing(session: Session, tank: Tank, before, after) -> None:
    before_percent = percent_of(before, tank.capacity_liters)
    after_percent = percent_of(after, tank.capacity_liters)
    if after_percent > tank.critical_percent or before_percent <= tank.critical_percent:
        return
    product = session.get(FuelProduct, tank.product_id)
    name = product.name_ar if product else tank.name
    _once(
        session,
        station_id=tank.station_id,
        kind="tank_critical",
        entity_type="tank",
        entity_id=str(tank.id),
        title="تنبيه الخزانات",
        body=f"{name}: المستوى حرج، أقل من {tank.critical_percent}%.",
    )


def note_license(session: Session, station: Station) -> None:
    today = utcnow().date()
    remaining = (station.license_expires_on - today).days
    if remaining > 30:
        return
    when = "منتهٍ" if remaining < 0 else f"خلال {remaining} يوماً"
    _once(
        session,
        station_id=station.id,
        kind="license_due",
        entity_type="station",
        entity_id=station.license_expires_on.isoformat(),
        title="تجديد الترخيص",
        body=f"ترخيص المحطة {station.license_number} ينتهي {when}.",
    )


def note_stale_orders(session: Session, station_id: uuid.UUID) -> None:
    cutoff = utcnow() - timedelta(days=3)
    orders = session.exec(
        select(SupplyOrder).where(
            SupplyOrder.station_id == station_id,
            SupplyOrder.status == "pending",
        )
    ).all()
    for order in orders:
        created = as_utc(order.created_at)
        if created is None or created > cutoff:
            continue
        _once(
            session,
            station_id=station_id,
            kind="order_stale",
            entity_type="supply_order",
            entity_id=str(order.id),
            title="طلب توريد متأخر",
            body=f"الطلب {order.code} ما زال قيد الانتظار منذ أكثر من 3 أيام.",
        )


def list_notifications(session: Session, station_id: uuid.UUID) -> list[dict]:
    rows = session.exec(
        select(Notification)
        .where(Notification.station_id == station_id)
        .order_by(Notification.created_at.desc())
    ).all()
    return [_public(row) for row in rows]


def mark_read(session: Session, station_id: uuid.UUID, notification_id: str) -> dict:
    try:
        parsed = uuid.UUID(notification_id)
    except ValueError as exc:
        from errors import AppError

        raise AppError("VALIDATION_ERROR", "التنبيه غير معروف.", 422) from exc
    row = session.get(Notification, parsed)
    if row is None or row.station_id != station_id:
        from errors import AppError

        raise AppError("NOTIFICATION_NOT_FOUND", "تعذر العثور على التنبيه.", 404)
    if row.read_at is None:
        row.read_at = utcnow()
        session.add(row)
        session.commit()
        session.refresh(row)
    return _public(row)


def _once(
    session: Session,
    *,
    station_id: uuid.UUID,
    kind: str,
    entity_type: str,
    entity_id: str,
    title: str,
    body: str,
) -> None:
    rows = session.exec(
        select(Notification).where(
            Notification.station_id == station_id,
            Notification.kind == kind,
            Notification.entity_id == entity_id,
        )
    ).all()
    if any(row.read_at is None for row in rows):
        return
    if kind in {"license_due", "order_stale"} and rows:
        return
    session.add(
        Notification(
            station_id=station_id,
            user_id=None,
            kind=kind,
            title=title,
            body=body,
            entity_type=entity_type,
            entity_id=entity_id,
        )
    )


def _public(row: Notification) -> dict:
    created = as_utc(row.created_at)
    return {
        "id": str(row.id),
        "kind": row.kind,
        "title": row.title,
        "body": row.body,
        "entity_type": row.entity_type,
        "entity_id": row.entity_id,
        "read_at": as_utc(row.read_at).isoformat() if row.read_at else None,
        "created_at": created.isoformat() if created else None,
    }
