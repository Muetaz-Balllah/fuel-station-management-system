from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

_TRIPOLI = timezone(timedelta(hours=2))


def station_timezone(name: str):
    try:
        from zoneinfo import ZoneInfo

        return ZoneInfo(name)
    except Exception:
        return _TRIPOLI


def as_decimal(value) -> Decimal:
    return Decimal(str(value)).quantize(Decimal("0.001"))


def format_qty(value) -> str:
    return f"{as_decimal(value):.3f}"


def percent_of(current, capacity) -> int:
    current_value = as_decimal(current)
    capacity_value = as_decimal(capacity)
    if capacity_value <= 0:
        return 0
    ratio = (current_value / capacity_value) * Decimal(100)
    return int(ratio.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def level_band(percent: int, critical: int, warning: int) -> str:
    if percent < critical:
        return "critical"
    if percent < warning:
        return "warning"
    return "stable"


def receipt_label(moment: datetime | None, now: datetime, tz) -> str | None:
    if moment is None:
        return None
    local = moment.astimezone(tz)
    today = now.astimezone(tz).date()
    days = (today - local.date()).days
    clock = local.strftime("%H:%M")
    suffix = "ص" if local.hour < 12 else "م"
    if days <= 0:
        return f"اليوم، {clock} {suffix}"
    if days == 1:
        return f"أمس، {clock} {suffix}"
    return f"{days} أيام مضت"
