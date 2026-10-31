import uuid

from fastapi import APIRouter, Depends
from fastapi.responses import Response
from pydantic import BaseModel
from sqlmodel import Session

from attendance.services import (
    attendance_csv,
    list_attendance,
    list_sessions,
    open_session,
    options,
    register_attendance,
    summary,
    update_attendance,
    _parse_date,
)
from core.deps import require_permission
from db import get_session
from users.models import User

router = APIRouter(tags=["attendance"])


class SessionCreate(BaseModel):
    template_id: str
    business_date: str
    supervisor_id: str | None = None


class AttendanceCreate(BaseModel):
    user_id: str
    nozzle_ids: list[str] = []
    check_in_at: str | None = None
    note: str | None = None
    status: str | None = None


class AttendanceUpdate(BaseModel):
    nozzle_ids: list[str] | None = None
    check_in_at: str | None = None
    check_out_at: str | None = None
    note: str | None = None
    status: str | None = None


@router.get("/attendance/options")
def read_options(
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return options(session, user)


@router.get("/attendance/summary")
def read_summary(
    date: str,
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return summary(session, user, _parse_date(date))


@router.get("/sessions")
def read_sessions(
    date: str | None = None,
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> dict:
    business_date = _parse_date(date) if date else None
    items = list_sessions(session, user, business_date)
    return {"items": items, "total": len(items)}


@router.post("/sessions", status_code=201)
def post_session(
    payload: SessionCreate,
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return open_session(session, user, payload)


@router.get("/sessions/{session_id}/attendance")
def read_attendance(
    session_id: uuid.UUID,
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items = list_attendance(session, user, session_id)
    return {"items": items, "total": len(items)}


@router.get("/sessions/{session_id}/attendance.csv")
def read_attendance_csv(
    session_id: uuid.UUID,
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> Response:
    body = "\ufeff" + attendance_csv(session, user, session_id)
    return Response(
        content=body,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": "attachment; filename=attendance.csv"},
    )


@router.post("/sessions/{session_id}/attendance", status_code=201)
def post_attendance(
    session_id: uuid.UUID,
    payload: AttendanceCreate,
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return register_attendance(session, user, session_id, payload)


@router.patch("/attendances/{attendance_id}")
def patch_attendance(
    attendance_id: uuid.UUID,
    payload: AttendanceUpdate,
    user: User = Depends(require_permission("attendance.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return update_attendance(session, user, attendance_id, payload)
