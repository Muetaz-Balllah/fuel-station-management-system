# FastAPI backend — built from repository root (fuel-station-management-system/)
#
# Render dashboard:
#   Runtime: Docker
#   Root Directory: .  (this folder — fuel-station-management-system)
#   Dockerfile path: Dockerfile
#   Health Check Path: /api/v1/health
#
# Local build from repo root:
#   docker build -t fuel-station-api .

FROM python:3.12-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ .

RUN chmod +x start.sh

EXPOSE 8000

CMD ["./start.sh"]
