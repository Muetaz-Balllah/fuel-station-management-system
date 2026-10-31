"""Money rules for a duty. No database imports."""

from decimal import Decimal, ROUND_HALF_UP

_LITERS = Decimal("0.001")
_MONEY = Decimal("0.01")


def q_liters(value) -> Decimal:
    return Decimal(str(value)).quantize(_LITERS, rounding=ROUND_HALF_UP)


def q_money(value) -> Decimal:
    return Decimal(str(value)).quantize(_MONEY, rounding=ROUND_HALF_UP)


def format_liters(value) -> str:
    return f"{q_liters(value):.3f}"


def format_money(value) -> str:
    return f"{q_money(value):.2f}"


def format_price(value) -> str:
    return f"{q_liters(value):.3f}"


def line_liters(opening, closing, *, rollover: bool = False, rollover_at=None) -> Decimal:
    start = q_liters(opening)
    end = q_liters(closing)
    if rollover:
        if rollover_at is None:
            raise ValueError("rollover_at is required")
        wrap = q_liters(rollover_at)
        return q_liters((wrap - start) + end)
    return q_liters(end - start)


def reconcile(lines: list[dict], cash_handed) -> dict:
    """Each line needs opening, closing, and unit_price. Optional rollover and rollover_at."""
    computed = []
    total_liters = Decimal("0.000")
    expected = Decimal("0.00")
    for line in lines:
        liters = line_liters(
            line["opening"],
            line["closing"],
            rollover=bool(line.get("rollover")),
            rollover_at=line.get("rollover_at"),
        )
        if liters < 0:
            raise ValueError("meter regression")
        amount = q_money(liters * q_liters(line["unit_price"]))
        total_liters = q_liters(total_liters + liters)
        expected = q_money(expected + amount)
        computed.append(
            {
                "nozzle_id": line.get("nozzle_id"),
                "liters": liters,
                "unit_price": q_liters(line["unit_price"]),
                "line_amount": amount,
            }
        )
    cash = q_money(cash_handed)
    variance = q_money(cash - expected)
    return {
        "liters": total_liters,
        "expected_cash": expected,
        "cash_handed": cash,
        "variance": variance,
        "variance_kind": variance_kind(variance),
        "lines": computed,
    }


def variance_kind(variance: Decimal) -> str:
    if variance == 0:
        return "match"
    if variance > 0:
        return "surplus"
    return "shortage"


def variance_label(variance) -> str:
    amount = q_money(variance)
    text = format_money(amount)
    if amount == 0:
        return f"{text} د.ل (مطابق)"
    if amount > 0:
        return f"+{text} د.ل (فائض)"
    return f"{text} د.ل (عجز)"


def submitted_liters(entries: list[dict]) -> Decimal:
    """Approved liters plus a close that is waiting for a signature. An open duty has no liters yet."""
    total = Decimal("0.000")
    for entry in entries:
        if entry.get("status") not in {"approved", "pending_approval"}:
            continue
        total = q_liters(total + q_liters(entry.get("liters") or 0))
    return total


def rollup(entries: list[dict]) -> dict:
    """Sum approved duties. Open and pending rows do not add revenue."""
    liters = Decimal("0.000")
    revenue = Decimal("0.00")
    variance = Decimal("0.00")
    counted = 0
    for entry in entries:
        if entry.get("status") != "approved":
            continue
        liters = q_liters(liters + q_liters(entry.get("liters") or 0))
        revenue = q_money(revenue + q_money(entry.get("expected_cash") or 0))
        variance = q_money(variance + q_money(entry.get("variance") or 0))
        counted += 1
    return {
        "duties": counted,
        "liters": liters,
        "revenue": revenue,
        "variance": variance,
    }
