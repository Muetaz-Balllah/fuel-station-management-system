from fastapi.testclient import TestClient

from main import app
from tests.helpers import auth_header, ensure_shift_template, login


def client_app():
    with TestClient(app) as test_client:
        yield test_client


import pytest


@pytest.fixture()
def client():
    yield from client_app()


def _manager(client) -> tuple[str, str]:
    body = login(client, "manager", "Manager@12345")
    return body["access_token"], body["user"]["id"]


def _login(client, username: str) -> str:
    return login(client, username, "Staff@12345")["access_token"]


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


def _gasoline(client, token: str) -> str:
    products = client.get("/api/v1/products", headers=auth_header(token)).json()["items"]
    return next(item["id"] for item in products if item["code"] == "G95")


def _session(client, token: str, day: str, name: str = "صباحية") -> dict:
    template = ensure_shift_template(client, token, name_ar=name)
    opened = client.post(
        "/api/v1/sessions",
        headers=auth_header(token),
        json={"template_id": template["id"], "business_date": day},
    )
    assert opened.status_code == 201, opened.text
    return opened.json()


def _assign(client, token: str, shift_id: str, user_id: str, nozzle_ids: list[str], status: str | None = None, note: str | None = None):
    body = {"user_id": user_id, "nozzle_ids": nozzle_ids, "check_in_at": "08:00"}
    if status == "absent":
        body = {"user_id": user_id, "nozzle_ids": [], "status": "absent", "note": note or "غياب"}
    created = client.post(
        f"/api/v1/sessions/{shift_id}/attendance",
        headers=auth_header(token),
        json=body,
    )
    assert created.status_code == 201, created.text
    return created.json()


def _yard(client, token: str, code: str, meters: list[str], stock: str = "10000.000", capacity: str = "50000.000"):
    tank = client.post(
        "/api/v1/tanks",
        headers=auth_header(token),
        json={"name": code, "product_id": _gasoline(client, token), "capacity_liters": capacity},
    )
    assert tank.status_code == 201, tank.text
    tank_id = tank.json()["id"]
    adjusted = client.post(
        f"/api/v1/tanks/{tank_id}/adjustments",
        headers=auth_header(token),
        json={"liters_delta": stock, "note": "رصيد اختبار الوردية"},
    )
    assert adjusted.status_code == 201, adjusted.text
    pump = client.post(
        "/api/v1/pumps",
        headers=auth_header(token),
        json={"code": code, "tank_id": tank_id},
    )
    assert pump.status_code == 201, pump.text
    pump_id = pump.json()["id"]
    nozzles = []
    for index, meter in enumerate(meters, start=1):
        created = client.post(
            f"/api/v1/pumps/{pump_id}/nozzles",
            headers=auth_header(token),
            json={"code": f"N{index}", "label": "يمين" if index == 1 else "يسار", "initial_meter": meter},
        )
        assert created.status_code == 201, created.text
        nozzles.append(created.json())
    return {"tank_id": tank_id, "pump_id": pump_id, "nozzles": nozzles}


def _tank_liters(client, token: str, tank_id: str) -> str:
    items = client.get("/api/v1/tanks", headers=auth_header(token)).json()["items"]
    return next(item["current_liters"] for item in items if item["id"] == tank_id)


def _open(client, token: str, shift_id: str, nozzles: list[dict], reason: str | None = None):
    return client.post(
        "/api/v1/duties/open",
        headers=auth_header(token),
        json={
            "session_id": shift_id,
            "reason": reason,
            "nozzles": [
                {"nozzle_id": item["id"], "opening_meter": item["current_meter"]}
                for item in nozzles
            ],
        },
    )


def test_close_matches_to_the_cent_and_approval_moves_the_tank(client):
    token, _manager_id = _manager(client)
    yard = _yard(client, token, "PUMP-CASH", ["1841200.000", "1621075.000"])
    operator_id = _user(client, token, "محمد الوردية", "duty.mohammed")
    shift = _session(client, token, "2026-11-02")
    nozzles = yard["nozzles"]
    _assign(client, token, shift["id"], operator_id, [item["id"] for item in nozzles])
    operator = _login(client, "duty.mohammed")
    opened = _open(client, operator, shift["id"], nozzles)
    assert opened.status_code == 201, opened.text
    duty_id = opened.json()["id"]
    assert _tank_liters(client, token, yard["tank_id"]) == "10000.000"
    closed = client.post(
        f"/api/v1/duties/{duty_id}/close",
        headers=auth_header(operator),
        json={
            "cash_handed": "642.00",
            "lines": [
                {"nozzle_id": nozzles[0]["id"], "closing_meter": "1843450.000"},
                {"nozzle_id": nozzles[1]["id"], "closing_meter": "1623105.000"},
            ],
        },
    )
    assert closed.status_code == 200, closed.text
    body = closed.json()
    assert body["liters"] == "4280.000"
    assert body["expected_cash"] == "642.00"
    assert body["variance"] == "0.00"
    assert body["variance_kind"] == "match"
    assert body["status"] == "pending_approval"
    assert _tank_liters(client, token, yard["tank_id"]) == "10000.000"
    board = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    card = next(item for item in board["cards"] if item["pump"]["code"] == "PUMP-CASH")
    meters = {item["code"]: item["current_meter"] for item in card["nozzles"]}
    assert meters["N1"] == "1841200.000"
    assert meters["N2"] == "1621075.000"
    approved = client.post(f"/api/v1/duties/{duty_id}/approve", headers=auth_header(token))
    assert approved.status_code == 200, approved.text
    assert approved.json()["approved_by_name"] == "أحمد المصراتي"
    assert _tank_liters(client, token, yard["tank_id"]) == "5720.000"
    board = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    card = next(item for item in board["cards"] if item["pump"]["code"] == "PUMP-CASH")
    meters = {item["code"]: item["current_meter"] for item in card["nozzles"]}
    assert meters["N1"] == "1843450.000"
    assert meters["N2"] == "1623105.000"
    history = client.get("/api/v1/me/duties", headers=auth_header(operator)).json()["items"]
    row = next(item for item in history if item["id"] == duty_id)
    assert row["liters"] == "4280.000"
    assert row["expected_cash"] == "642.00"
    assert row["cash_handed"] == "642.00"
    assert row["variance"] == "0.00"
    assert row["approved_by_name"] == "أحمد المصراتي"
    log = client.get("/api/v1/shift-log?date_from=2026-11-02&date_to=2026-11-02", headers=auth_header(token))
    assert log.status_code == 200
    entry = next(item for item in log.json()["items"] if item["id"] == shift["id"])
    assert entry["revenue"] == "642.00"
    assert entry["status_label"] == "معتمدة ومغلقة"
    denied = client.get("/api/v1/shift-log", headers=auth_header(operator))
    assert denied.status_code == 403


def test_shortage_surplus_reject_and_tank_short(client):
    token, _ = _manager(client)
    yard = _yard(client, token, "PUMP-VAR", ["1841200.000", "1621075.000"], stock="100.000", capacity="5000.000")
    operator_id = _user(client, token, "خالد العهدة", "duty.khaled")
    shift = _session(client, token, "2026-11-03")
    nozzles = yard["nozzles"]
    _assign(client, token, shift["id"], operator_id, [item["id"] for item in nozzles])
    operator = _login(client, "duty.khaled")
    opened = _open(client, operator, shift["id"], nozzles)
    assert opened.status_code == 201, opened.text
    duty_id = opened.json()["id"]
    short = client.post(
        f"/api/v1/duties/{duty_id}/close",
        headers=auth_header(operator),
        json={
            "cash_handed": "637.00",
            "lines": [
                {"nozzle_id": nozzles[0]["id"], "closing_meter": "1843450.000"},
                {"nozzle_id": nozzles[1]["id"], "closing_meter": "1623105.000"},
            ],
        },
    )
    assert short.status_code == 200, short.text
    assert short.json()["variance"] == "-5.00"
    assert short.json()["variance_kind"] == "shortage"
    rejected = client.post(
        f"/api/v1/duties/{duty_id}/reject",
        headers=auth_header(token),
        json={"reason": "راجع الصندوق"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["status"] == "rejected"
    assert _tank_liters(client, token, yard["tank_id"]) == "100.000"
    again = client.post(
        f"/api/v1/duties/{duty_id}/close",
        headers=auth_header(operator),
        json={
            "cash_handed": "647.00",
            "lines": [
                {"nozzle_id": nozzles[0]["id"], "closing_meter": "1843450.000"},
                {"nozzle_id": nozzles[1]["id"], "closing_meter": "1623105.000"},
            ],
        },
    )
    assert again.status_code == 200, again.text
    assert again.json()["variance"] == "5.00"
    assert again.json()["variance_kind"] == "surplus"
    blocked = client.post(f"/api/v1/duties/{duty_id}/approve", headers=auth_header(token))
    assert blocked.status_code == 409
    assert blocked.json()["code"] == "TANK_SHORT"
    assert _tank_liters(client, token, yard["tank_id"]) == "100.000"
    still = client.get(f"/api/v1/duties/{duty_id}", headers=auth_header(operator)).json()
    assert still["status"] == "pending_approval"
    board = client.get("/api/v1/assets/board", headers=auth_header(token)).json()
    card = next(item for item in board["cards"] if item["pump"]["code"] == "PUMP-VAR")
    assert {item["code"]: item["current_meter"] for item in card["nozzles"]}["N1"] == "1841200.000"


def test_absent_and_foreign_nozzle_cannot_open(client):
    token, _ = _manager(client)
    yard = _yard(client, token, "PUMP-BLOCK", ["1000.000"])
    present_id = _user(client, token, "سالم الحاضر", "duty.present")
    absent_id = _user(client, token, "سالم الغائب", "duty.absent")
    shift = _session(client, token, "2026-11-04")
    nozzle = yard["nozzles"][0]
    _assign(client, token, shift["id"], present_id, [nozzle["id"]])
    _assign(client, token, shift["id"], absent_id, [], status="absent", note="بدون عذر")
    absent = _login(client, "duty.absent")
    blocked = _open(client, absent, shift["id"], [nozzle])
    assert blocked.status_code == 409
    assert blocked.json()["code"] == "ATTENDANCE_BLOCKED"
    present = _login(client, "duty.present")
    other = _yard(client, token, "PUMP-OTHER", ["50.000"])
    foreign = _open(client, present, shift["id"], other["nozzles"])
    assert foreign.status_code == 201, foreign.text
    assert foreign.json()["status"] == "open"


def test_meter_edit_is_allowed_for_operator_and_manager_and_stays_visible(client):
    token, manager_id = _manager(client)
    yard = _yard(client, token, "PUMP-METER", ["5000.000"])
    operator_id = _user(client, token, "فني العداد", "duty.meter")
    shift = _session(client, token, "2026-11-05")
    nozzle = yard["nozzles"][0]
    _assign(client, token, shift["id"], operator_id, [nozzle["id"]])
    operator = _login(client, "duty.meter")
    missing = client.post(
        "/api/v1/duties/open",
        headers=auth_header(operator),
        json={
            "session_id": shift["id"],
            "nozzles": [{"nozzle_id": nozzle["id"], "opening_meter": "5001.000"}],
        },
    )
    assert missing.status_code == 422
    assert missing.json()["code"] == "REASON_REQUIRED"
    opened = client.post(
        "/api/v1/duties/open",
        headers=auth_header(operator),
        json={
            "session_id": shift["id"],
            "reason": "العداد على المضخة يختلف عن آخر إغلاق",
            "nozzles": [{"nozzle_id": nozzle["id"], "opening_meter": "5001.000"}],
        },
    )
    assert opened.status_code == 201, opened.text
    line = opened.json()["lines"][0]
    assert line["opening_meter"] == "5001.000"
    assert line["meter_adjusted"] is True
    assert line["previous_meter"] == "5000.000"
    assert line["meter_reason"] == "العداد على المضخة يختلف عن آخر إغلاق"
    assert opened.json()["meter_adjustments"][0]["actor_name"] == "فني العداد"
    manager_yard = _yard(client, token, "PUMP-OVR", ["8000.000"])
    manager_shift = _session(client, token, "2026-11-06")
    manager_nozzle = manager_yard["nozzles"][0]
    _assign(client, token, manager_shift["id"], manager_id, [manager_nozzle["id"]])
    accepted = client.post(
        "/api/v1/duties/open",
        headers=auth_header(token),
        json={
            "session_id": manager_shift["id"],
            "reason": "تصحيح بعد صيانة العداد",
            "nozzles": [{"nozzle_id": manager_nozzle["id"], "opening_meter": "8005.000"}],
        },
    )
    assert accepted.status_code == 201, accepted.text
    duty_id = accepted.json()["id"]
    closed = client.post(
        f"/api/v1/duties/{duty_id}/close",
        headers=auth_header(token),
        json={
            "cash_handed": "1.50",
            "lines": [{"nozzle_id": manager_nozzle["id"], "closing_meter": "8015.000"}],
        },
    )
    assert closed.status_code == 200, closed.text
    pending = client.get(f"/api/v1/duties/{duty_id}", headers=auth_header(token)).json()
    assert pending["status"] == "pending_approval"
    assert pending["lines"][0]["meter_adjusted"] is True
    assert pending["lines"][0]["previous_meter"] == "8000.000"
    assert pending["expected_cash"] == "1.50"


def test_price_change_after_open_does_not_touch_the_duty(client):
    token, _ = _manager(client)
    yard = _yard(client, token, "PUMP-PRICE", ["100.000"])
    operator_id = _user(client, token, "موظف السعر", "duty.price")
    shift = _session(client, token, "2026-11-07")
    nozzle = yard["nozzles"][0]
    _assign(client, token, shift["id"], operator_id, [nozzle["id"]])
    operator = _login(client, "duty.price")
    opened = _open(client, operator, shift["id"], [nozzle])
    assert opened.status_code == 201, opened.text
    product_id = _gasoline(client, token)
    posted = client.post(
        f"/api/v1/products/{product_id}/prices",
        headers=auth_header(token),
        json={"price_per_liter": "0.200"},
    )
    assert posted.status_code == 201, posted.text
    closed = client.post(
        f"/api/v1/duties/{opened.json()['id']}/close",
        headers=auth_header(operator),
        json={"cash_handed": "15.00", "lines": [{"nozzle_id": nozzle["id"], "closing_meter": "200.000"}]},
    )
    assert closed.status_code == 200, closed.text
    assert closed.json()["lines"][0]["unit_price"] == "0.150"
    assert closed.json()["expected_cash"] == "15.00"
    restored = client.post(
        f"/api/v1/products/{product_id}/prices",
        headers=auth_header(token),
        json={"price_per_liter": "0.150"},
    )
    assert restored.status_code == 201, restored.text


def test_two_operators_cannot_open_the_same_nozzle(client):
    token, _ = _manager(client)
    yard = _yard(client, token, "PUMP-BUSY", ["3000.000"])
    first_id = _user(client, token, "الأول", "duty.first")
    second_id = _user(client, token, "الثاني", "duty.second")
    morning = _session(client, token, "2026-11-08", "صباحية")
    evening = _session(client, token, "2026-11-08", "مسائية")
    nozzle = yard["nozzles"][0]
    _assign(client, token, morning["id"], first_id, [nozzle["id"]])
    _assign(client, token, evening["id"], second_id, [nozzle["id"]], )
    first = _login(client, "duty.first")
    second = _login(client, "duty.second")
    opened = _open(client, first, morning["id"], [nozzle])
    assert opened.status_code == 201, opened.text
    busy = _open(client, second, evening["id"], [nozzle])
    assert busy.status_code == 409
    assert busy.json()["code"] == "NOZZLE_BUSY"


def test_operator_cannot_approve(client):
    token, _ = _manager(client)
    yard = _yard(client, token, "PUMP-PERM", ["10.000"])
    operator_id = _user(client, token, "بدون اعتماد", "duty.perm")
    shift = _session(client, token, "2026-11-09")
    _assign(client, token, shift["id"], operator_id, [yard["nozzles"][0]["id"]])
    operator = _login(client, "duty.perm")
    opened = _open(client, operator, shift["id"], yard["nozzles"])
    assert opened.status_code == 201, opened.text
    denied = client.post(f"/api/v1/duties/{opened.json()['id']}/approve", headers=auth_header(operator))
    assert denied.status_code == 403


def test_operator_opens_a_shift_without_a_prior_assignment(client):
    token, _ = _manager(client)
    yard = _yard(client, token, "PUMP-FREE", ["900.000"])
    _user(client, token, "فني حر", "duty.free")
    shift = _session(client, token, "2026-11-12")
    operator = _login(client, "duty.free")
    opened = _open(client, operator, shift["id"], yard["nozzles"])
    assert opened.status_code == 201, opened.text
    body = opened.json()
    assert body["full_name"] == "فني حر"
    assert body["taken_over"] is False
    rows = client.get(f"/api/v1/sessions/{shift['id']}/attendance", headers=auth_header(token)).json()["items"]
    assert rows[0]["note"] == "فتح الموظف الوردية بنفسه"
    assert rows[0]["assignments"]


def test_operator_takeover_is_visible_to_the_manager(client):
    token, _ = _manager(client)
    yard = _yard(client, token, "PUMP-TAKE", ["4000.000"])
    rostered_id = _user(client, token, "سالم المكلّف", "duty.roster")
    taker_id = _user(client, token, "ليلى المناوبة", "duty.taker")
    shift = _session(client, token, "2026-11-13")
    nozzle = yard["nozzles"][0]
    _assign(client, token, shift["id"], rostered_id, [nozzle["id"]])
    taker = _login(client, "duty.taker")
    opened = _open(client, taker, shift["id"], [nozzle])
    assert opened.status_code == 201, opened.text
    body = opened.json()
    assert body["full_name"] == "ليلى المناوبة"
    assert body["rostered_name"] == "سالم المكلّف"
    assert body["taken_over"] is True
    rows = client.get(f"/api/v1/sessions/{shift['id']}/attendance", headers=auth_header(token)).json()["items"]
    taker_row = next(item for item in rows if item["user_id"] == taker_id)
    assert "سالم المكلّف" in (taker_row["note"] or "")
    log = client.get("/api/v1/shift-log?date_from=2026-11-13&date_to=2026-11-13", headers=auth_header(token))
    assert log.status_code == 200
    assert "ليلى المناوبة بدل سالم المكلّف" in log.json()["items"][0]["operators"]
