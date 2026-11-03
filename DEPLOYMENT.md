# Deployment checklist

Use this when uploading the project to hosting for the first test run.

**Free tier (Neon + Upstash + Render API + Render Flutter web):** step-by-step guide in Arabic — [`docs/FREE_HOSTING_GUIDE_AR.md`](docs/FREE_HOSTING_GUIDE_AR.md).  
Templates: `backend/.env.production.example`, `Dockerfile` (repo root), `render.yaml`, `frontend/scripts/render_build.sh`.  
Flutter **mobile/desktop** builds run on devices — no static host; use the same `API_BASE_URL` when building releases.

## Backend

1. Copy `backend/.env.example` to `backend/.env` on the server.
2. Set a strong **`JWT_SECRET`** (32+ random characters). Never use the example value in production.
3. Set **`DATABASE_URL`** to your hosted database (PostgreSQL recommended for production).
4. Set **`REDIS_URL`** to a reachable Redis instance (required for login sessions).
5. For durable images on Render, set S3-compatible storage: **`AWS_ENDPOINT_URL_S3`**, **`S3_BUCKET`**, **`AWS_ACCESS_KEY_ID`**, **`AWS_SECRET_ACCESS_KEY`** (see `backend/.env.production.example`). Without these, uploads use ephemeral local disk.
6. Set **`CORS_ORIGINS`** to your Flutter web URL (comma-separated), not `*` in production.
7. For the **first** deploy with sample data:
   - `SEED_ON_STARTUP=true`
   - `SEED_DEMO_ASSETS=true` (four pumps/tanks from seed)
   - Change default **`SEED_*_PASSWORD`** values after testing, or set `SEED_ON_STARTUP=false` on subsequent restarts so users are not recreated.
8. Run the API (example): `./start.sh` or `uvicorn main:app --host 0.0.0.0 --port 8000`
9. Optional extra data (run once on the server, from `backend/`):
   - `python -m scripts.seed_demo_day` — today’s sample sale for the dashboard
   - `python -m scripts.seed_realistic` — supply orders and past shifts

## Frontend (Flutter)

**Web (Render static site):** set `API_BASE_URL` in Render; build uses `frontend/scripts/render_build.sh`. See `render.yaml`.

**Mobile / desktop (no hosting):** build with the same API URL, e.g.  
`flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com`

Local web:  
`flutter build web --dart-define=API_BASE_URL=https://your-api.example.com`

## Fresh database

New databases are created from the current SQLModel models only (no legacy columns).  
If you reuse an old SQLite file that still has removed columns, prefer a **new empty database** on hosting.

## Health check

`GET /api/v1/health` should return `"status": "ok"`, `"redis": "ok"`, and `"storage_ok": "ok"` when S3 is configured.
