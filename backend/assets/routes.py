import uuid

from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel
from sqlmodel import Session

from assets.services import (
    adjust_tank,
    board,
    create_nozzle,
    create_pump,
    create_tank,
    delete_nozzle,
    delete_pump,
    delete_tank,
    list_events,
    list_pumps,
    list_tanks,
    update_nozzle,
    update_pump,
    update_tank,
)
from core.deps import require_permission
from db import get_session
from users.models import User

router = APIRouter(tags=["assets"])


class TankCreate(BaseModel):
    name: str
    product_id: str
    capacity_liters: str


class TankUpdate(BaseModel):
    name: str | None = None
    critical_percent: int | None = None
    warning_percent: int | None = None
    is_active: bool | None = None


class AdjustmentCreate(BaseModel):
    liters_delta: str
    note: str


class PumpCreate(BaseModel):
    code: str
    tank_id: str


class PumpUpdate(BaseModel):
    status: str


class NozzleCreate(BaseModel):
    code: str
    label: str
    initial_meter: str
    status: str = "ready"


class NozzleUpdate(BaseModel):
    label: str | None = None
    status: str | None = None


@router.get("/tanks")
def read_tanks(
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items = list_tanks(session, user)
    return {"items": items, "total": len(items)}


@router.post("/tanks", status_code=201)
def post_tank(
    payload: TankCreate,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return create_tank(session, user, payload)


@router.patch("/tanks/{tank_id}")
def patch_tank(
    tank_id: uuid.UUID,
    payload: TankUpdate,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return update_tank(session, user, tank_id, payload)


@router.post("/tanks/{tank_id}/adjustments", status_code=201)
def post_adjustment(
    tank_id: uuid.UUID,
    payload: AdjustmentCreate,
    user: User = Depends(require_permission("inventory.adjust")),
    session: Session = Depends(get_session),
) -> dict:
    return adjust_tank(session, user, tank_id, payload)


@router.get("/pumps")
def read_pumps(
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items = list_pumps(session, user)
    return {"items": items, "total": len(items)}


@router.post("/pumps", status_code=201)
def post_pump(
    payload: PumpCreate,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return create_pump(session, user, payload)


@router.patch("/pumps/{pump_id}")
def patch_pump(
    pump_id: uuid.UUID,
    payload: PumpUpdate,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return update_pump(session, user, pump_id, payload)


@router.post("/pumps/{pump_id}/nozzles", status_code=201)
def post_nozzle(
    pump_id: uuid.UUID,
    payload: NozzleCreate,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return create_nozzle(session, user, pump_id, payload)


@router.patch("/nozzles/{nozzle_id}")
def patch_nozzle(
    nozzle_id: uuid.UUID,
    payload: NozzleUpdate,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return update_nozzle(session, user, nozzle_id, payload)


@router.delete("/tanks/{tank_id}", status_code=204)
def remove_tank(
    tank_id: uuid.UUID,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> Response:
    delete_tank(session, user, tank_id)
    return Response(status_code=204)


@router.delete("/pumps/{pump_id}", status_code=204)
def remove_pump(
    pump_id: uuid.UUID,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> Response:
    delete_pump(session, user, pump_id)
    return Response(status_code=204)


@router.delete("/nozzles/{nozzle_id}", status_code=204)
def remove_nozzle(
    nozzle_id: uuid.UUID,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> Response:
    delete_nozzle(session, user, nozzle_id)
    return Response(status_code=204)


@router.get("/assets/board")
def read_board(
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return board(session, user)


@router.get("/inventory/events")
def read_events(
    product_id: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    limit: int = 20,
    offset: int = 0,
    user: User = Depends(require_permission("assets.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items, total = list_events(
        session,
        user,
        product_id=product_id,
        date_from=date_from,
        date_to=date_to,
        limit=limit,
        offset=offset,
    )
    return {"items": items, "total": total}
