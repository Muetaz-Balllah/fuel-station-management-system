# FastAPI backend — Docker image for Render.com Web Service
#
# Render dashboard (Manual):
#   New → Web Service → Connect repo
#   Runtime: Docker
#   Root Directory: backend          (if repo root is fuel-station-management-system)
#   Dockerfile path: Dockerfile
#   Health Check Path: /api/v1/health
#   Environment: see .env.production.example (Neon, Upstash, S3, JWT, CORS)
#
# Render injects PORT; start.sh binds uvicorn to 0.0.0.0:$PORT

FROM python:3.12-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod +x start.sh

EXPOSE 8000

CMD ["./start.sh"]
