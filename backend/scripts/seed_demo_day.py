"""One small approved duty for today.

Run from the backend folder:

    python -m scripts.seed_demo_day

The script does nothing when today's morning session already exists, or when a
Brega order is still pending. It sells 10 liters so the demo tanks stay usable.
It is not part of startup and the tests never call it.
"""

from datetime import datetime
from decimal import Decimal

from sqlmodel import Session, select

import uuid

from assets.levels import station_timezone
from assets.models import Nozzle, Pump, Tank
from attendance.models import ShiftSession
from attendance.routes import AttendanceCreate, SessionCreate
from attendance.services import open_session, register_attendance
from db import engine
from shifts.reconciliation import q_liters, q_money
from shifts.routes import CloseDuty, CloseLine, OpenDuty, OpenNozzle
from shifts.services import approve_duty, close_duty, open_duty
from stations.models import FuelPrice, FuelProduct, ShiftTemplate, Station
from supply.models import Supplier, SupplyOrder
from users.models import User


def main() -> None:
    with Session(engine) as session:
        station = session.exec(select(Station)).first()
        manager = session.exec(select(User).where(User.username == "manager")).first()
        operator = session.exec(select(User).where(User.username == "operator")).first()
        if station is None or manager is None or operator is None:
            print("Sign in once so the station and users exist, then run this again.")
            return
        today = datetime.now(station_timezone(station.timezone)).date()
        morning = session.exec(select(ShiftTemplate).where(ShiftTemplate.name_ar == "صباحية")).first()
        if morning is None:
            print("The morning template is missing.")
            return
        existing = session.exec(
            select(ShiftSession).where(
                ShiftSession.station_id == station.id,
                ShiftSession.template_id == morning.id,
                ShiftSession.business_date == today,
            )
        ).first()
        brega = session.exec(select(Supplier).where(Supplier.name.contains("البريقة"))).first()
        pending = None
        if brega is not None:
            pending = session.exec(
                select(SupplyOrder).where(SupplyOrder.supplier_id == brega.id, SupplyOrder.status == "pending")
            ).first()
        if existing is not None or pending is not None:
            print("Today already has a morning shift or a pending Brega order. Nothing was added.")
            return
        product = session.exec(select(FuelProduct).where(FuelProduct.code == "G95")).first()
        if product is None:
            print("Gasoline 95 is missing.")
            return
        price = session.exec(
            select(FuelPrice).where(FuelPrice.product_id == product.id).order_by(FuelPrice.created_at.desc())
        ).first()
        if price is None:
            print("Gasoline 95 has no current price.")
            return
        nozzle = _nozzle(session, station.id, product.id)
        if nozzle is None:
            print("No ready gasoline nozzle with fuel in the tank.")
            return
        opened = open_session(
            session,
            manager,
            SessionCreate(template_id=str(morning.id), business_date=today.isoformat(), supervisor_id=str(manager.id)),
        )
        register_attendance(
            session,
            manager,
            _uuid(opened["id"]),
            AttendanceCreate(user_id=str(operator.id), nozzle_ids=[str(nozzle.id)], check_in_at="08:00"),
        )
        session.refresh(nozzle)
        opening = q_liters(nozzle.current_meter)
        closing = q_liters(opening + Decimal("10.000"))
        duty = open_duty(
            session,
            operator,
            OpenDuty(session_id=opened["id"], nozzles=[OpenNozzle(nozzle_id=str(nozzle.id), opening_meter=f"{opening:.3f}")]),
            (),
        )
        cash = q_money(Decimal("10.000") * q_liters(price.price_per_liter))
        close_duty(
            session,
            operator,
            duty["id"],
            CloseDuty(
                cash_handed=f"{cash:.2f}",
                lines=[CloseLine(nozzle_id=str(nozzle.id), closing_meter=f"{closing:.3f}")],
            ),
            (),
        )
        approve_duty(session, manager, duty["id"])
        print(f"Approved a 10 liter gasoline sale on {today.isoformat()}.")


def _nozzle(session: Session, station_id, product_id) -> Nozzle | None:
    nozzles = session.exec(select(Nozzle).where(Nozzle.station_id == station_id, Nozzle.status == "ready")).all()
    for nozzle in nozzles:
        pump = session.get(Pump, nozzle.pump_id)
        tank = session.get(Tank, pump.tank_id) if pump is not None else None
        if pump is None or tank is None or pump.status != "active" or not tank.is_active:
            continue
        if tank.product_id == product_id and q_liters(tank.current_liters) >= Decimal("10"):
            return nozzle
    return None


def _uuid(raw: str) -> uuid.UUID:
    return uuid.UUID(raw)


if __name__ == "__main__":
    main()
