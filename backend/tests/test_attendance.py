from datetime import datetime, timedelta

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


def _user(client, token: str, name: str, username: str) -> str:
    created = client.post(
        "/api/v1/users",
        headers=auth_header(token),
        json={
            "full_name": name,
            "username": username,
            "job_title": "موظف",
            "role_code": "operator",
            "password": "Staff@12345",
        },
    )
    assert created.status_code == 201, created.text
    return created.json()["id"]


def _morning(client, token: str, day: str) -> dict:
    templates = client.get("/api/v1/shift-templates", headers=auth_header(token)).json()["items"]
    template = next(item for item in templates if item["name_ar"] == "صباحية")
    opened = client.post(
        "/api/v1/sessions",
        headers=auth_header(token),
        json={"template_id": template["id"], "business_date": day},
    )
    assert opened.status_code == 201, opened.text
    return opened.json()


def test_present_late_and_absent_follow_the_grace_window(client):
    token = _manager(client)
    day = "2026-10-26"
    shift = _morning(client, token, day)
    assert shift["crosses_midnight"] is False
    start = datetime.fromisoformat(shift["starts_at"])
    end = datetime.fromisoformat(shift["ends_at"])
    assert end - start == timedelta(hours=8)
    board = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    active = [card for card in board["cards"] if card["pump"]["status"] == "active"]
    nozzles = [card["nozzles"][0]["id"] for card in active[:3]]
    mohammed = _user(client, token, "محمد", "mohammed.att")
    khaled = _user(client, token, "خالد", "khaled.att")
    third = _user(client, token, "سالم الثاني", "salem.two")
    absent = _user(client, token, "سالم", "salem.att")
    early = client.post(
        f"/api/v1/sessions/{shift['id']}/attendance",
        headers=auth_header(token),
        json={"user_id": mohammed, "nozzle_ids": [nozzles[0]], "check_in_at": "07:55"},
    )
    assert early.status_code == 201, early.text
    assert early.json()["status_label"] == "حاضر"
    assert early.json()["check_in_label"] == "07:55"
    assert early.json()["assignments"][0]["nozzle_code"] == "N1"
    late = client.post(
        f"/api/v1/sessions/{shift['id']}/attendance",
        headers=auth_header(token),
        json={"user_id": khaled, "nozzle_ids": [nozzles[1]], "check_in_at": "08:45"},
    )
    assert late.status_code == 201, late.text
    assert late.json()["status_label"] == "متأخر"
    on_time = client.post(
        f"/api/v1/sessions/{shift['id']}/attendance",
        headers=auth_header(token),
        json={"user_id": third, "nozzle_ids": [nozzles[2]], "check_in_at": "08:00"},
    )
    assert on_time.status_code == 201, on_time.text
    missing = client.post(
        f"/api/v1/sessions/{shift['id']}/attendance",
        headers=auth_header(token),
        json={"user_id": absent, "nozzle_ids": [], "status": "absent", "note": "بدون عذر مسبق"},
    )
    assert missing.status_code == 201, missing.text
    assert missing.json()["status_label"] == "غائب"
    assert missing.json()["check_in_at"] is None
    assert missing.json()["check_in_label"] is None
    assert missing.json()["note"] == "بدون عذر مسبق"
    taken = client.post(
        f"/api/v1/sessions/{shift['id']}/attendance",
        headers=auth_header(token),
        json={
            "user_id": _user(client, token, "آخر", "other.att"),
            "nozzle_ids": [nozzles[0]],
            "check_in_at": "08:00",
        },
    )
    assert taken.status_code == 409
    assert taken.json()["code"] == "NOZZLE_TAKEN"
    summary = client.get(f"/api/v1/attendance/summary?date={day}", headers=auth_header(token)).json()
    assert summary["morning"]["showed"] == 3
    assert summary["morning"]["total"] == 4
    assert summary["morning"]["percent"] == 75
    assert summary["coverage"]["covered"] == 3
    assert summary["late_count"] == 1
    monday = next(item for item in summary["week"] if item["date"] == day)
    assert monday["percent"] == 75
    exported = client.get(f"/api/v1/sessions/{shift['id']}/attendance.csv", headers=auth_header(token))
    assert exported.status_code == 200
    text = exported.content.decode("utf-8-sig")
    assert "محمد" in text
    assert "خالد" in text
    assert "سالم" in text
    assert "حاضر" in text
    assert "متأخر" in text
    assert "غائب" in text
    assert "بدون عذر مسبق" in text


def test_maintenance_pump_cannot_be_assigned(client):
    token = _manager(client)
    shift = _morning(client, token, "2026-10-27")
    board = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    maintenance = next(card for card in board["cards"] if card["pump"]["status"] == "maintenance")
    nozzle = maintenance["nozzles"][0]["id"]
    user_id = _user(client, token, "فني", "tech.att")
    response = client.post(
        f"/api/v1/sessions/{shift['id']}/attendance",
        headers=auth_header(token),
        json={"user_id": user_id, "nozzle_ids": [nozzle], "check_in_at": "08:00"},
    )
    assert response.status_code == 409
    assert response.json()["code"] == "PUMP_UNAVAILABLE"


def test_evening_template_ends_the_next_day(client):
    token = _manager(client)
    templates = client.get("/api/v1/shift-templates", headers=auth_header(token)).json()["items"]
    evening = next(item for item in templates if item["name_ar"] == "مسائية")
    opened = client.post(
        "/api/v1/sessions",
        headers=auth_header(token),
        json={"template_id": evening["id"], "business_date": "2026-10-31"},
    )
    assert opened.status_code == 201, opened.text
    body = opened.json()
    assert body["crosses_midnight"] is True
    start = datetime.fromisoformat(body["starts_at"])
    end = datetime.fromisoformat(body["ends_at"])
    assert end - start == timedelta(hours=8)
    again = client.post(
        "/api/v1/sessions",
        headers=auth_header(token),
        json={"template_id": evening["id"], "business_date": "2026-10-31"},
    )
    assert again.json()["id"] == body["id"]


def test_operator_cannot_open_attendance(client):
    token = login(client, "operator", "Operator@12345")["access_token"]
    assert client.get("/api/v1/attendance/options", headers=auth_header(token)).status_code == 403
    assert client.get("/api/v1/sessions", headers=auth_header(token)).status_code == 403
