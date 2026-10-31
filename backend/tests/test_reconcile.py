from decimal import Decimal

import pytest

from shifts.reconciliation import format_money, reconcile, variance_label


def _line(opening, closing, price, nozzle_id="n"):
    return {"nozzle_id": nozzle_id, "opening": opening, "closing": closing, "unit_price": price}


def test_fixture_4280_liters_matches_642():
    figures = reconcile(
        [
            _line("1841200.000", "1843450.000", "0.150", "a"),
            _line("1621075.000", "1623105.000", "0.150", "b"),
        ],
        "642.00",
    )
    assert figures["liters"] == Decimal("4280.000")
    assert figures["expected_cash"] == Decimal("642.00")
    assert figures["variance"] == Decimal("0.00")
    assert figures["variance_kind"] == "match"
    assert figures["lines"][0]["line_amount"] == Decimal("337.50")
    assert figures["lines"][1]["line_amount"] == Decimal("304.50")
    assert variance_label(figures["variance"]) == "0.00 د.ل (مطابق)"


def test_surplus_and_shortage_are_five_dinars():
    lines = [
        _line("1841200.000", "1843450.000", "0.150", "a"),
        _line("1621075.000", "1623105.000", "0.150", "b"),
    ]
    surplus = reconcile(lines, "647.00")
    shortage = reconcile(lines, "637.00")
    assert surplus["variance"] == Decimal("5.00")
    assert surplus["variance_kind"] == "surplus"
    assert variance_label(surplus["variance"]) == "+5.00 د.ل (فائض)"
    assert shortage["variance"] == Decimal("-5.00")
    assert shortage["variance_kind"] == "shortage"
    assert variance_label(shortage["variance"]) == "-5.00 د.ل (عجز)"
    second = reconcile([_line("0", "8120", "0.150")], "1223.00")
    assert second["expected_cash"] == Decimal("1218.00")
    assert second["variance"] == Decimal("5.00")


def test_mixed_prices_stay_on_their_own_lines():
    figures = reconcile(
        [
            _line("0", "1000", "0.150", "gas"),
            _line("0", "1000", "0.180", "diesel"),
        ],
        "330.00",
    )
    assert figures["lines"][0]["unit_price"] == Decimal("0.150")
    assert figures["lines"][1]["unit_price"] == Decimal("0.180")
    assert figures["lines"][0]["line_amount"] == Decimal("150.00")
    assert figures["lines"][1]["line_amount"] == Decimal("180.00")
    assert figures["expected_cash"] == Decimal("330.00")
    assert format_money(figures["expected_cash"]) == "330.00"


def test_closing_below_opening_is_refused():
    with pytest.raises(ValueError):
        reconcile([_line("100", "90", "0.150")], "0")
