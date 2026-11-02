# Fuel station API

Local development uses a SQLite file and Redis for session tokens. The database URL is the only switch to PostgreSQL. Queries stay in SQLAlchemy / SQLModel either way.

```text
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
cd ..
docker compose up -d
cd backend
uvicorn main:app --reload
```

`docker compose up -d` starts Redis. The SQLite file `fuel_station.db` is created in `backend/` on first launch. If you already have a database from an earlier run, delete `fuel_station.db` once so the new columns are created.

PostgreSQL, when you want it:

```text
DATABASE_URL=postgresql+psycopg://fuel:fuel@localhost:5432/fuel_station
```

Development sign-in:

- admin / Admin@12345 (system admin, can edit role permissions)
- manager / Manager@12345
- operator / Operator@12345

The first launch also seeds four demo pumps (PUMP-01, PUMP-02, PUMP-D1, PUMP-D2) when the station has no tanks. Set `SEED_DEMO_ASSETS=false` to skip them.

A separate command adds one approved 10-liter sale for today, so the dashboard is not empty. It skips itself when today's morning shift or a pending Brega order already exists, and it does not run on startup or in the tests:

```text
python -m scripts.seed_demo_day
```

For richer local data (supply orders + past approved shifts):

```text
python -m scripts.seed_realistic
```

Hosting: see [DEPLOYMENT.md](../DEPLOYMENT.md).

Docs: http://127.0.0.1:8000/docs

Tests use an in-memory database and an in-memory Redis, so they do not need Docker:

```text
cd backend
pytest
```

The Flutter app reads `API_BASE_URL`, default `http://127.0.0.1:8000`.
