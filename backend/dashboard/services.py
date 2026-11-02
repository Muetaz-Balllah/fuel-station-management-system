import csv
import io
from datetime import datetime, timedelta
from decimal import Decimal

from sqlmodel import Session, select

from alerts import list_notifications, mark_read, note_license, note_stale_orders
from assets.levels import percent_of, station_timezone
from assets.models import Tank
from attendance.models import Attendance, ShiftSession
from shifts.reconciliation import format_liters, format_money, q_liters, rollup, submitted_liters
from shifts.services import duty_entries, shift_log
from stations.models import FuelProduct, ShiftTemplate, Station
from users.models import User
from utils import utcnow

_WEEKDAYS = ["الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت", "الأحد"]


def dashboard(session: Session, user: User, day: str | None) -> dict:
    station = session.get(Station, user.station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    business_date = _date(day) if day else datetime.now(tz).date()
    if station is not None:
        note_license(session, station)
    note_stale_orders(session, user.station_id)
    session.commit()
    shifts = session.exec(
        select(ShiftSession).where(
            ShiftSession.station_id == user.station_id,
            ShiftSession.business_date == business_date,
        )
    ).all()
    entries = []
    for shift in shifts:
        entries.extend(duty_entries(session, shift))
    approved = rollup(entries)
    tanks = session.exec(select(Tank).where(Tank.station_id == user.station_id)).all()
    inventory = Decimal("0.000")
    for tank in tanks:
        inventory = q_liters(inventory + q_liters(tank.current_liters))
    staff = _staff(session, user, business_date)
    return {
        "date": business_date.isoformat(),
        "revenue": format_money(approved["revenue"]),
        "liters": format_liters(submitted_liters(entries)),
        "inventory_liters": format_liters(inventory),
        "staff_on_duty": staff,
        "alert": _alert(session, tanks),
        "week": _week(session, user, business_date),
        "tanks": [_tank_row(session, tank) for tank in tanks if tank.is_active],
        "sessions": shift_log(
            session,
            user,
            business_date.isoformat(),
            business_date.isoformat(),
            None,
            page=1,
            page_size=500,
        )["items"],
        "license_expires_on": station.license_expires_on.isoformat() if station else None,
        "license_due": bool(station and (station.license_expires_on - utcnow().date()).days <= 30),
    }


def dashboard_csv(session: Session, user: User, day: str | None) -> str:
    body = dashboard(session, user, day)
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(["الرمز", "الفترة", "المشرف", "اللترات", "الإيراد", "العجز", "الحالة"])
    for row in body["sessions"]:
        writer.writerow(
            [
                row["code"],
                row["window"],
                row["supervisor"],
                row["liters"] or "",
                row["revenue"] or "0.00",
                row["variance_label"] or "",
                row["status_label"],
            ]
        )
    return buffer.getvalue()


def notifications(session: Session, user: User, permissions: tuple[str, ...] = ()) -> list[dict]:
    from enums import PermissionCode

    operator_only = PermissionCode.DASHBOARD_VIEW not in permissions
    return list_notifications(session, user.station_id, user_id=user.id if operator_only else None)


def read_notification(session: Session, user: User, notification_id: str) -> dict:
    return mark_read(session, user.station_id, notification_id)


def _staff(session: Session, user: User, business_date) -> int:
    rows = session.exec(
        select(Attendance)
        .join(ShiftSession, ShiftSession.id == Attendance.session_id)
        .where(
            Attendance.station_id == user.station_id,
            ShiftSession.business_date == business_date,
        )
    ).all()
    return sum(1 for row in rows if row.status in {"present", "late"} and row.check_out_at is None)


def _alert(session: Session, tanks: list[Tank]) -> dict | None:
    worst = None
    worst_percent = None
    for tank in tanks:
        if not tank.is_active:
            continue
        percent = percent_of(tank.current_liters, tank.capacity_liters)
        if percent > tank.critical_percent:
            continue
        if worst_percent is None or percent < worst_percent:
            worst = tank
            worst_percent = percent
    if worst is None or worst_percent is None:
        return None
    product = session.get(FuelProduct, worst.product_id)
    return {
        "tank_id": str(worst.id),
        "tank_name": worst.name,
        "product_name": product.name_ar if product else "",
        "percent": worst_percent,
        "message": f"المستوى حرج: أقل من {worst.critical_percent}%",
    }


def _tank_row(session: Session, tank: Tank) -> dict:
    product = session.get(FuelProduct, tank.product_id)
    return {
        "id": str(tank.id),
        "name": tank.name,
        "product_name": product.name_ar if product else "",
        "percent": percent_of(tank.current_liters, tank.capacity_liters),
        "current_liters": format_liters(tank.current_liters),
        "capacity_liters": format_liters(tank.capacity_liters),
    }


def _week(session: Session, user: User, business_date) -> list[dict]:
    offset = (business_date.weekday() - 5) % 7
    start = business_date - timedelta(days=offset)
    days = []
    for index in range(7):
        day = start + timedelta(days=index)
        shifts = session.exec(
            select(ShiftSession).where(
                ShiftSession.station_id == user.station_id,
                ShiftSession.business_date == day,
            )
        ).all()
        morning: list[dict] = []
        evening: list[dict] = []
        for shift in shifts:
            template = session.get(ShiftTemplate, shift.template_id)
            name = template.name_ar if template else ""
            bucket = morning if "صباح" in name else evening
            bucket.extend(duty_entries(session, shift))
        days.append(
            {
                "date": day.isoformat(),
                "label": _WEEKDAYS[day.weekday()],
                "morning": format_money(rollup(morning)["revenue"]),
                "evening": format_money(rollup(evening)["revenue"]),
            }
        )
    return days


def _date(raw: str):
    from errors import AppError

    try:
        return datetime.strptime(raw, "%Y-%m-%d").date()
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "صيغة التاريخ يجب أن تكون سنة-شهر-يوم.", 422) from exc
