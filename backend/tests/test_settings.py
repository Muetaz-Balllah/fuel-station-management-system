import pytest
from fastapi.testclient import TestClient

from tests.helpers import auth_header, login
from main import app


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


def test_license_edit_survives_reload(client):
    token = login(client, "manager", "Manager@12345")["access_token"]
    original = client.get("/api/v1/station", headers=auth_header(token)).json()
    renamed = client.patch(
        "/api/v1/station",
        headers=auth_header(token),
        json={"license_number": "LY-TEST-9001"},
    )
    assert renamed.status_code == 200
    again = client.get("/api/v1/station", headers=auth_header(token))
    assert again.json()["license_number"] == "LY-TEST-9001"
    restored = client.patch(
        "/api/v1/station",
        headers=auth_header(token),
        json={"license_number": original["license_number"]},
    )
    assert restored.status_code == 200


def test_new_operator_can_login_and_password_reset_replaces_the_old_one(client):
    manager = login(client, "manager", "Manager@12345")["access_token"]
    created = client.post(
        "/api/v1/users",
        headers=auth_header(manager),
        json={
            "full_name": "موظف تجريبي",
            "username": "shift.tester",
            "email": "shift.tester@station.local",
            "job_title": "موظف",
            "role_code": "operator",
            "password": "First@12345",
            "is_maintenance": False,
        },
    )
    assert created.status_code == 201, created.text
    user_id = created.json()["id"]
    assert login(client, "shift.tester", "First@12345")["user"]["role_code"] == "operator"
    reset = client.patch(
        f"/api/v1/users/{user_id}",
        headers=auth_header(manager),
        json={"password": "Second@12345"},
    )
    assert reset.status_code == 200, reset.text
    old = client.post(
        "/api/v1/auth/login",
        json={"username": "shift.tester", "password": "First@12345", "remember_me": False},
    )
    assert old.status_code == 401
    assert login(client, "shift.tester", "Second@12345")["access_token"]


def test_deactivating_a_user_kills_the_session(client):
    manager = login(client, "manager", "Manager@12345")["access_token"]
    created = client.post(
        "/api/v1/users",
        headers=auth_header(manager),
        json={
            "full_name": "حساب يوقف",
            "username": "paused.user",
            "role_code": "operator",
            "password": "Pause@12345",
        },
    )
    assert created.status_code == 201, created.text
    user_id = created.json()["id"]
    tokens = login(client, "paused.user", "Pause@12345")
    blocked = client.patch(
        f"/api/v1/users/{user_id}",
        headers=auth_header(manager),
        json={"is_active": False},
    )
    assert blocked.status_code == 200
    me = client.get("/api/v1/auth/me", headers=auth_header(tokens["access_token"]))
    assert me.status_code == 401
    refresh = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert refresh.status_code == 401


def test_manager_cannot_deactivate_self(client):
    tokens = login(client, "manager", "Manager@12345")
    response = client.patch(
        f"/api/v1/users/{tokens['user']['id']}",
        headers=auth_header(tokens["access_token"]),
        json={"is_active": False},
    )
    assert response.status_code == 422


def test_new_price_keeps_the_old_row(client):
    token = login(client, "manager", "Manager@12345")["access_token"]
    products = client.get("/api/v1/products", headers=auth_header(token))
    assert products.status_code == 200
    gasoline = next(item for item in products.json()["items"] if item["code"] == "G95")
    assert gasoline["active_price"] == "0.150"
    posted = client.post(
        f"/api/v1/products/{gasoline['id']}/prices",
        headers=auth_header(token),
        json={"price_per_liter": "0.175"},
    )
    assert posted.status_code == 201, posted.text
    history = client.get(f"/api/v1/products/{gasoline['id']}/prices", headers=auth_header(token))
    prices = [item["price_per_liter"] for item in history.json()["items"]]
    assert "0.150" in prices
    assert "0.175" in prices
    assert history.json()["total"] >= 2
    current = client.get("/api/v1/products", headers=auth_header(token)).json()["items"]
    active = next(item for item in current if item["code"] == "G95")
    assert active["active_price"] == "0.175"
    rejected = client.post(
        f"/api/v1/products/{gasoline['id']}/prices",
        headers=auth_header(token),
        json={"price_per_liter": "0"},
    )
    assert rejected.status_code == 422


def test_shift_template_rules(client):
    token = login(client, "manager", "Manager@12345")["access_token"]
    morning = client.post(
        "/api/v1/shift-templates",
        headers=auth_header(token),
        json={"name_ar": "صباحية", "starts_at": "08:00", "ends_at": "16:00", "grace_minutes": 10},
    )
    assert morning.status_code == 201
    assert morning.json()["crosses_midnight"] is False
    evening = client.post(
        "/api/v1/shift-templates",
        headers=auth_header(token),
        json={"name_ar": "مسائية", "starts_at": "16:00", "ends_at": "00:00", "grace_minutes": 10},
    )
    assert evening.status_code == 201
    assert evening.json()["crosses_midnight"] is True
    empty = client.post(
        "/api/v1/shift-templates",
        headers=auth_header(token),
        json={"name_ar": "   ", "starts_at": "08:00", "ends_at": "16:00", "grace_minutes": 10},
    )
    assert empty.status_code == 422
    assert empty.json()["message"] == "اسم الوردية مطلوب."
    grace = client.post(
        "/api/v1/shift-templates",
        headers=auth_header(token),
        json={"name_ar": "طويلة", "starts_at": "08:00", "ends_at": "16:00", "grace_minutes": 121},
    )
    assert grace.status_code == 422


def test_operator_cannot_open_settings(client):
    token = login(client, "operator", "Operator@12345")["access_token"]
    assert client.get("/api/v1/users", headers=auth_header(token)).status_code == 403
    assert client.get("/api/v1/shift-templates", headers=auth_header(token)).status_code == 403
    assert client.patch(
        "/api/v1/station",
        headers=auth_header(token),
        json={"name": "محاولة"},
    ).status_code == 403


def test_manager_replaces_operator_permissions(client):
    manager = login(client, "manager", "Manager@12345")["access_token"]
    roles = client.get("/api/v1/roles", headers=auth_header(manager)).json()["items"]
    assert [item["code"] for item in roles] == ["station_manager", "operator"]
    operator_role = next(item for item in roles if item["code"] == "operator")
    updated = client.put(
        f"/api/v1/roles/{operator_role['id']}/permissions",
        headers=auth_header(manager),
        json={"permissions": ["shifts.operate", "shifts.view_all"]},
    )
    assert updated.status_code == 200, updated.text
    assert "shifts.view_all" in updated.json()["permissions"]
    restored = client.put(
        f"/api/v1/roles/{operator_role['id']}/permissions",
        headers=auth_header(manager),
        json={"permissions": ["shifts.operate"]},
    )
    assert restored.status_code == 200


def test_logo_upload(client):
    token = login(client, "manager", "Manager@12345")["access_token"]
    uploaded = client.post(
        "/api/v1/station/logo",
        headers=auth_header(token),
        files={"file": ("logo.png", b"\x89PNG\r\n\x1a\nlogo", "image/png")},
    )
    assert uploaded.status_code == 200, uploaded.text
    logo_url = uploaded.json()["logo_url"]
    assert logo_url.startswith("/api/v1/media/")
    fetched = client.get(logo_url.split("?", 1)[0])
    assert fetched.status_code == 200
    assert fetched.content.startswith(b"\x89PNG")
