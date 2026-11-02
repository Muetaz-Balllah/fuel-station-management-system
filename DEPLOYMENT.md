# Deployment checklist

Use this when uploading the project to hosting for the first test run.

## Backend

1. Copy `backend/.env.example` to `backend/.env` on the server.
2. Set a strong **`JWT_SECRET`** (32+ random characters). Never use the example value in production.
3. Set **`DATABASE_URL`** to your hosted database (PostgreSQL recommended for production).
4. Set **`REDIS_URL`** to a reachable Redis instance (required for login sessions).
5. Set **`CORS_ORIGINS`** to your Flutter web URL (comma-separated), not `*` in production.
6. For the **first** deploy with sample data:
   - `SEED_ON_STARTUP=true`
   - `SEED_DEMO_ASSETS=true` (four pumps/tanks from seed)
   - Change default **`SEED_*_PASSWORD`** values after testing, or set `SEED_ON_STARTUP=false` on subsequent restarts so users are not recreated.
7. Run the API (example): `uvicorn main:app --host 0.0.0.0 --port 8000`
8. Optional extra data (run once on the server, from `backend/`):
   - `python -m scripts.seed_demo_day` — today’s sample sale for the dashboard
   - `python -m scripts.seed_realistic` — supply orders and past shifts

## Frontend (Flutter)

1. Build with the hosted API URL, e.g.  
   `flutter build web --dart-define=API_BASE_URL=https://your-api.example.com`
2. Serve the `build/web` output from your static host or CDN.

## Fresh database

New databases are created from the current SQLModel models only (no legacy columns).  
If you reuse an old SQLite file that still has removed columns, prefer a **new empty database** on hosting.

## Health check

`GET /api/v1/health` should return `"status": "ok"` and `"redis": "ok"`.
