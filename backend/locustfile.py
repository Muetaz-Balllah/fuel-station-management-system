"""Load test against the running API. Reads only, after one login per user.

From the backend folder, with the API already on port 8000:

    .\\.venv\\Scripts\\python.exe -m locust -f locustfile.py --host http://127.0.0.1:8000

Then open http://127.0.0.1:8089 and start 15 users at a spawn rate of 3.
Keep the run under ten minutes: the access token lasts fifteen.
"""

from __future__ import annotations

import os
from datetime import date

from locust import HttpUser, between, task

MANAGER_USERNAME = os.environ.get("LOCUST_MANAGER_USER", "manager")
MANAGER_PASSWORD = os.environ.get("LOCUST_MANAGER_PASSWORD", "Manager@12345")
OPERATOR_USERNAME = os.environ.get("LOCUST_OPERATOR_USER", "operator")
OPERATOR_PASSWORD = os.environ.get("LOCUST_OPERATOR_PASSWORD", "Operator@12345")


class _ApiUser(HttpUser):
    abstract = True
    wait_time = between(1, 2)
    username = ""
    password = ""

    def on_start(self) -> None:
        today = date.today().isoformat()
        self.today = today
        with self.client.post(
            "/api/v1/auth/login",
            json={"username": self.username, "password": self.password, "remember_me": False},
            name="POST /auth/login",
            catch_response=True,
        ) as response:
            if response.status_code != 200:
                response.failure(f"login failed ({response.status_code})")
                self.environment.runner.quit()
                return
            response.success()
            token = response.json()["access_token"]
        self.client.headers["Authorization"] = f"Bearer {token}"

    def _get(self, path: str, name: str) -> None:
        self.client.get(path, name=name)


class ManagerUser(_ApiUser):
    """Manager browsing the screens used in daily work."""

    weight = 3
    username = MANAGER_USERNAME
    password = MANAGER_PASSWORD

    @task(5)
    def dashboard(self) -> None:
        self._get(f"/api/v1/dashboard?date={self.today}", "GET /dashboard")
        self._get("/api/v1/notifications", "GET /notifications")

    @task(4)
    def assets(self) -> None:
        self._get("/api/v1/assets/board", "GET /assets/board")
        self._get("/api/v1/tanks", "GET /tanks")
        self._get("/api/v1/inventory/events?limit=8&offset=0", "GET /inventory/events")

    @task(3)
    def attendance(self) -> None:
        self._get(f"/api/v1/attendance/summary?date={self.today}", "GET /attendance/summary")
        self._get(f"/api/v1/sessions?date={self.today}", "GET /sessions")
        self._get(
            f"/api/v1/duties/by-date?date={self.today}&page=1&page_size=10",
            "GET /duties/by-date",
        )

    @task(2)
    def supply(self) -> None:
        self._get("/api/v1/supply/summary", "GET /supply/summary")
        self._get("/api/v1/suppliers", "GET /suppliers")
        self._get("/api/v1/supply-orders?page=1&page_size=10", "GET /supply-orders")

    @task(2)
    def settings(self) -> None:
        self._get("/api/v1/station", "GET /station")
        self._get("/api/v1/users?limit=20&offset=0", "GET /users")
        self._get("/api/v1/products", "GET /products")
        self._get("/api/v1/system/clock", "GET /system/clock")

    @task(1)
    def health(self) -> None:
        self._get("/api/v1/health", "GET /health")


class OperatorUser(_ApiUser):
    """Operator opening the shift screens."""

    weight = 2
    username = OPERATOR_USERNAME
    password = OPERATOR_PASSWORD

    @task(5)
    def assignment(self) -> None:
        self._get("/api/v1/me/assignment", "GET /me/assignment")
        self._get("/api/v1/me/duties?page=1&page_size=10", "GET /me/duties")

    @task(2)
    def notifications(self) -> None:
        self._get("/api/v1/notifications", "GET /notifications")
        self._get("/api/v1/system/clock", "GET /system/clock")
        self._get("/api/v1/auth/me", "GET /auth/me")
