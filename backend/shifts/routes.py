from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel
from sqlmodel import Session

from core.deps import require_permission
from db import get_session
from shifts.services import (
    approve_duty,
    close_duty,
    get_duty,
    my_assignment,
    my_duties,
    open_duty,
    reject_duty,
    session_duties,
    shift_log,
)
from users.models import User

router = APIRouter(tags=["shifts"])


class OpenNozzle(BaseModel):
    nozzle_id: str
    opening_meter: str


class OpenDuty(BaseModel):
    session_id: str | None = None
    template_id: str | None = None
    nozzles: list[OpenNozzle]
    reason: str | None = None


class CloseLine(BaseModel):
    nozzle_id: str
    closing_meter: str
    rollover: bool = False
    meter_rollover_at: str | None = None


class CloseDuty(BaseModel):
    lines: list[CloseLine]
    cash_handed: str


class RejectDuty(BaseModel):
    reason: str


def _permissions(request: Request) -> tuple[str, ...]:
    return tuple(getattr(request.state, "permissions", ()))


@router.get("/me/assignment")
def read_assignment(
    user: User = Depends(require_permission("shifts.operate")),
    session: Session = Depends(get_session),
) -> dict:
    return my_assignment(session, user)


@router.post("/duties/open", status_code=201)
def post_open(
    payload: OpenDuty,
    request: Request,
    user: User = Depends(require_permission("shifts.operate")),
    session: Session = Depends(get_session),
) -> dict:
    return open_duty(session, user, payload, _permissions(request))


@router.get("/duties/{duty_id}")
def read_duty(
    duty_id: str,
    request: Request,
    user: User = Depends(require_permission("shifts.operate")),
    session: Session = Depends(get_session),
) -> dict:
    return get_duty(session, user, duty_id, _permissions(request))


@router.post("/duties/{duty_id}/close")
def post_close(
    duty_id: str,
    payload: CloseDuty,
    request: Request,
    user: User = Depends(require_permission("shifts.operate")),
    session: Session = Depends(get_session),
) -> dict:
    return close_duty(session, user, duty_id, payload, _permissions(request))


@router.post("/duties/{duty_id}/approve")
def post_approve(
    duty_id: str,
    user: User = Depends(require_permission("shifts.approve")),
    session: Session = Depends(get_session),
) -> dict:
    return approve_duty(session, user, duty_id)


@router.post("/duties/{duty_id}/reject")
def post_reject(
    duty_id: str,
    payload: RejectDuty,
    user: User = Depends(require_permission("shifts.approve")),
    session: Session = Depends(get_session),
) -> dict:
    return reject_duty(session, user, duty_id, payload.reason)


@router.get("/me/duties")
def read_mine(
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    user: User = Depends(require_permission("shifts.operate")),
    session: Session = Depends(get_session),
) -> dict:
    return my_duties(session, user, page=page, page_size=page_size)


@router.get("/sessions/{session_id}/duties")
def read_session_duties(
    session_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    user: User = Depends(require_permission("shifts.view_all")),
    session: Session = Depends(get_session),
) -> dict:
    return session_duties(session, user, session_id, page=page, page_size=page_size)


@router.get("/shift-log")
def read_log(
    date_from: str | None = None,
    date_to: str | None = None,
    status: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    user: User = Depends(require_permission("shifts.view_all")),
    session: Session = Depends(get_session),
) -> dict:
    return shift_log(session, user, date_from, date_to, status, page=page, page_size=page_size)
