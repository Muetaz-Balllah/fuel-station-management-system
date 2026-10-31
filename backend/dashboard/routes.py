from fastapi import APIRouter, Depends
from fastapi.responses import Response
from sqlmodel import Session

from core.deps import require_permission
from dashboard.services import dashboard, dashboard_csv, notifications, read_notification
from db import get_session
from users.models import User

router = APIRouter(tags=["dashboard"])


@router.get("/dashboard")
def read_dashboard(
    date: str | None = None,
    user: User = Depends(require_permission("dashboard.view")),
    session: Session = Depends(get_session),
) -> dict:
    return dashboard(session, user, date)


@router.get("/dashboard/export")
def export_dashboard(
    date: str | None = None,
    user: User = Depends(require_permission("reports.export")),
    session: Session = Depends(get_session),
) -> Response:
    text = dashboard_csv(session, user, date)
    filename = date or "today"
    return Response(
        content="\ufeff" + text,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="shifts-{filename}.csv"'},
    )


@router.get("/notifications")
def read_notifications(
    user: User = Depends(require_permission("dashboard.view")),
    session: Session = Depends(get_session),
) -> dict:
    items = notifications(session, user)
    return {"items": items, "total": len(items)}


@router.post("/notifications/{notification_id}/read")
def post_read(
    notification_id: str,
    user: User = Depends(require_permission("dashboard.view")),
    session: Session = Depends(get_session),
) -> dict:
    return read_notification(session, user, notification_id)
