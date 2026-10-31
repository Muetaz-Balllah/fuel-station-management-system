from fastapi.testclient import TestClient

from main import app
from tests.helpers import auth_header, login


import pytest


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


def _manager(client) -> str:
    return login(client, "manager", "Manager@12345")["access_token"]


def _product(client, token: str, code: str) -> str:
    products = client.get("/api/v1/products", headers=auth_header(token)).json()["items"]
    return next(item["id"] for item in products if item["code"] == code)


def _supplier(client, token: str, name: str) -> dict:
    items = client.get("/api/v1/suppliers", headers=auth_header(token)).json()["items"]
    return next(item for item in items if item["name"] == name)


def _tank(client, token: str, name: str, product_id: str, capacity: str) -> dict:
    created = client.post(
        "/api/v1/tanks",
        headers=auth_header(token),
        json={"name": name, "product_id": product_id, "capacity_liters": capacity},
    )
    assert created.status_code == 201, created.text
    return created.json()


def _order(client, token: str, supplier_id: str, tank_id: str, product_id: str, liters: str):
    return client.post(
        "/api/v1/supply-orders",
        headers=auth_header(token),
        json={
            "supplier_id": supplier_id,
            "tank_id": tank_id,
            "product_id": product_id,
            "ordered_liters": liters,
            "expected_on": "2026-11-20",
            "notes": "اختبار",
        },
    )


def test_receive_fills_the_tank_and_a_mismatch_is_rejected(client):
    token = _manager(client)
    gasoline = _product(client, token, "G95")
    diesel = _product(client, token, "DIESEL")
    gas_tank = _tank(client, token, "خزان استلام", gasoline, "50000.000")
    diesel_tank = _tank(client, token, "خزان ديزل", diesel, "50000.000")
    brega = _supplier(client, token, "شركة البريقة لتسويق النفط")
    assert brega["headquarters"] == "طريق المطار، طرابلس"
    assert brega["contact_name"] == "م. علي صالح"
    assert brega["max_daily_liters"] == "500000.000"
    mismatch = _order(client, token, brega["id"], gas_tank["id"], diesel, "15000.000")
    assert mismatch.status_code == 409
    assert mismatch.json()["code"] == "PRODUCT_MISMATCH"
    created = _order(client, token, brega["id"], gas_tank["id"], gasoline, "15000.000")
    assert created.status_code == 201, created.text
    assert created.json()["status_label"] == "قيد الانتظار"
    received = client.post(
        f"/api/v1/supply-orders/{created.json()['id']}/receive",
        headers=auth_header(token),
        json={},
    )
    assert received.status_code == 200, received.text
    assert received.json()["status"] == "received"
    assert received.json()["received_liters"] == "15000.000"
    assert received.json()["received_by_name"] == "أحمد المصراتي"
    tanks = client.get("/api/v1/tanks", headers=auth_header(token)).json()["items"]
    tank = next(item for item in tanks if item["id"] == gas_tank["id"])
    assert tank["current_liters"] == "15000.000"
    assert tank["percent"] == 30
    assert tank["last_receipt_label"].startswith("اليوم")
    events = client.get("/api/v1/inventory/events", headers=auth_header(token)).json()["items"]
    receipt = next(item for item in events if item["note"] == created.json()["code"])
    assert receipt["movement_type"] == "supply_receipt"
    assert receipt["actor_name"] == "أحمد المصراتي"
    assert receipt["liters_delta"] == "15000.000"
    too_much = _order(client, token, brega["id"], gas_tank["id"], gasoline, "40000.000")
    assert too_much.status_code == 201, too_much.text
    blocked = client.post(
        f"/api/v1/supply-orders/{too_much.json()['id']}/receive",
        headers=auth_header(token),
        json={"received_liters": "40000.000"},
    )
    assert blocked.status_code == 422
    assert blocked.json()["code"] == "CAPACITY_EXCEEDED"
    still = client.get("/api/v1/tanks", headers=auth_header(token)).json()["items"]
    assert next(item["current_liters"] for item in still if item["id"] == gas_tank["id"]) == "15000.000"
    pending = client.get("/api/v1/supply-orders", headers=auth_header(token)).json()["items"]
    assert next(item for item in pending if item["id"] == too_much.json()["id"])["status"] == "pending"
    cancelled = client.post(
        f"/api/v1/supply-orders/{too_much.json()['id']}/cancel",
        headers=auth_header(token),
    )
    assert cancelled.status_code == 200, cancelled.text
    assert next(item["current_liters"] for item in client.get("/api/v1/tanks", headers=auth_header(token)).json()["items"] if item["id"] == gas_tank["id"]) == "15000.000"
    closed = client.post(
        f"/api/v1/supply-orders/{created.json()['id']}/cancel",
        headers=auth_header(token),
    )
    assert closed.status_code == 409
    assert closed.json()["code"] == "ORDER_CLOSED"
    card = client.get(f"/api/v1/suppliers/{brega['id']}", headers=auth_header(token)).json()
    assert card["reliability"] == 50
    assert card["headquarters"] == "طريق المطار، طرابلس"
    counts = client.get("/api/v1/supply/summary", headers=auth_header(token)).json()
    assert counts["delivered_liters"] == "15000.000"
    assert counts["pending_orders"] == 0
    assert counts["active_orders"] == 1
    assert counts["active_suppliers"] == 3
    assert any(day["liters"] == "15000.000" for day in counts["week"])
    assert len(counts["week"]) == 7
    operator = login(client, "operator", "Operator@12345")["access_token"]
    denied = client.get("/api/v1/supply/summary", headers=auth_header(operator))
    assert denied.status_code == 403
    denied_tank = client.post(
        "/api/v1/supply-orders",
        headers=auth_header(operator),
        json={
            "supplier_id": brega["id"],
            "tank_id": diesel_tank["id"],
            "product_id": diesel,
            "ordered_liters": "1000",
            "expected_on": "2026-11-20",
        },
    )
    assert denied_tank.status_code == 403
