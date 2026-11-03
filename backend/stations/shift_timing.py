from datetime import date, datetime, time, timezone

from sqlmodel import Session, select

from assets.levels import station_timezone
from stations.models import ShiftTemplate, Station
from stations.windows import expand_window
from utils import utcnow


def _as_time(value) -> time:
    if isinstance(value, time):
        return value
    if isinstance(value, datetime):
        return value.time()
    if isinstance(value, str):
        hour, minute = value.split(":")
        return time(int(hour), int(minute))
    raise TypeError("unsupported time value")


def station_local_today(session: Session, station_id) -> date:
    station = session.get(Station, station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    return datetime.now(tz).date()


def template_window_bounds_utc(
    session: Session,
    station_id,
    template: ShiftTemplate,
    business_date: date,
) -> tuple[datetime, datetime]:
    station = session.get(Station, station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    starts = _as_time(template.starts_at)
    ends = _as_time(template.ends_at)
    start_naive, end_naive = expand_window(starts, ends, business_date)
    start = datetime.combine(start_naive.date(), start_naive.time(), tzinfo=tz)
    end = datetime.combine(end_naive.date(), end_naive.time(), tzinfo=tz)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def today_plannable_templates(session: Session, station_id) -> list[ShiftTemplate]:
    """Shift templates for today that have not passed their end time yet."""
    today = station_local_today(session, station_id)
    now = utcnow()
    rows = session.exec(
        select(ShiftTemplate)
        .where(
            ShiftTemplate.station_id == station_id,
            ShiftTemplate.business_date == today,
            ShiftTemplate.is_active == True,  # noqa: E712
        )
        .order_by(ShiftTemplate.sort_order, ShiftTemplate.name_ar)
    ).all()
    visible: list[ShiftTemplate] = []
    for row in rows:
        _, ends = template_window_bounds_utc(session, station_id, row, today)
        if now <= ends:
            visible.append(row)
    return visible
