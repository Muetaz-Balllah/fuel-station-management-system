"""Populate realistic historical operations for local testing.

Run from the backend folder:

    python -m scripts.seed_realistic

Safe to re-run. Existing approved shifts and supply orders are left in place.
"""

from __future__ import annotations

import sys
import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal

from sqlmodel import Session, select

from assets.levels import station_timezone
from assets.models import Nozzle, Pump, Tank
from attendance.models import Attendance, ShiftSession
from shifts.models import ShiftDuty
from attendance.routes import AttendanceCreate, SessionCreate
from attendance.services import open_session, register_attendance
from core.security import hash_password
from db import engine
from enums import RoleCode
from errors import AppError
from shifts.reconciliation import q_liters, q_money
from shifts.routes import CloseDuty, CloseLine, OpenDuty, OpenNozzle
from shifts.services import approve_duty, close_duty, open_duty
from stations.models import FuelPrice, FuelProduct, ShiftTemplate, Station
from supply.models import Supplier, SupplyOrder
from users.models import User
from utils import utcnow

_WORKERS = (
    ("ali.tumi", "EMP-2101", "علي التومي", "مشغل مضخة"),
    ("salem.werf", "EMP-2102", "سالم الورفلي", "مشغل مضخة"),
    ("noura.sharef", "EMP-2103", "نورة الشريف", "مشغلة وردية"),
)


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    with Session(engine) as session:
        station = session.exec(select(Station)).first()
        manager = session.exec(select(User).where(User.username == "manager")).first()
        operator = session.exec(select(User).where(User.username == "operator")).first()
        if station is None or manager is None or operator is None:
            print("Run the API once so users exist, then run this script.")
            return
        workers = _ensure_workers(session, station)
        operators = [operator, *workers]
        _seed_supply_orders(session, station, manager)
        session.commit()
        _seed_history(session, station, manager, operators)
        print("Realistic seed complete.")
        print("Operator logins (password Operator@12345): operator, ali.tumi, salem.werf, noura.sharef")


def _ensure_workers(session: Session, station: Station) -> list[User]:
    role = RoleCode.OPERATOR
    people: list[User] = []
    for username, code, name, title in _WORKERS:
        found = session.exec(
            select(User).where(User.station_id == station.id, User.username == username)
        ).first()
        if found is None:
            found = User(
                station_id=station.id,
                role=role,
                employee_code=code,
                full_name=name,
                username=username,
                email=f"{username}@station.local",
                password_hash=hash_password("Operator@12345"),
                job_title=title,
                is_active=True,
            )
            session.add(found)
            session.flush()
            print(f"Added operator {name} ({username}).")
        people.append(found)
    return people


def _seed_history(session: Session, station: Station, manager: User, operators: list[User]) -> None:
    tz = station_timezone(station.timezone)
    today = datetime.now(tz).date()
    templates = list(
        session.exec(
            select(ShiftTemplate).where(ShiftTemplate.station_id == station.id).order_by(ShiftTemplate.sort_order)
        ).all()
    )
    if not templates:
        print("Shift templates missing.")
        return
    nozzles = _ready_nozzles(session, station.id)
    if not nozzles:
        print("Need at least one ready nozzle with a price and tank stock.")
        return
    for offset in range(0, 14):
        day = today - timedelta(days=offset)
        chosen = templates[:1] if offset == 0 else templates
        for template in chosen:
            try:
                _seed_window(session, station, manager, operators, nozzles, template, day, offset, today)
            except AppError as exc:
                session.rollback()
                print(f"Skipped {day.isoformat()} {template.name_ar}: {exc.message}")


def _seed_window(
    session: Session,
    station: Station,
    manager: User,
    operators: list[User],
    nozzles: list[tuple[Nozzle, Pump, Tank, FuelPrice]],
    template: ShiftTemplate,
    day: date,
    offset: int,
    today: date,
) -> None:
    existing = session.exec(
        select(ShiftSession).where(
            ShiftSession.station_id == station.id,
            ShiftSession.template_id == template.id,
            ShiftSession.business_date == day,
        )
    ).first()
    if existing is not None:
        approved = session.exec(
            select(ShiftDuty).where(ShiftDuty.session_id == existing.id, ShiftDuty.status == "approved")
        ).first()
        if approved is not None or existing.status == "approved":
            return
    opened = open_session(
        session,
        manager,
        SessionCreate(template_id=str(template.id), business_date=day.isoformat(), supervisor_id=str(manager.id)),
    )
    free = _free_nozzles(session, nozzles)
    if not free:
        print(f"No free nozzle on {day.isoformat()} {template.name_ar}.")
        return
    planted = 0
    for index, (person, nozzle, _pump, tank, price) in enumerate(_pairs(operators, free, offset)):
        try:
            if _plant_duty(session, manager, person, nozzle, tank, price, opened["id"], template, day, offset, index):
                planted += 1
        except AppError as exc:
            session.rollback()
            print(f"Skipped {day.isoformat()} {template.name_ar} / {person.username}: {exc.message}")
    if offset % 3 == 0 and len(operators) > 2:
        spare = operators[-1]
        try:
            register_attendance(
                session,
                manager,
                uuid.UUID(opened["id"]),
                AttendanceCreate(
                    user_id=str(spare.id),
                    nozzle_ids=[],
                    status="absent",
                    note="غياب بعذر مرضي",
                ),
            )
        except AppError:
            session.rollback()
    if planted:
        print(f"Seeded {planted} approved duty(ies) on {day.isoformat()} ({template.name_ar}).")


def _plant_duty(session, manager, person, nozzle, tank, price, session_id, template, day, offset, index) -> bool:
    already = session.exec(
        select(Attendance).where(
            Attendance.session_id == uuid.UUID(session_id),
            Attendance.user_id == person.id,
        )
    ).first()
    if already is not None:
        return False
    session.refresh(nozzle)
    session.refresh(tank)
    desired = Decimal(str(180 + ((offset * 37 + index * 90) % 520)))
    if template.starts_at.hour >= 12:
        desired += Decimal("110")
    room = q_liters(tank.current_liters) - Decimal("80")
    liters = q_liters(min(desired, room))
    if liters < Decimal("8"):
        return False
    opening = q_liters(nozzle.current_meter)
    closing = q_liters(opening + liters)
    check_in = "08:22" if index == 1 and offset % 2 == 0 else "07:52"
    if template.starts_at.hour >= 12:
        check_in = "16:18" if index == 1 and offset % 2 == 0 else "15:55"
    register_attendance(
        session,
        manager,
        uuid.UUID(session_id),
        AttendanceCreate(user_id=str(person.id), nozzle_ids=[str(nozzle.id)], check_in_at=check_in),
    )
    duty = open_duty(
        session,
        person,
        OpenDuty(
            session_id=session_id,
            nozzles=[OpenNozzle(nozzle_id=str(nozzle.id), opening_meter=f"{opening:.3f}")],
        ),
        (),
    )
    expected = q_money(liters * q_liters(price.price_per_liter))
    pattern = (offset + index) % 5
    if pattern == 0:
        cash = q_money(expected - Decimal("2.50"))
    elif pattern == 1:
        cash = q_money(expected + Decimal("1.25"))
    else:
        cash = expected
    if cash < 0:
        cash = expected
    close_duty(
        session,
        person,
        duty["id"],
        CloseDuty(
            cash_handed=f"{cash:.2f}",
            lines=[CloseLine(nozzle_id=str(nozzle.id), closing_meter=f"{closing:.3f}")],
        ),
        (),
    )
    approve_duty(session, manager, duty["id"])
    return True


def _free_nozzles(session: Session, nozzles):
    from shifts.services import _ensure_free

    free = []
    for item in nozzles:
        try:
            _ensure_free(session, item[0].id)
        except AppError:
            continue
        free.append(item)
    return free


def _pairs(operators: list[User], nozzles, offset: int):
    if not operators or not nozzles:
        return []
    count = 1 if len(nozzles) == 1 or len(operators) == 1 else 2
    rows = []
    for index in range(count):
        person = operators[(offset + index) % max(1, len(operators) - (1 if len(operators) > 2 else 0))]
        nozzle, pump, tank, price = nozzles[(offset + index) % len(nozzles)]
        rows.append((person, nozzle, pump, tank, price))
    return rows


def _seed_supply_orders(session: Session, station: Station, manager: User) -> None:
    suppliers = list(session.exec(select(Supplier).where(Supplier.station_id == station.id)).all())
    tanks = list(
        session.exec(select(Tank).where(Tank.station_id == station.id, Tank.is_active == True)).all()  # noqa: E712
    )
    if not suppliers or not tanks:
        return
    today = date.today()
    specs = (
        ("HIST-1001", 0, 12, "received", "48000.000", "توريد بنزين أسبوعي"),
        ("HIST-1002", 1, 8, "received", "22000.000", "تعبئة ديزل"),
        ("HIST-1003", 2, 5, "cancelled", "15000.000", "أُلغي بعد تأخير الناقلة"),
        ("HIST-1004", 0, 3, "received", "31000.000", "توريد طارئ"),
        ("HIST-1005", 1, -2, "pending", "40000.000", "طلب التوريد القادم"),
        ("HIST-1006", 2, -4, "pending", "18000.000", "طلب مسائي"),
        ("HIST-1007", 0, 1, "received", "12500.000", "دفعة جزئية مستلمة"),
    )
    for code, supplier_index, day_offset, status, liters, notes in specs:
        if session.exec(select(SupplyOrder).where(SupplyOrder.station_id == station.id, SupplyOrder.code == code)).first():
            continue
        supplier = suppliers[supplier_index % len(suppliers)]
        tank = tanks[supplier_index % len(tanks)]
        moment = utcnow() - timedelta(days=max(day_offset, 0))
        if day_offset < 0:
            moment = utcnow() - timedelta(days=1)
        session.add(
            SupplyOrder(
                station_id=station.id,
                supplier_id=supplier.id,
                tank_id=tank.id,
                product_id=tank.product_id,
                code=code,
                ordered_liters=Decimal(liters),
                received_liters=Decimal(liters) if status == "received" else None,
                status=status,
                expected_on=today - timedelta(days=day_offset),
                notes=notes,
                received_at=moment if status == "received" else None,
                received_by=manager.id if status == "received" else None,
                cancelled_at=moment if status == "cancelled" else None,
                created_by=manager.id,
                created_at=moment,
                updated_at=moment,
            )
        )
        print(f"Supply order {code} ({status}).")


def _ready_nozzles(session: Session, station_id: uuid.UUID):
    rows = []
    nozzles = session.exec(select(Nozzle).where(Nozzle.station_id == station_id, Nozzle.status == "ready")).all()
    for nozzle in nozzles:
        pump = session.get(Pump, nozzle.pump_id)
        tank = session.get(Tank, pump.tank_id) if pump else None
        if pump is None or tank is None or pump.status != "active" or not tank.is_active:
            continue
        price = session.exec(
            select(FuelPrice).where(FuelPrice.product_id == tank.product_id).order_by(FuelPrice.created_at.desc())
        ).first()
        if price is None or q_liters(tank.current_liters) < Decimal("200"):
            continue
        rows.append((nozzle, pump, tank, price))
    return rows


if __name__ == "__main__":
    main()
