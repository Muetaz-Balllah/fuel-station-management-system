from fastapi.testclient import TestClient


def login(client: TestClient, username: str, password: str, remember_me: bool = False) -> dict:
    response = client.post(
        "/api/v1/auth/login",
        json={"username": username, "password": password, "remember_me": remember_me},
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def ensure_shift_template(
    client: TestClient,
    token: str,
    *,
    name_ar: str = "صباحية",
    starts_at: str = "08:00",
    ends_at: str = "23:59",
) -> dict:
    listed = client.get("/api/v1/shift-templates", headers=auth_header(token))
    assert listed.status_code == 200, listed.text
    items = listed.json()["items"]
    found = next((item for item in items if item["name_ar"] == name_ar), None)
    if found is not None:
        return found
    created = client.post(
        "/api/v1/shift-templates",
        headers=auth_header(token),
        json={
            "name_ar": name_ar,
            "starts_at": starts_at,
            "ends_at": ends_at,
            "grace_minutes": 10,
            "is_active": True,
        },
    )
    assert created.status_code == 201, created.text
    return created.json()
