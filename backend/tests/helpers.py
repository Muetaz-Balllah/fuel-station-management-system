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
