import pytest
from fastapi.testclient import TestClient

from main import app
from tests.helpers import auth_header, login


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


def _manager(client) -> str:
    return login(client, "manager", "Manager@12345")["access_token"]


def test_board_matches_the_demo_cards(client):
    token = _manager(client)
    board = client.get("/api/v1/assets/board", headers=auth_header(token))
    assert board.status_code == 200, board.text
    body = board.json()
    assert body["demo"] is True
    by_code = {card["pump"]["code"]: card for card in body["cards"]}
    gasoline = by_code["PUMP-01"]
    assert gasoline["tank"]["code"] == "T-01"
    assert gasoline["tank"]["percent"] == 76
    assert gasoline["tank"]["current_liters"] == "19000.000"
    assert gasoline["tank"]["capacity_liters"] == "25000.000"
    assert gasoline["tank"]["today_liters"] == "2850.000"
    assert gasoline["tank"]["card_band_label"] == "مستقر"
    assert [item["code"] for item in gasoline["nozzles"]] == ["N1", "N2"]
    assert gasoline["nozzles"][0]["current_meter"] == "680150.000"
    diesel = by_code["PUMP-D1"]
    assert diesel["pump"]["status"] == "maintenance"
    assert diesel["tank"]["percent"] == 22
    assert diesel["tank"]["card_band_label"] == "يحتاج صيانة"
    assert len(diesel["nozzles"]) == 2


def test_two_pumps_cannot_share_a_tank(client):
    token = _manager(client)
    tanks = client.get("/api/v1/tanks", headers=auth_header(token)).json()["items"]
    tank = next(item for item in tanks if item["code"] == "T-01")
    response = client.post(
        "/api/v1/pumps",
        headers=auth_header(token),
        json={"code": "PUMP-99", "tank_id": tank["id"]},
    )
    assert response.status_code == 409
    assert response.json()["code"] == "TANK_ALREADY_LINKED"
    assert "خزان" in response.json()["message"]


def test_new_nozzle_stays_on_its_pump(client):
    token = _manager(client)
    pumps = client.get("/api/v1/pumps", headers=auth_header(token)).json()["items"]
    pump = next(item for item in pumps if item["code"] == "PUMP-02")
    created = client.post(
        f"/api/v1/pumps/{pump['id']}/nozzles",
        headers=auth_header(token),
        json={"code": "N9", "label": "يمين", "initial_meter": "1234.500", "status": "ready"},
    )
    assert created.status_code == 201, created.text
    assert created.json()["current_meter"] == "1234.500"
    board = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    by_code = {card["pump"]["code"]: card for card in board["cards"]}
    assert any(item["code"] == "N9" for item in by_code["PUMP-02"]["nozzles"])
    assert all(item["code"] != "N9" for item in by_code["PUMP-01"]["nozzles"])


def test_adjustment_round_trip_and_capacity_guard(client):
    token = _manager(client)
    products = client.get("/api/v1/assets/board", headers=auth_header(token)).json()["products"]
    gasoline = next(item for item in products if item["code"] == "G95")
    created = client.post(
        "/api/v1/tanks",
        headers=auth_header(token),
        json={"name": "خزان اختبار", "product_id": gasoline["id"], "capacity_liters": "5000"},
    )
    assert created.status_code == 201, created.text
    tank_id = created.json()["id"]
    assert created.json()["current_liters"] == "0.000"
    up = client.post(
        f"/api/v1/tanks/{tank_id}/adjustments",
        headers=auth_header(token),
        json={"liters_delta": "1000", "note": "زيادة تجريبية"},
    )
    assert up.status_code == 201, up.text
    assert up.json()["current_liters"] == "1000.000"
    down = client.post(
        f"/api/v1/tanks/{tank_id}/adjustments",
        headers=auth_header(token),
        json={"liters_delta": "-1000", "note": "عكس الزيادة"},
    )
    assert down.status_code == 201, down.text
    assert down.json()["current_liters"] == "0.000"
    events = client.get("/api/v1/inventory/events", headers=auth_header(token)).json()
    notes = [item["note"] for item in events["items"]]
    assert "زيادة تجريبية" in notes
    assert "عكس الزيادة" in notes
    refused = client.post(
        f"/api/v1/tanks/{tank_id}/adjustments",
        headers=auth_header(token),
        json={"liters_delta": "5001", "note": "فوق السعة"},
    )
    assert refused.status_code == 422
    assert refused.json()["code"] == "BALANCE_OUT_OF_RANGE"
    current = client.get("/api/v1/tanks", headers=auth_header(token)).json()["items"]
    tank = next(item for item in current if item["id"] == tank_id)
    assert tank["current_liters"] == "0.000"


def test_maintenance_changes_the_band_and_keeps_nozzles(client):
    token = _manager(client)
    pumps = client.get("/api/v1/pumps", headers=auth_header(token)).json()["items"]
    pump = next(item for item in pumps if item["code"] == "PUMP-02")
    before = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    before_card = next(card for card in before["cards"] if card["pump"]["code"] == "PUMP-02")
    nozzle_codes = [item["code"] for item in before_card["nozzles"]]
    updated = client.patch(
        f"/api/v1/pumps/{pump['id']}",
        headers=auth_header(token),
        json={"status": "maintenance"},
    )
    assert updated.status_code == 200, updated.text
    board = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    card = next(item for item in board["cards"] if item["pump"]["code"] == "PUMP-02")
    assert card["tank"]["card_band_label"] == "يحتاج صيانة"
    assert [item["code"] for item in card["nozzles"]] == nozzle_codes
    restored = client.patch(
        f"/api/v1/pumps/{pump['id']}",
        headers=auth_header(token),
        json={"status": "active"},
    )
    assert restored.status_code == 200


def test_operator_cannot_open_assets(client):
    token = login(client, "operator", "Operator@12345")["access_token"]
    assert client.get("/api/v1/assets/board", headers=auth_header(token)).status_code == 403
    assert client.get("/api/v1/tanks", headers=auth_header(token)).status_code == 403
