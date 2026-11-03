# Fuel Station Management System

Development plan and technical specification. Version 1.0.

Stack: FastAPI + PostgreSQL (SQLModel) and a Flutter app for station managers and pump operators. The app is Arabic, right-to-left, and covers one station in v1. The schema still carries `station_id` so a second site does not require a redesign.

This plan is a sequence of **vertical phases**. Each phase ships one feature from the database through the API to the Flutter screen, and it is not started until the previous phase’s exit checks pass. There is no “finish the backend, then build the UI” stage.

Screen reference (source of truth for layout):

| File | Screen | Who uses it |
| --- | --- | --- |
| `design/phots/code1.html` | Login | Everyone |
| `design/phots/code2.html` | Manager dashboard | Manager |
| `design/phots/code3.html` | Tanks, pumps, nozzles | Manager |
| `design/phots/code4.html` | Suppliers and supply orders | Manager |
| `design/phots/code5.html` | Attendance and nozzle assignment | Manager |
| `design/phots/code6.html` | Station settings, users, roles | Manager |
| `design/phots/code7.html` | Operator shift, desktop | Operator |
| `design/phots/code8.html` | Operator shift, phone | Operator |

`code6.html` shows a fourth tab, **إعدادات الورديات ومواعيد المناوبات**, with no panel behind it. Section 6 specifies that panel. `code4.html` creates an order without a destination tank. This spec requires a tank, because a received order has to credit a real tank.

---

## 1. Decisions locked by the designs

These are product rules, not suggestions. Later phases must not reopen them.

**One tank belongs to one pump.** The tanks screen says each pump is fed by a dedicated tank and that the tank is not shared. `pumps.tank_id` is unique. A tank may exist briefly before a pump is attached. A pump cannot be saved without its tank. Nozzles hang off the pump and inherit the tank’s fuel product. The “add nozzle” dialog shows pump and fuel as read-only.

**The nozzle totalizer is the meter.** The tanks screen stores a cumulative liter reading on each nozzle (`عداد: 680,150 L`). The operator mockups draw one number per pump. That is the simple case of the same rule: the close form lists every nozzle on the assigned pumps, grouped under the pump name. A pump with two nozzles shows two inputs.

**There is no live sensor feed in v1.** “Real-time” on the tanks screen means the page refetches from the API while it is open, and consumption is computed from approved shift readings (liters today, and liters on the current open duties). Pump controllers, ATG probes, and websockets are out of scope.

**Cash is settled per employee, then rolled up per shift window.** An operator hands over one cash amount for their own duty. The dashboard row is the station shift (morning 08:00–16:00, evening 16:00–00:00): summed liters, summed revenue, summed variance, one supervisor.

**Variance is cash minus what the meters say, in Libyan dinar.**

```
liters        = closing_meter − opening_meter          (per nozzle)
line_amount   = liters × price_of_that_product         (price frozen at open)
expected_cash = sum of line amounts
variance      = cash_handed_over − expected_cash
```

- `variance == 0` → مطابق
- `variance > 0` → فائض (زيادة)
- `variance < 0` → عجز

Worked example from the operator screen, used as a permanent test fixture:

- Nozzle A: 1,843,450.0 − 1,841,200.0 = 2,250.0 L
- Nozzle B: 1,623,105.0 − 1,621,075.0 = 2,030.0 L
- Total 4,280.0 L × 0.150 د.ل = 642.00 د.ل
- Cash 642.00 → variance 0.00
- A second fixture: expected 1,218.00, cash 1,223.00 → فائض +5.00

Prices are per product. The single “0.150 د.ل / لتر” line is shown only when every nozzle on the duty sells the same product at the same price. Mixed gasoline and diesel show one line per product. The phone mock labels pump 02 as diesel while still using one price; the desktop mock labels both pumps as gasoline 95. The engine follows the desktop fixture. The phone layout still has to support mixed products.

**A submitted close waits for the supervisor.** After the operator confirms, the duty is “بانتظار توقيع المشرف”. Meters and tank volume change only when a manager approves. Reject returns the duty to the operator and changes nothing in the tank.

**Inventory is a ledger.** `tanks.current_liters` is a cache. Every change is an `inventory_movements` row inside the same database transaction. Approved sales subtract. Received orders add. Managers may post an adjustment with a reason. Nothing in the ledger is deleted. A mistake is a reversing movement.

**Attendance is assignment plus presence.** The attendance table’s main column is the field posting: pump and nozzle, side, product. Status is حاضر, متأخر, or غائب. Late means check-in after the shift start plus that template’s grace minutes (default 10).

**Two roles ship in the product.** Day-to-day use is the station manager and the pump operator. v1 seeds `station_manager` and `operator`. A maintenance flag on the user can mark فني صيانة in the user list without a third role. The manager cannot delete financial records. Nobody hard-deletes them.

**Login is username and password issued by the manager.** “نسيت كلمة المرور؟” tells the user to ask the station manager. The manager resets the password from user management. v1 does not send mail.

**Locale and money.** Arabic RTL, IBM Plex Sans (Arabic cut for body), JetBrains Mono for meters, liters, money, and codes. Currency is د.ل with 2 decimal places. Liters and meter readings use 3 decimal places. Store both as `NUMERIC`, never as float.

**Visual language, taken from the mockups.** Navy `#041539` on the sidebar and primary buttons. Page background `#f9f9ff`. Orange `#f56600` for the persistent “طلب تزويد جديد” action and for warning states. Error `#ba1a1a`. Success green for حاضر, جاهز, and a matched shift. Manager chrome is a fixed right sidebar (256px) plus a 64px top bar. The operator phone shell is a top bar plus a 3-item bottom nav: الوردية, السجل, حسابي.

---

## 2. Architecture

```
Flutter (Windows, Android, iOS, tablet)
  Cubit per screen  →  repository  →  Dio  →  HTTPS /api/v1
                                              │
FastAPI                                        │
  router → service (rules, transactions) → SQLModel
                                              │
                                         PostgreSQL
```

The Flutter client may preview liters and variance as the operator types, matching the mockups. The server recomputes every figure and is the only writer. The client replaces its preview with the response.

One FastAPI process. Uvicorn. Pydantic v2 schemas at the edge. Services own transactions. Routers do not calculate money and do not touch the session directly except through a dependency.

Local development uses SQLite (`sqlite:///./fuel_station.db`). PostgreSQL stays available by changing `DATABASE_URL` to `postgresql+psycopg://...`; the models and services do not change. Redis is required for access-token sessions: each JWT id is an allow-list key, and logout, password change, deactivation, and role edits delete those keys. Refresh tokens remain hashed rows in the database. Tests use an in-memory SQLite database and `REDIS_URL=memory`.

Volumes and money use `Decimal` end to end (`NUMERIC` in Postgres, `decimal` in Python, string on the wire so JSON does not turn 642.00 into a binary float). The Flutter models parse those strings into `Decimal` (package `decimal`).

### Request rules

- Base path `/api/v1`.
- Auth header `Authorization: Bearer <access>`.
- Access token lifetime 15 minutes. Refresh token 7 days, 30 days when “تذكرني” is checked.
- Passwords hashed with bcrypt.
- List endpoints accept `limit` (default 20, max 100) and `offset`, and return `{ "items", "total" }`.
- Errors: `{ "code": "METER_REGRESSION", "message": "..." }` with the right HTTP status. `code` is stable for the client. `message` is Arabic.
- Every mutating service writes an `audit_log` row: actor, action, entity, entity id, JSON before/after, timestamp.
- Tank updates take `SELECT … FOR UPDATE` on that tank row.

### Runtime layout

Local development is `docker-compose.yml` with Postgres only, plus a venv for the API and `flutter run` for the client. The API reads `DATABASE_URL`, `JWT_SECRET`, and `ACCESS_TOKEN_MINUTES` from the environment. `.env` is never committed. `.env.example` is.

---

## 3. Repository layout

Adapted from the previous project’s trees (`structure/front.jpg`, `structure/back.png`). Feature folders stay the unit of work. Names follow this product instead of the old student/course modules.

### Backend

```
backend/
  main.py                 # app factory, router mount, CORS
  config.py
  db.py                   # engine, session dependency
  enums.py
  errors.py               # AppError → HTTP
  middleware.py           # request id, access log
  utils.py                # codes, Decimal helpers, time windows
  core/
    security.py           # password, JWT
    deps.py               # current user, permission guard
    pagination.py
  auth/
    routes.py
    schemas.py
    services.py
  users/
    models.py
    routes.py
    schemas.py
    services.py
  stations/               # profile, license, products, prices, shift templates
    models.py
    routes.py
    schemas.py
    services.py
  assets/                 # tanks, pumps, nozzles, inventory ledger
    models.py
    routes.py
    schemas.py
    services.py
  suppliers/
    models.py
    routes.py
    schemas.py
    services.py
  supply_orders/
    models.py
    routes.py
    schemas.py
    services.py
  operations/             # sessions, attendance, duties, readings
    models.py
    schemas.py
    routes.py             # includes both routers
    services/
      sessions.py
      attendance.py
      duties.py
      reconciliation.py   # pure functions, no database
  dashboard/
    routes.py
    schemas.py
    services.py
  notifications/
    models.py
    routes.py
    services.py
  alembic/
  tests/
```

Each package’s `routes.py` exports an `APIRouter`. `main.py` mounts them. `reconciliation.py` has no SQL imports, so the money rules can be unit-tested without a database.

### Flutter

```
frontend/lib/
  main.dart
  app.dart
  core/
    di/                   # get_it registrations
    helpers/              # Decimal format, LYD, liters, Arabic dates
    l10n/                 # app_ar.arb is the default locale
    networking/           # Dio, auth interceptor, error mapping
    routing/              # go_router, role redirect
    theming/              # navy / orange / type scale from the mockups
    widgets/              # sidebar, top bar, metric card, status pill, empty state
  features/
    auth/
    settings/
    assets/
    attendance/
    shifts/               # operator duty + manager shift log
    supply/
    dashboard/
    account/              # operator “حسابي”
  # every feature:
  #   data/apis
  #   data/models
  #   data/repos
  #   logic/cubit
  #   ui/widgets
  #   ui/<name>_screen.dart
```

State is `flutter_bloc` Cubit, one cubit per screen, matching the reference tree. Dependencies are registered in `core/di` with `get_it`. Navigation is `go_router`. HTTP is `Dio`. Tokens live in `flutter_secure_storage`. Charts on the dashboard and attendance page use `fl_chart`.

A feature folder is created in the phase that builds that feature. Do not scaffold empty features ahead of time.

### Navigation

After login the API returns `role` and a permission list. The router sends:

- `station_manager` to the manager shell (right sidebar).
- `operator` to the operator shell.

Manager destinations, in sidebar order from the mockups:

1. `/dashboard` لوحة القيادة
2. `/assets` الخزانات والمضخات
3. `/supply` التوريدات والموردين
4. `/attendance` سجل الحضور والدوام
5. `/settings` إعدادات النظام

The orange button “طلب تزويد جديد” sits at the bottom of the sidebar on every manager page and opens the create-order dialog. Until phase 6 it is hidden, not a dead button.

Logout is on the sidebar footer (`code3` onward).

Operator destinations:

- Wide layout (the desktop mock, `code7`): top bar, no sidebar, shift page with history underneath.
- Narrow layout (the phone mock, `code8`): bottom nav to `/shift`, `/my-shifts`, `/account`.

The manager sidebar collapses to a drawer below 900px width so a tablet is usable. The operator layout switches at 720px.

---

## 4. Database schema

Conventions for every table: `id UUID` primary key, `station_id UUID NOT NULL` (except `stations` itself), `created_at`, `updated_at`. Human codes (`SH-2026-104`, `ORD-9921`, `EMP-0122`, `PUMP-01`, `T-01`) are unique per station and generated in the service.

### Identity and access

**stations**

| Column | Notes |
| --- | --- |
| code | `ST-104` |
| name | محطة طريق المطار - طرابلس |
| license_number | `LY-4492-TPS` |
| license_expires_on | date |
| latitude, longitude | numeric, nullable |
| logo_url | nullable |
| timezone | default `Africa/Tripoli` |

**roles** — `code`, `name_ar`, `is_system` (seeded roles cannot be deleted).

**permissions** — stable string codes. Seed:

`dashboard.view`, `assets.manage`, `supply.manage`, `supply.receive`, `attendance.manage`, `shifts.operate`, `shifts.approve`, `shifts.view_all`, `prices.manage`, `settings.manage`, `users.manage`, `reports.export`, `meter.override`, `inventory.adjust`.

**role_permissions** — role_id, permission_id. Unique pair.

Seed grants:

| Role | Gets | Does not get |
| --- | --- | --- |
| station_manager | all permissions | a hard delete of ledger or approved duties, because that path does not exist |
| operator | `shifts.operate` only | prices, settings, other people’s shifts, supply, assets |

**users**

| Column | Notes |
| --- | --- |
| role_id | |
| employee_code | `EMP-0122` |
| full_name | |
| username | unique per station, this is the login |
| password_hash | |
| job_title | مشرف التعبئة, عامل مضخة, … |
| is_active | false replaces delete |
| is_maintenance | shows as فني صيانة in the user filter |
| last_login_at | |

**refresh_tokens** — user_id, token_hash, expires_at, revoked_at.

### Catalog and shift clock

**fuel_products** — `code` (`G95`, `G98`, `DIESEL`, `KEROSENE`), `name_ar` (بنزين 95, بنزين 98, ديزل, كيروسين), `is_active`.

**fuel_prices** — product_id, price_per_liter `NUMERIC(14,3)`, effective_from `timestamptz`, created_by. The active price is the latest row with `effective_from <= now()`. Old rows stay, so a duty can point at the price it used.

**shift_templates** — name_ar (الوردية الصباحية), starts_at `time`, ends_at `time`, grace_minutes default 10, is_active, sort_order. If `ends_at <= starts_at` the window crosses midnight (16:00–00:00).

### Physical assets

**tanks**

| Column | Notes |
| --- | --- |
| code | `T-01`, `TD-01` |
| name | |
| product_id | |
| capacity_liters | `NUMERIC(14,3)` > 0 |
| current_liters | cache, `>= 0` and `<= capacity` |
| critical_percent | default 15 |
| warning_percent | default 40 |
| is_active | |

Level band is computed, not stored: under `critical_percent` is حرج, under `warning_percent` is تحذير, otherwise مستقر.

**pumps** — code (`PUMP-01`), name, `tank_id UNIQUE`, status `active | maintenance | inactive`. A maintenance pump cannot receive a new assignment.

**nozzles** — pump_id, code (`N1`), label (يمين, يسار, شاحنات ثقيلة), status `ready | valve_check | calibrating | inactive`, current_meter `NUMERIC(16,3)` default 0. Unique `(pump_id, code)`.

**inventory_movements**

| Column | Notes |
| --- | --- |
| tank_id | |
| movement_type | `opening_balance`, `supply_receipt`, `shift_sale`, `adjustment` |
| liters_delta | signed |
| balance_after | |
| source_type, source_id | order or duty or adjustment |
| note | required for adjustment |
| created_by | |

### Supply

**suppliers** — name, headquarters, contact_name, phone, max_daily_liters, is_active. Reliability on the card is computed: received orders / (received + cancelled) over the last 90 days, shown as a percent. It is not a hand-typed score.

**supply_orders**

| Column | Notes |
| --- | --- |
| code | `ORD-9921` |
| supplier_id | |
| tank_id | required, and the tank’s product must match |
| product_id | denormalized from the tank at create time |
| ordered_liters | |
| received_liters | null until receipt |
| status | `pending`, `received`, `cancelled` |
| expected_on | date |
| notes | |
| received_at, received_by | |
| cancelled_at | |

Receipt posts a `supply_receipt` movement and raises `current_liters`. It fails if the tank would exceed capacity.

### The working day

**shift_sessions** — one station window.

| Column | Notes |
| --- | --- |
| code | `SH-2026-104` |
| template_id | |
| business_date | the date the window starts |
| supervisor_id | nullable until someone with `shifts.approve` is set |
| status | `open`, `approved` |
| starts_at, ends_at | absolute timestamps, expanded from the template |

Unique `(station_id, template_id, business_date)`.

**attendances** — one employee inside one session.

| Column | Notes |
| --- | --- |
| session_id, user_id | unique pair |
| check_in_at, check_out_at | nullable |
| status | `assigned`, `present`, `late`, `absent`, `completed` |
| note | عطل فني في السيارة, بدون عذر مسبق, … |
| recorded_by | |

**shift_assignments** — which nozzle that attendance covers.

| Column | Notes |
| --- | --- |
| attendance_id, nozzle_id | unique pair |
| | a nozzle has at most one assignment inside a session |

An operator with two pumps has two assignment rows and one attendance row. The attendance screen groups them. The operator header reads “المضخات المكلّف بها” from these rows.

**shift_duties** — the cash envelope for that employee in that session.

| Column | Notes |
| --- | --- |
| session_id, user_id | unique |
| attendance_id | |
| status | `open`, `pending_approval`, `approved`, `rejected` |
| opened_at, submitted_at, approved_at | |
| approved_by | |
| reject_reason | |
| cash_handed | null until submit |
| expected_cash, variance | null until submit, recomputed on the server |

**shift_readings** — one per nozzle on the duty.

| Column | Notes |
| --- | --- |
| duty_id, nozzle_id | unique |
| opening_meter, closing_meter | closing null while open |
| liters, unit_price, line_amount | null until close |
| price_id | the `fuel_prices` row that was active at open |

**notifications** — user_id nullable (null means every manager), kind (`tank_critical`, `duty_pending`, `license_due`, `order_stale`), title, body, read_at, entity reference.

**audit_log** — actor_id, action, entity, entity_id, before JSON, after JSON, created_at.

### Invariants the database should enforce

- `pumps.tank_id` unique.
- `current_liters` between 0 and capacity.
- Nozzle `(pump_id, code)` unique.
- One attendance per `(session, user)`.
- One assignment per `(session, nozzle)` — enforce with a unique index through the session, or in the service under a lock. Prefer a concrete unique index: store `session_id` on `shift_assignments` as well (denormalized from attendance) and unique `(session_id, nozzle_id)`.
- One duty per `(session, user)`.
- Status checks as Postgres enums or check constraints.

---

## 5. Business rules

### 5.1 Opening a duty

1. There is an attendance row for this user and session, status `present` or `late`. `absent` cannot open.
2. Every nozzle on the duty is one of this user’s assignments, status `ready`, pump not `maintenance`.
3. No other duty in `open` or `pending_approval` holds that nozzle.
4. Opening meter is the nozzle’s `current_meter` (last approved close, or the meter typed when the nozzle was created). The client shows it and may submit it back. If the submitted value differs, respond `409 METER_MISMATCH` unless the caller has `meter.override`.
5. Create the duty `open` and one reading per nozzle. Copy `price_id` and `unit_price` now. Later price edits do not touch this duty.
6. Set attendance check-in if it is still empty.

### 5.2 Closing a duty

The client sends closing meters and `cash_handed`. The server:

1. Rejects a closing meter below opening with `422 METER_REGRESSION`. Rollover is not guessed. A manager with `meter.override` may send `rollover: true` and the nozzle’s configured `meter_rollover_at`. Liters then are `(rollover_at − opening) + closing`. Operators never set this.
2. Runs the pure function in `reconciliation.py`.
3. Stores readings, `expected_cash`, `variance`, `cash_handed`.
4. Sets the duty to `pending_approval`.
5. Notifies users who have `shifts.approve`.
6. Does **not** move the tank or the nozzle meter.

Reject sets `rejected`, keeps the readings for the audit trail, and lets the operator submit again (new close overwrites the pending numbers only while status is `rejected` or, if you prefer a cleaner trail, insert a new submission version — v1 overwrites the rejected duty’s numbers and writes the previous numbers to `audit_log`).

### 5.3 Approving a duty

Inside one transaction:

1. Lock the duty and every involved tank.
2. Re-run reconciliation. If it does not match the stored figures, stop. Do not “fix forward” silently.
3. For each reading, fail with `409 TANK_SHORT` if `liters` is greater than that tank’s `current_liters`.
4. Set `nozzles.current_meter = closing_meter`.
5. Insert `shift_sale` movements (negative) and update `current_liters`.
6. Set duty `approved`, stamp approver.
7. If every duty on the session is `approved` and there is no `open` attendance still expected, set the session `approved`. A session with nobody else assigned can close as soon as its only duties are approved. The dashboard label معتمدة ومغلقة maps to session `approved`. جارية الآن maps to session `open`.

The supervisor name on the dashboard is `shift_sessions.supervisor_id`, falling back to the approver.

### 5.4 Session totals for the dashboard

For a session:

- liters = sum of approved reading liters, plus pending and open readings only in the “today so far” sales card if their close has been submitted. The shift table uses **approved duties only** for revenue and variance, and shows جارية الآن while the session is `open`.
- revenue = sum of approved `expected_cash`.
- variance = sum of approved `variance`.
- Display variance as `0.00 د.ل (مطابق)`, `+15.00 د.ل (فائض)`, or `-25.00 د.ل (عجز)`.

Daily sales on the dashboard are the sum of approved `expected_cash` for sessions whose `business_date` is the selected day. Inventory is the sum of `current_liters`. Staff on duty is the count of attendances today with status `present` or `late` and a null check-out.

The tank alert card picks the active tank with the lowest percent at or under `critical_percent`. If none, hide the alert card. The mock’s “خزان بنزين 95 / أقل من 15%” is this card.

The weekly chart buckets approved revenue by `business_date` for the week that contains the selected day, one series per shift template (morning, evening).

### 5.5 Attendance lateness

When check-in is recorded:

- if `check_in_at <= session.starts_at + grace` → `present`
- else → `late` (the time is shown in the error color, as خالد 08:45 in the mock)

A manager may set `absent` without a check-in. Check-out sets `completed` but does not by itself close the cash duty. Cash close is the operator flow.

Coverage widget: nozzles with a `present` or `late` assignment, over nozzles whose pump is `active`. The mock’s “6 / 8 مسدس نشط” is that fraction.

### 5.6 Supply

Create sets `pending`. Cancel is allowed only from `pending`. Receive:

- caller needs `supply.receive`
- `received_liters` defaults to `ordered_liters` and must be `> 0`
- tank product equals order product
- `current_liters + received_liters <= capacity`
- then status `received`, movement posted

“الكمية الموردة” on the supply page is the sum of `received_liters` for the current calendar month. “اجمالي الطلبات النشطة” is orders not `cancelled` in that month. “قيد الانتظار” is `pending`. “الموردين النشطين” is suppliers with `is_active`.

### 5.7 What the tanks page shows per pump card

From `code3.html`, each card is a pump plus its tank:

- pump code, product name, pump status (نشطة / صيانة)
- tank code, and the badge that the tank is dedicated
- operational band from the tank percent (مستقر / يحتاج صيانة when the pump is in maintenance)
- circular gauge = `current_liters / capacity`
- capacity, available liters, last receipt time, today’s approved liters (معدل السحب اليومي)
- nozzle chips: code, side label, `current_meter`, status (جاهز / فحص الصمام / معايرة عداد)

The reading log under the cards is `inventory_movements` joined to the source duty or order: time, path `pump ← tank ← nozzle`, event type, liters, actor. Filter by product. Paginate.

Adding a tank asks for name, product, capacity. Adding a pump asks for code and an unattached tank. Adding a nozzle asks for code, side, initial meter, status, and shows the parent pump and tank as read-only.

---

## 6. API blueprint

All paths are under `/api/v1`. Auth is required except login and refresh.

### Auth

| Method | Path | Body / result |
| --- | --- | --- |
| POST | `/auth/login` | `username`, `password`, `remember_me` → access, refresh, user, permissions |
| POST | `/auth/refresh` | refresh → new access |
| POST | `/auth/logout` | revokes the refresh token |
| POST | `/auth/change-password` | old, new. Any signed-in user |

### Station, catalog, templates — phase 2

| Method | Path | Permission |
| --- | --- | --- |
| GET, PATCH | `/station` | GET any manager; PATCH `settings.manage` |
| POST | `/station/logo` | multipart, `settings.manage` |
| GET, POST | `/users` | `users.manage` |
| PATCH | `/users/{id}` | includes `is_active`, role, reset password |
| GET | `/roles` | `users.manage` |
| PUT | `/roles/{id}/permissions` | `users.manage` (station manager) |
| GET, POST | `/products` | POST `prices.manage` |
| GET, POST | `/products/{id}/prices` | POST adds a new effective price, does not edit the old row |
| GET, POST, PATCH | `/shift-templates` | `settings.manage` |

`PATCH /station` accepts name, license number, license expiry, coordinates.

The shift-template payload is `{ name_ar, starts_at, ends_at, grace_minutes, is_active }`. The settings tab that the mock only labels, and does not draw, is this list plus an add form. Fields: name, start, end, grace minutes, active switch. Show a hint when the shift crosses midnight.

### Assets — phase 3

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/tanks` | includes percent, band, pump summary |
| POST | `/tanks` | name, product, capacity. `current_liters` starts at 0 |
| PATCH | `/tanks/{id}` | name, thresholds, is_active. Not current liters |
| POST | `/tanks/{id}/adjustments` | `{ liters_delta, note }`, `inventory.adjust` |
| GET, POST | `/pumps` | POST `{ code, tank_id }`. 409 if the tank is taken |
| PATCH | `/pumps/{id}` | status |
| POST | `/pumps/{id}/nozzles` | code, label, initial meter, status. Sets `current_meter` and may post nothing to the tank |
| PATCH | `/nozzles/{id}` | label, status. Meter changes only through duties or `meter.override` |
| GET | `/assets/board` | the card payload for the tanks screen, pumps with tank and nozzles |
| GET | `/inventory/events` | the reading log, filters `product_id`, `date_from`, `date_to` |

### Attendance — phase 4

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/sessions` | `{ template_id, business_date, supervisor_id? }` find-or-create |
| GET | `/sessions` | filter by date |
| GET | `/sessions/{id}/attendance` | rows for the attendance table, assignments nested |
| POST | `/sessions/{id}/attendance` | `{ user_id, nozzle_ids[], check_in_at?, note }` manual register |
| PATCH | `/attendances/{id}` | check-in, check-out, status, note, replace nozzle list |
| GET | `/attendance/summary` | morning completion, nozzle coverage, active template, late count, weekly percents |

Weekly compliance for a weekday is `present + late` over `present + late + absent` for that date.

### Shifts — phase 5

| Method | Path | Who |
| --- | --- | --- |
| GET | `/me/assignment` | operator, today’s assignments and last meters |
| POST | `/duties/open` | `{ session_id, nozzles: [{ nozzle_id, opening_meter }] }` |
| GET | `/duties/{id}` | |
| POST | `/duties/{id}/close` | `{ lines: [{ nozzle_id, closing_meter }], cash_handed }` → server totals |
| POST | `/duties/{id}/approve` | `shifts.approve` |
| POST | `/duties/{id}/reject` | `{ reason }` |
| GET | `/me/duties` | operator history |
| GET | `/sessions/{id}/duties` | manager |
| GET | `/shift-log` | the “سجل كافة الورديات” table, filter by date range and status |

`POST /duties/{id}/close` returns:

```json
{
  "liters": "4280.000",
  "expected_cash": "642.00",
  "cash_handed": "642.00",
  "variance": "0.00",
  "variance_kind": "match",
  "lines": [
    { "nozzle_id": "...", "liters": "2250.000", "unit_price": "0.150", "line_amount": "337.50" }
  ]
}
```

`variance_kind` is `match`, `surplus`, or `shortage`.

### Supply — phase 6

| Method | Path | Notes |
| --- | --- | --- |
| GET, POST, PATCH | `/suppliers` | |
| GET | `/suppliers/{id}` | includes computed reliability and recent orders |
| GET | `/supply/summary` | the four counters and the weekday bar series |
| GET, POST | `/supply-orders` | POST `{ supplier_id, tank_id, ordered_liters, expected_on, notes }` |
| POST | `/supply-orders/{id}/receive` | `{ received_liters? }` |
| POST | `/supply-orders/{id}/cancel` | |

### Dashboard and notifications — phase 7

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/dashboard?date=YYYY-MM-DD` | four cards, chart, tank bars, today’s session table |
| GET | `/dashboard/export?date=` | CSV, `reports.export` |
| GET | `/notifications` | |
| POST | `/notifications/{id}/read` | |

The dashboard service only reads. It does not invent a second way to compute revenue.

---

## 7. Flutter screens

Shared manager widgets, built once and reused:

- `ManagerShell` — sidebar, top bar, connection dot, notification bell, user chip, orange supply button.
- `MetricCard`, `StatusPill`, `DataTable`, `Gauge`, `ConfirmDialog`.
- Formatters: liters `12,500`, money `18,450.00 د.ل`, meter `1,841,200.0`.

### Screen map

| Screen | Design | Cubit | Notes |
| --- | --- | --- | --- |
| Login | code1 | `LoginCubit` | username, password, show/hide, remember me, forgot-password dialog |
| Dashboard | code2 | `DashboardCubit` | date chip, export, 4 cards, weekly bars, tank levels, shift table |
| Assets | code3 | `AssetsCubit` | pump cards, add tank, add pump, add nozzle, event log |
| Supply | code4 | `SupplyCubit` | 4 counters, order table, supplier card, week bars, create-order dialog |
| Attendance | code5 | `AttendanceCubit` | 3 stats, assignment table, manual dialog, week compliance |
| Settings | code6 | `SettingsCubit` | 4 tabs. Shift tab specified in section 6 |
| Operator shift | code7 and code8 | `DutyCubit` | open tab and close tab; live preview; confirm dialog on the phone layout |
| My shifts | code8 history | `MyShiftsCubit` | full list behind “عرض السجل الكامل” |
| Account | code8 “حسابي” | `AccountCubit` | name, employee code, station, logout. No settings |

Operator close form behavior, both layouts:

- Pre-fill opening meters from `GET /me/assignment`.
- On each keystroke, preview liters and variance locally with the same rounding as the server (3 dp liters, 2 dp money, half-up).
- The submit button calls `POST /duties/{id}/close` and then shows the confirm step with the **server** numbers.
- Confirm on the phone mock is the second button (“نعم، اعتماد الإغلاق”). Desktop uses one primary button “اعتماد الإغلاق النهائي وتسليم العهدة”; keep a confirm dialog there too so a mis-tap cannot submit.
- After success the button becomes the disabled state “تم رفع المحضر وانتظار توقيع المشرف”.

Empty states to design, because the mockups only show the happy path:

- Operator with no assignment today.
- Manager dashboard with no sessions.
- Tank at 0 liters.
- Supply table with no orders.
- Login error for a wrong password (inline, under the form, not only a toast).

---

## 8. Vertical phases

Each phase lists the backend work, the Flutter work, and the checks that mean “done”. A check is done only when it has been exercised through the UI against a real API and Postgres, not against fake repositories.

### Phase 1 — Sign-in and the two shells

**Outcome.** A seeded manager and a seeded operator can log in and land in the correct chrome. Nobody else can.

**Backend.** Compose file for Postgres. SQLModel metadata and Alembic baseline: `stations`, `roles`, `permissions`, `role_permissions`, `users`, `refresh_tokens`. Seed station محطة طريق المطار, the three roles, the permission grants in section 4, one manager, one operator. Implement login, refresh, logout, the auth dependency, and `403` when a permission is missing. CORS for the Flutter desktop origin.

**Flutter.** Theme tokens from section 1. `LoginScreen` matching `code1.html`: split brand panel on wide windows, form only on narrow, RTL, password visibility, remember me, forgot-password dialog that says to contact the manager. On success, route by role. Manager shell with sidebar entries that exist so far (home placeholder titled لوحة القيادة, logout). Operator shell with the top bar from `code8.html` / `code7.html` and a placeholder that says no shift is assigned yet. Dio interceptor refreshes the access token once on `401`, then logs out.

**Done when**

- Wrong password shows an inline Arabic error and does not navigate.
- Manager login shows the right-hand sidebar and the manager’s name in the top bar.
- Operator login does not show the manager sidebar.
- Remember me still restores the session after the app restarts; without it, a restart asks for the password again.
- A revoked refresh token cannot mint an access token.
- An operator calling `PATCH /station` receives `403`.
- `pytest` covers login success, login failure, and the permission guard.

### Phase 2 — Station profile, people, prices, and the shift clock

**Outcome.** The settings screen’s four tabs work, and later phases can trust products, prices, users, and templates.

**Backend.** Tables and routes from the phase 2 API list. Price insert is append-only. Password reset sets a new bcrypt hash and revokes that user’s refresh tokens. Role permission edit requires `users.manage`, which the station manager holds. Validation: template grace `0…120`, price `> 0`, username unique.

**Flutter.** `SettingsScreen` from `code6.html`.

- إعدادات المحطة: name, license, renewal date, coordinates, logo upload, save and cancel.
- إدارة المستخدمين: search, role filter (including فني صيانة via `is_maintenance`), add, edit, deactivate. Deactivated rows look muted and can be restored. No hard delete.
- الأدوار والصلاحيات: cards for مدير المحطة and موظف. Toggling a permission calls `PUT` and requires `users.manage`.
- إعدادات الورديات: the panel missing from the HTML. List templates, add and edit name, start, end, grace, active. Seed صباحية 08:00–16:00 and مسائية 16:00–00:00 so the rest of the app has the mock’s clock.

**Done when**

- Editing the license number survives a reload.
- A new operator can log in with the password the manager set, and the old password fails.
- Deactivating a user kills their refresh token.
- Posting a new gasoline price leaves the previous price row in place. `GET` active price returns the new one.
- A shift template that ends at 00:00 stores a next-day end when a session is later expanded.
- The operator account cannot open settings.
- Widget test: the four tabs render, and the shift form rejects an empty name.

### Phase 3 — Tanks, pumps, and nozzles

**Outcome.** The station’s physical layout matches `code3.html`, including the 1:1 tank rule, and the reading log exists (it will be sparse until sales and receipts exist).

**Backend.** Asset tables, movement ledger, board endpoint, event log. Creating a pump fails with `409 TANK_ALREADY_LINKED` if the tank already has a pump. Creating a nozzle on a pump copies nothing from other pumps. Adjustment endpoint posts a signed movement and refuses a balance outside `0…capacity`. Seed, behind a dev flag, the four pump cards from the mock (two gasoline, two diesel) so the screen can be compared to the design. Mark the seed as demo data.

**Flutter.** `AssetsScreen` matching `code3.html`: header, add pump, add tank, the 2-column pump cards, gauge, four stats, nozzle chips, add-nozzle dialog with pump and tank read-only, event table with product filter and pager. Status colors: green جاهز, orange صيانة / فحص الصمام / معايرة. Pull-to-refresh and a 15-second refetch while the route is visible.

**Done when**

- Two pumps cannot be saved against one tank. The UI shows the Arabic error.
- A new nozzle appears on the right pump only, with the typed initial meter.
- An adjustment of `+1000` then `-1000` returns the tank to the prior volume, and both rows are in the event log.
- An adjustment that would exceed capacity is refused and the volume is unchanged.
- Putting a pump in صيانة changes the card band without deleting nozzles.
- The gauge percent equals `current_liters / capacity` rounded to the nearest percent.
- API tests cover the unique tank link and the capacity guard.

### Phase 4 — Attendance and who stands on which nozzle

**Outcome.** A manager can open today’s shift window, assign people to nozzles, and see present, late, and absent the way `code5.html` does.

**Backend.** Sessions, attendances, assignments, summary endpoint. Find-or-create session from template plus date, expanding `starts_at` and `ends_at` in the station timezone, including midnight crossing. Assignment of a nozzle that is already taken in that session returns `409 NOZZLE_TAKEN`. Assignment to a maintenance pump returns `409 PUMP_UNAVAILABLE`. Late versus present uses grace. Summary numbers match section 5.5.

**Flutter.** `AttendanceScreen` from `code5.html`: three stat cards, the assignment table (name, job title, employee code, pump, nozzle chip, side and product subtitle, check-in, check-out, status pill, note, edit), manual-register dialog, export of the visible day to CSV, weekly compliance bars. The safety caption at the bottom can be static text. Date defaults to today.

**Done when**

- Assigning محمد to `PUMP-A1 / N1` and checking him in at 07:55 shows حاضر. The same session with خالد at 08:45 shows متأخر in the error color when the template starts at 08:00 and grace is 10 minutes.
- Marking سالم absent with note “بدون عذر مسبق” shows غائب and does not invent a check-in time.
- A second employee cannot take N1 in that same session.
- Coverage reads assigned-and-present nozzles over active nozzles.
- The weekly bar for a day with 1 absent and 3 present or late reads 75%.
- CSV export contains the same rows as the table.
- Operator still has no cash screen. That is phase 5, and this phase is complete without it.

### Phase 5 — Open a shift, close it, and reconcile the cash

**Outcome.** The operator can run the duty in `code7.html` and `code8.html`. A manager can approve or reject it. Approval is the only thing that moves liters out of the tank and the nozzle meter forward.

**Backend.** Duties, readings, the pure `reconcile()` function, open, close, approve, reject, `GET /me/assignment`, `GET /me/duties`, `GET /shift-log`. Lock tanks on approve. `TANK_SHORT` leaves the duty `pending_approval` and moves no volume. Unit tests for `reconcile()` use the 4,280 L / 642.00 د.ل fixture, the +5.00 surplus fixture, a shortage fixture, and a mixed-price fixture (gasoline 0.150 and diesel 0.150 are allowed to differ).

**Flutter.** `DutyCubit` and both layouts.

- Desktop (`code7`): identity strip, elapsed timer from `opened_at`, open-shift card once the duty is open (read-only, marked معتمد), close form with one meter input per assigned nozzle, three result tiles (liters, expected cash, variance), cash field, submit.
- Phone (`code8`): same data, segmented control “فتح وردية جديدة / إغلاق الوردية”, bottom nav, confirm sheet before the final post.
- History table on the desktop page and the history cards on the phone, backed by `GET /me/duties`. “عرض السجل الكامل” opens the full list.
- Manager `ShiftLogScreen` at `/shifts`, which is the destination of “سجل كافة الورديات”. Columns from the dashboard table: code, window, supervisor, liters, revenue, variance, status. Row tap opens a duty list with اعتماد and رفض. This screen is built now so approval has a home. Phase 7 embeds the same table on the dashboard.

**Done when**

- An operator who is absent, or who was not assigned that nozzle, cannot open. The screen explains why.
- Opening meters that do not match the last close are rejected for an operator and accepted for a manager with a reason.
- Typing the fixture meters and 642.00 shows مطابق before submit, and the stored duty matches to the cent after submit.
- Cash 637.00 on that same duty shows عجز −5.00. Cash 647.00 shows فائض +5.00.
- Before approval, `current_liters` and `current_meter` are unchanged. After approval they move by the sold liters and the closing meter. After reject they stay unchanged and the operator can submit again.
- Approval of a sale larger than the tank fails, the duty stays pending, and the tank is unchanged.
- Two operators cannot open the same nozzle.
- A price change after open does not change that duty’s `unit_price`.
- The operator history shows the approved row with liters, expected cash, cash handed, variance, and the approver’s name.
- `pytest` for `reconcile()` and for the approve transaction. A Flutter unit test runs the same 4,280 L fixture through the preview function.

### Phase 6 — Suppliers and inbound fuel

**Outcome.** The supply screen in `code4.html` works, and receiving an order is what fills a tank.

**Backend.** Suppliers, orders, summary, receive, cancel. Receive uses the same tank lock as shift approval. Reliability is the 90-day ratio from section 5.6. Seed three suppliers named as in the mock: شركة البريقة لتسويق النفط, شركة ليبيا للنفط, شركة الراحلة للخدمات النفطية. Do not seed fake received liters on top of demo tanks unless the seed also writes matching movements.

**Flutter.** `SupplyScreen`: four counters, order table with status chips (قيد الانتظار orange, تم الاستلام navy, ملغي gray), supplier detail card, weekly bars, create dialog. The dialog adds the destination tank dropdown the HTML is missing, and it only lists tanks whose product equals the chosen product. Sidebar orange button opens the same dialog. Receive and cancel actions live on the row. “تحديث بيانات المورد” opens the edit form.

**Done when**

- Creating an order for a diesel quantity against a gasoline tank is impossible in the form and rejected by the API.
- Receiving 15,000 L into a tank raises `current_liters` by 15,000 and the assets page shows the new gauge and “آخر توريد” without a manual refresh of the database.
- Receiving more than the free capacity fails and leaves the order `pending`.
- Cancelling a pending order does not change the tank. Cancelling a received order is rejected.
- The four counters match the database for the current month.
- The supplier card shows headquarters, max daily liters, the computed reliability, and the contact name.
- A received order appears in the assets event log as a receipt, with the manager as the actor.

### Phase 7 — Dashboard, alerts, and a release pass

**Outcome.** The manager home is `code2.html`, filled from real sessions, tanks, and attendance. The bell and the license date do something. The app is fit to hand to a station.

**Backend.** `GET /dashboard` composing the existing services. No copied formulas: revenue, variance, and liters call the same helpers phase 5 uses. CSV export of the day’s session table. Notification rows created when a tank crosses below `critical_percent`, when a duty enters `pending_approval`, when the license expires within 30 days, and when a pending order is older than 3 days. Those writes happen inside the approve, adjust, receive, and close transactions, plus a cheap check on dashboard load for the license and stale orders.

**Flutter.** Replace the phase 1 home placeholder with `DashboardScreen`: greeting, date picker, export, four cards, weekly two-series chart (صباحية / مسائية), tank level list with the link “عرض كافة التفاصيل الفنية” routing to `/assets`, and today’s shift table with “سجل كافة الورديات” routing to `/shifts`. The critical-tank card uses the error palette and is omitted when no tank is critical. Bell dropdown lists notifications and marks them read. Settings shows a renewal warning when the license is inside 30 days.

Release pass, still inside this phase:

- Empty, loading, and error states on every screen built so far.
- Arabic strings live in `app_ar.arb`, including API error codes mapped to sentences.
- Desktop and a 390px-wide phone preview of the operator flow.
- Demo seed script that can rebuild the mock station from an empty database: products, price 0.150 for gasoline 95, templates, tanks, pumps, nozzles, users, one approved session and one open session, one pending Brega order. Document the seed command in `backend/README.md`.
- `pytest` green, and the reconciliation widget test green.

**Done when**

- With the demo seed, the dashboard day shows a revenue total equal to the sum of that day’s approved duties, an inventory total equal to the sum of tank volumes, and a staff count equal to open attendances.
- The shift table’s variance text matches the three formats in section 5.4, including a shortage in red.
- Approving a duty that drives a tank under 15% creates a notification and the alert card appears on the next dashboard load.
- Export downloads a CSV whose revenue column sums to the card.
- An operator token receives `403` on `GET /dashboard`.
- Login → assign → open → close → approve → see the dashboard update, done in one sitting on a fresh seed, without editing the database by hand.

---

## 9. Quality bar that applies to every phase

- Business numbers change in exactly one service function. Screens never update `current_liters` on their own.
- A phase does not add a table it does not display, and does not add a screen it cannot save.
- Backend tests use a transaction rolled back per test, or a dedicated test database. The reconciliation tests do not need a database.
- Flutter models parse money and liters as `Decimal`. Formatting is centralized in `core/helpers`.
- User-facing validation errors are Arabic and name the field.
- Logs do not contain passwords, tokens, or the full cash payload at info level.

## 10. Out of scope for v1

Pump-controller integration, automatic tank gauges, customer invoices, card payments, multi-station switching, email or SMS, PDF reports, and a public self-registration page. The shift log’s CSV export is in scope. PDF is not.

When v1 is in daily use, the next increments in order are: a second station on the existing `station_id`, then a read-only nozzle flow if a controller actually exists, then PDF shift handover sheets.

## 11. Gaps filled in Phase 1

These were missing from the mockups or from the first pass of this plan, and Phase 1 now implements them.

- **Account lockout.** Five failed passwords lock the account for 15 minutes (`users.failed_login_count`, `users.locked_until`). A correct password during the lock still returns `ACCOUNT_LOCKED`.
- **Refresh tokens are opaque and rotated.** The database stores a SHA-256 hash, not the token. Each refresh revokes the presented token and issues a new one. Reusing a revoked token revokes every refresh token for that user.
- **The access token carries identity, not a permission list that the client can trust.** Phase 2 stores that session in Redis. A missing key rejects the token even when the signature is still valid. The user row is still loaded, so a deactivated account fails closed.
- **`users.email` is optional.** The settings mock shows an email column. Login stays username and password. Phase 2 edits this field.
- **Audit rows start with sign-in.** `audit_log` records login success, login failure, lockout, logout, refresh reuse, and password change.
- **`GET /station` is readable by any signed-in user of that station. `PATCH /station` requires `settings.manage`.** That is the real permission check behind the operator `403`, not a hardcoded response.
- **License date on the seed is 31 Dec 2027.** The mock’s 2024-12-31 is already past, and a past date would trip the Phase 7 renewal warning on an empty station.
- **Forgot password, privacy, and help are dialogs.** They tell the operator to ask the manager. No mail is sent.
- **Password change is available from both shells** and revokes refresh tokens, then returns the user to the login screen.
- **Coordinates are floats.** Money and liters stay `Decimal` from Phase 3 onward. Coordinates are not money.
- **The API base URL is `API_BASE_URL`**, default `http://127.0.0.1:8000`. Android emulator builds should pass `http://10.0.2.2:8000`.

## 12. Gaps filled in Phase 2

- **SQLite is the local database.** `db.py` keeps one engine factory. An in-memory URL uses a single shared connection so tests see the seeded rows. A file URL uses a normal pool. A PostgreSQL URL keeps `pool_pre_ping`. No service imports a driver.
- **Redis is the access-token allow-list.** Login writes `jwt:{jti}` with the role and permission codes. `get_current_user` requires that key. Logout deletes the token that belongs to the presented refresh token. Deactivation, password reset, and a role-permission save delete every key for that user.
- **The station manager saves permission changes.** The seeded accounts are the manager and the operator. There is no separate system-admin login.
- **You cannot deactivate your own account.**
- **A manager cannot assign the system-admin role.** Only a system admin can.
- **Fuel prices live on the station settings tab.** The mock has four tabs and no price panel. The official price is station configuration, so it sits under إعدادات المحطة. Old price rows are never updated.
- **`stations.logo_url` stores a file under `backend/uploads`**, served at `/uploads`. The upload accepts PNG, JPG, and WEBP up to 2 MB.
- **`GET /products` requires `prices.manage` in this phase.** Operators do not open settings. A later shift screen can widen the read if the operator must see the price.

## 13. Gaps filled in Phase 3

- **Demo tanks are seeded when `SEED_DEMO_ASSETS` is true** and the station has no tanks yet. The four cards match the mock, and every liter is a ledger row marked بيانات تجريبية. Turn the flag off for an empty yard.
- **`inventory_movements.nozzle_id` is optional.** The reading log can name the nozzle. Adjustments leave it empty.
- **The card band becomes يحتاج صيانة when the pump is in maintenance**, even if the tank level is otherwise مستقر. The stored level band stays separate.
- **معدل السحب اليومي is the sum of today’s `shift_sale` movements.** Approved duties do not exist until Phase 5, so the demo seed writes those movements for the current day.
- **A tank starts at 0 liters.** Volume changes only through the adjustment endpoint in this phase. The endpoint refuses a balance outside `0…capacity` and does not edit the old movement.

## 14. Gaps filled in Phase 4

- **The live pump codes stay `PUMP-01` and `PUMP-D1`.** The attendance mock prints `PUMP-A1`. That label is the same nozzle rule on the seeded pumps, not a second set of equipment.
- **Check-in is a clock on the session’s business date, in the station timezone.** `07:55` on a morning shift that starts at `08:00` with 10 minutes of grace is حاضر. `08:45` is متأخر.
- **Absent does not store a check-in.** The note is required. Coverage counts only present and late nozzles, over nozzles on pumps whose status is `active`.
- **Weekly compliance is Saturday through Friday.** Each day is `present + late + completed` over that sum plus `absent`. A day with three arrivals and one absence is 75%.
- **Opening a session is find-or-create.** The same template and date return the existing window, including an evening window that ends at midnight the next day.

## 15. Gaps filled in Phase 5

- **The manager shift log lives at `/manager/shifts`.** The plan’s `/shifts` path would be sent back to the manager home by the role redirect, which only allows `/manager`.
- **Rollover is a close field, not a nozzle column.** The nozzle table has no `meter_rollover_at`. A manager with `meter.override` sends `rollover` and `meter_rollover_at` on the closing line. An operator cannot.
- **A meter that differs from the last close needs `meter.override` and a written reason.** The accepted opening is stored on the reading. Approval still sets the nozzle meter to the closing reading.
- **Approve groups liters by tank.** Two nozzles on one pump share the tank, so the guard is the sum, not each line alone. `TANK_SHORT` is raised before any movement is added.
- **An open session with no approved duty yet shows dashes for liters, revenue, and variance.** Status stays جارية الآن. A zero is not labeled مطابق before anyone is approved.
- **The session becomes معتمدة ومغلقة when every duty is approved and every present, late, assigned, or completed attendance has one.** An absence does not keep the window open.
- **Close asks for confirmation before the post, then shows the server figures.** A mis-tap does not submit. The preview and the server both use 3 dp liters and 2 dp money, half-up.
- **One notification row is written per user who holds `shifts.approve` when a duty becomes pending.** The bell and the dashboard still belong to Phase 7.

## 16. Gaps filled in Phase 6

- **Order codes are `ORD-0001` upward.** The mock’s `ORD-9921` is a sample number. No historical orders are seeded, so the first real order starts at 1.
- **The create body includes `product_id`.** The tank is still required. If that product is not the tank’s product, the API returns `409 PRODUCT_MISMATCH`. The form only lists tanks of the chosen product, so the mismatch cannot be picked there.
- **A quantity above the supplier’s daily cap is refused.** The cap is `max_daily_liters`. Brega’s cap is the mock’s 500,000 L/day.
- **شركة ليبيا للنفط and شركة الراحلة للخدمات النفطية are seeded with an office and a contact.** The mock only prints those details for البريقة. Their names match the supplier list. No received liters are seeded.
- **The four counters use the station’s current calendar month.** Delivered liters use `received_at`. Active orders are the month’s orders that are not cancelled. Pending is the month’s `pending` rows. Active suppliers are every supplier with `is_active`, which is not a monthly figure.
- **Weekly bars are Saturday through Friday**, the sum of liters received on that day. The same week the attendance screen uses.
- **Reliability is received ÷ (received + cancelled) over 90 days**, rounded half-up. A supplier with no finished orders in that window has no score.
- **The orange طلب تزويد جديد button opens `/manager/supply?new=1`**, which is the same create dialog as the button on the page.

## 17. Gaps filled in Phase 7

- **The dashboard calls `rollup()` and `submitted_liters()`.** It does not keep a second formula. Revenue and variance are approved duties only. The liters card also includes a duty that is waiting for approval. An open duty has no liters yet.
- **The tank card uses `percent <= critical_percent`.** The gauge band still uses a strict less-than. The card is omitted when every active tank is above the line. A notification is written only when a tank crosses that line on approval, adjustment, or receipt.
- **License and stale-order checks run when the dashboard is loaded.** A license inside 30 days, and a pending order older than 3 days, each create one station-wide row. Marking that row read clears it for every manager. Duty-pending rows stay per approver, and they are still written when the duty is submitted.
- **The home route stays `/manager`.** The role redirect only allows that prefix.
- **The week is Saturday through Friday**, with a morning series when the template name contains صباح and an evening series otherwise. Both series are approved revenue.
- **Arabic strings for the dashboard and the error codes live in `app_ar.arb`.** The screens built in earlier phases keep their Arabic literals so the widget tests stay stable.
- **`python -m scripts.seed_demo_day` is manual.** Startup does not sell fuel, and the tests do not call the script.


