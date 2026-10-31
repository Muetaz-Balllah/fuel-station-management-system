import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from db import engine
from main import app
from tests.helpers import auth_header, login
from users.models import User


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


def test_health(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_login_success_returns_role_and_tokens(client):
    body = login(client, "manager", "Manager@12345", remember_me=True)
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["user"]["role_code"] == "station_manager"
    assert body["user"]["full_name"] == "أحمد المصراتي"
    assert "settings.manage" in body["user"]["permissions"]
    assert "dashboard.view" in body["user"]["permissions"]


def test_login_failure_does_not_issue_a_token(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"username": "manager", "password": "wrong-password", "remember_me": False},
    )
    assert response.status_code == 401
    payload = response.json()
    assert payload["code"] == "INVALID_CREDENTIALS"
    assert "access_token" not in payload
    assert "غير صحيحة" in payload["message"]


def test_operator_cannot_patch_station(client):
    tokens = login(client, "operator", "Operator@12345")
    response = client.patch(
        "/api/v1/station",
        headers=auth_header(tokens["access_token"]),
        json={"name": "محطة أخرى"},
    )
    assert response.status_code == 403
    assert response.json()["code"] == "FORBIDDEN"


def test_manager_can_read_and_update_station(client):
    tokens = login(client, "manager", "Manager@12345")
    headers = auth_header(tokens["access_token"])
    current = client.get("/api/v1/station", headers=headers)
    assert current.status_code == 200
    original = current.json()["name"]
    renamed = client.patch(
        "/api/v1/station",
        headers=headers,
        json={"name": "محطة الاختبار"},
    )
    assert renamed.status_code == 200
    assert renamed.json()["name"] == "محطة الاختبار"
    client.patch("/api/v1/station", headers=headers, json={"name": original})


def test_missing_token_is_rejected(client):
    response = client.get("/api/v1/station")
    assert response.status_code == 401
    assert response.json()["code"] == "NOT_AUTHENTICATED"


def test_refresh_rotates_and_old_token_cannot_be_reused(client):
    first = login(client, "operator", "Operator@12345")
    refreshed = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": first["refresh_token"]},
    )
    assert refreshed.status_code == 200
    second = refreshed.json()
    assert second["access_token"] != first["access_token"]
    reused = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": first["refresh_token"]},
    )
    assert reused.status_code == 401
    assert reused.json()["code"] == "INVALID_REFRESH"


def test_logout_revokes_refresh_token(client):
    tokens = login(client, "manager", "Manager@12345")
    gone = client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert gone.status_code == 204
    still = client.get("/api/v1/auth/me", headers=auth_header(tokens["access_token"]))
    assert still.status_code == 401
    again = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert again.status_code == 401


def test_inactive_user_cannotlogin(client):
    with Session(engine) as session:
        user = session.exec(select(User).where(User.username == "operator")).one()
        user.is_active = False
        session.add(user)
        session.commit()
    try:
        response = client.post(
            "/api/v1/auth/login",
            json={"username": "operator", "password": "Operator@12345", "remember_me": False},
        )
        assert response.status_code == 403
        assert response.json()["code"] == "ACCOUNT_INACTIVE"
    finally:
        with Session(engine) as session:
            user = session.exec(select(User).where(User.username == "operator")).one()
            user.is_active = True
            session.add(user)
            session.commit()


def test_lockout_after_repeated_failures(client):
    username = "lock-probe"
    with Session(engine) as session:
        from core.security import hash_password
        from users.models import Role

        template = session.exec(select(User).where(User.username == "operator")).one()
        role = session.exec(select(Role).where(Role.code == "operator")).one()
        session.add(
            User(
                station_id=template.station_id,
                role_id=role.id,
                employee_code="EMP-LOCK",
                full_name="حساب القفل",
                username=username,
                password_hash=hash_password("LockProbe@123"),
                job_title="اختبار",
            )
        )
        session.commit()
    try:
        for _ in range(5):
            failed = client.post(
                "/api/v1/auth/login",
                json={"username": username, "password": "nope-nope", "remember_me": False},
            )
            assert failed.status_code == 401
        locked = client.post(
            "/api/v1/auth/login",
            json={"username": username, "password": "LockProbe@123", "remember_me": False},
        )
        assert locked.status_code == 423
        assert locked.json()["code"] == "ACCOUNT_LOCKED"
    finally:
        with Session(engine) as session:
            user = session.exec(select(User).where(User.username == username)).one()
            session.delete(user)
            session.commit()


def test_change_password_then_old_password_fails(client):
    tokens = login(client, "operator", "Operator@12345")
    changed = client.post(
        "/api/v1/auth/change-password",
        headers=auth_header(tokens["access_token"]),
        json={"current_password": "Operator@12345", "new_password": "Operator@99999"},
    )
    assert changed.status_code == 204
    old = client.post(
        "/api/v1/auth/login",
        json={"username": "operator", "password": "Operator@12345", "remember_me": False},
    )
    assert old.status_code == 401
    restored_login = client.post(
        "/api/v1/auth/login",
        json={"username": "operator", "password": "Operator@99999", "remember_me": False},
    )
    assert restored_login.status_code == 200
    client.post(
        "/api/v1/auth/change-password",
        headers=auth_header(restored_login.json()["access_token"]),
        json={"current_password": "Operator@99999", "new_password": "Operator@12345"},
    )
