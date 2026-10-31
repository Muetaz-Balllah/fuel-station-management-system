import csv
import io
import uuid
from datetime import timedelta
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from db import engine
from main import app
from supply.models import SupplyOrder
from tests.helpers import auth_header, login
from utils import utcnow


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


def _manager(client) -> str:
    return login(client, "manager", "Manager@12345")["access_token"]


def _product(client, token: str) -> str:
    products = client.get("/api/v1/products", headers=auth_header(token)).json()["items"]
    return next(item["id"] for item in products if item["code"] == "G95")


def _user(client, token: str) -> str:
    created = client.post(
        "/api/v1/users",
        headers=auth_header(token),
        json={
            "full_name": "مناوب اللوحة",
            "username": "dash.operator",
            "job_title": "موظف",
            "role_code": "operator",
            "password": "Staff@12345",
        },
    )
    assert created.status_code == 201, created.text
    return created.json()["id"]


def test_dashboard_matches_approved_duty_inventory_and_staff(client):
    token = _manager(client)
    product = _product(client, token)
    tank = client.post(
        "/api/v1/tanks",
        headers=auth_header(token),
        json={"name": "خزان اللوحة", "product_id": product, "capacity_liters": "10000.000"},
    )
    assert tank.status_code == 201, tank.text
    tank_id = tank.json()["id"]
    filled = client.post(
        f"/api/v1/tanks/{tank_id}/adjustments",
        headers=auth_header(token),
        json={"liters_delta": "2000.000", "note": "رصيد لوحة القيادة"},
    )
    assert filled.status_code == 201, filled.text
    pump = client.post(
        "/api/v1/pumps",
        headers=auth_header(token),
        json={"code": "PUMP-DASH", "tank_id": tank_id},
    )
    assert pump.status_code == 201, pump.text
    nozzle = client.post(
        f"/api/v1/pumps/{pump.json()['id']}/nozzles",
        headers=auth_header(token),
        json={"code": "N1", "label": "يمين", "initial_meter": "1000.000"},
    )
    assert nozzle.status_code == 201, nozzle.text
    templates = client.get("/api/v1/shift-templates", headers=auth_header(token)).json()["items"]
    morning = next(item for item in templates if item["name_ar"] == "صباحية")
    day = "2026-12-15"
    shift = client.post(
        "/api/v1/sessions",
        headers=auth_header(token),
        json={"template_id": morning["id"], "business_date": day},
    )
    assert shift.status_code == 201, shift.text
    operator_id = _user(client, token)
    assigned = client.post(
        f"/api/v1/sessions/{shift.json()['id']}/attendance",
        headers=auth_header(token),
        json={"user_id": operator_id, "nozzle_ids": [nozzle.json()["id"]], "check_in_at": "08:00"},
    )
    assert assigned.status_code == 201, assigned.text
    operator = login(client, "dash.operator", "Staff@12345")["access_token"]
    opened = client.post(
        "/api/v1/duties/open",
        headers=auth_header(operator),
        json={
            "session_id": shift.json()["id"],
            "nozzles": [{"nozzle_id": nozzle.json()["id"], "opening_meter": "1000.000"}],
        },
    )
    assert opened.status_code == 201, opened.text
    closed = client.post(
        f"/api/v1/duties/{opened.json()['id']}/close",
        headers=auth_header(operator),
        json={
            "cash_handed": "85.00",
            "lines": [{"nozzle_id": nozzle.json()["id"], "closing_meter": "1600.000"}],
        },
    )
    assert closed.status_code == 200, closed.text
    assert closed.json()["expected_cash"] == "90.00"
    assert closed.json()["variance"] == "-5.00"
    approved = client.post(f"/api/v1/duties/{opened.json()['id']}/approve", headers=auth_header(token))
    assert approved.status_code == 200, approved.text
    denied = client.get(f"/api/v1/dashboard?date={day}", headers=auth_header(operator))
    assert denied.status_code == 403
    board = client.get(f"/api/v1/dashboard?date={day}", headers=auth_header(token))
    assert board.status_code == 200, board.text
    body = board.json()
    tanks = client.get("/api/v1/tanks", headers=auth_header(token)).json()["items"]
    inventory = sum(Decimal(item["current_liters"]) for item in tanks)
    assert body["revenue"] == "90.00"
    assert body["inventory_liters"] == f"{inventory:.3f}"
    assert body["staff_on_duty"] == 1
    assert body["alert"] is not None
    assert body["alert"]["percent"] <= 15
    notes = client.get("/api/v1/notifications", headers=auth_header(token)).json()["items"]
    assert any(item["kind"] == "tank_critical" and item["entity_id"] == tank_id for item in notes)
    row = next(item for item in body["sessions"] if item["id"] == shift.json()["id"])
    assert row["variance_label"] == "-5.00 د.ل (عجز)"
    assert row["revenue"] == "90.00"
    exported = client.get(f"/api/v1/dashboard/export?date={day}", headers=auth_header(token))
    assert exported.status_code == 200
    table = list(csv.reader(io.StringIO(exported.content.decode("utf-8-sig"))))
    revenue_index = table[0].index("الإيراد")
    revenue = sum(Decimal(line[revenue_index] or "0") for line in table[1:])
    assert revenue == Decimal(body["revenue"])
    morning_bar = next(item for item in body["week"] if item["date"] == day)
    assert morning_bar["morning"] == "90.00"


def test_license_and_stale_order_raise_notifications(client):
    token = _manager(client)
    soon = (utcnow().date() + timedelta(days=10)).isoformat()
    patched = client.patch(
        "/api/v1/station",
        headers=auth_header(token),
        json={"license_expires_on": soon},
    )
    assert patched.status_code == 200, patched.text
    product = _product(client, token)
    tank = client.post(
        "/api/v1/tanks",
        headers=auth_header(token),
        json={"name": "خزان التنبيه", "product_id": product, "capacity_liters": "1000.000"},
    )
    assert tank.status_code == 201, tank.text
    suppliers = client.get("/api/v1/suppliers", headers=auth_header(token)).json()["items"]
    brega = next(item for item in suppliers if "البريقة" in item["name"])
    order = client.post(
        "/api/v1/supply-orders",
        headers=auth_header(token),
        json={
            "supplier_id": brega["id"],
            "tank_id": tank.json()["id"],
            "product_id": product,
            "ordered_liters": "100.000",
            "expected_on": "2026-12-20",
        },
    )
    assert order.status_code == 201, order.text
    with Session(engine) as db:
        row = db.get(SupplyOrder, uuid.UUID(order.json()["id"]))
        row.created_at = utcnow() - timedelta(days=4)
        db.add(row)
        db.commit()
    board = client.get("/api/v1/dashboard?date=2026-12-16", headers=auth_header(token))
    assert board.status_code == 200, board.text
    assert board.json()["license_due"] is True
    notes = client.get("/api/v1/notifications", headers=auth_header(token)).json()["items"]
    license_row = next(item for item in notes if item["kind"] == "license_due")
    stale = next(item for item in notes if item["kind"] == "order_stale" and item["entity_id"] == order.json()["id"])
    assert license_row["read_at"] is None
    read = client.post(f"/api/v1/notifications/{license_row['id']}/read", headers=auth_header(token))
    assert read.status_code == 200, read.text
    assert read.json()["read_at"] is not None
    assert stale["title"]
    with Session(engine) as db:
        stale_order = db.get(SupplyOrder, uuid.UUID(order.json()["id"]))
        db.delete(stale_order)
        db.commit()
    restored = client.patch(
        "/api/v1/station",
        headers=auth_header(token),
        json={"license_expires_on": "2027-12-31"},
    )
    assert restored.status_code == 200, restored.text
