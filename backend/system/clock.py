from sqlmodel import Session

from assets.levels import station_timezone
from stations.models import Station
from users.models import User
from utils import utcnow


def station_clock(session: Session, user: User) -> dict:
    station = session.get(Station, user.station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    now = utcnow()
    local = now.astimezone(tz)
    return {
        "utc": now.isoformat(),
        "timezone": str(tz),
        "business_date": local.date().isoformat(),
        "local_time": local.strftime("%H:%M"),
    }
