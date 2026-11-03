from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlmodel import Session, SQLModel

from assets.routes import router as assets_router
from attendance.routes import router as attendance_router
from dashboard.routes import router as dashboard_router
from shifts.routes import router as shifts_router
from supply.routes import router as supply_router
from auth.routes import router as auth_router
from config import settings
from core.cache import session_cache
from db import engine
from errors import AppError
from stations.catalog_routes import products_router, templates_router
from stations.routes import router as station_router
from users.routes import router as users_router
from system.routes import router as system_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    import assets.models  # noqa: F401
    import attendance.models  # noqa: F401
    import shifts.models  # noqa: F401
    import supply.models  # noqa: F401
    import stations.models  # noqa: F401
    import users.models  # noqa: F401

    Path("uploads").mkdir(parents=True, exist_ok=True)
    if settings.auto_create_tables:
        SQLModel.metadata.create_all(engine)
        from schema_patch import apply_sqlite_patches

        apply_sqlite_patches(engine)
    if settings.seed_on_startup:
        from users.bootstrap import seed

        with Session(engine) as session:
            seed(session, settings)
    yield


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name, lifespan=lifespan)
    origins = (
        ["*"]
        if settings.cors_origins.strip() == "*"
        else [item.strip() for item in settings.cors_origins.split(",") if item.strip()]
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"code": exc.code, "message": exc.message},
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={
                "code": "VALIDATION_ERROR",
                "message": "البيانات المرسلة غير مكتملة أو غير صالحة.",
            },
        )

    @app.get("/api/v1/health")
    def health() -> dict[str, str]:
        database = "sqlite" if settings.database_url.startswith("sqlite") else "postgresql"
        return {
            "status": "ok",
            "database": database,
            "redis": "ok" if session_cache.ping() else "down",
        }

    app.include_router(auth_router, prefix="/api/v1")
    app.include_router(station_router, prefix="/api/v1")
    app.include_router(users_router, prefix="/api/v1")
    app.include_router(products_router, prefix="/api/v1")
    app.include_router(templates_router, prefix="/api/v1")
    app.include_router(assets_router, prefix="/api/v1")
    app.include_router(attendance_router, prefix="/api/v1")
    app.include_router(shifts_router, prefix="/api/v1")
    app.include_router(supply_router, prefix="/api/v1")
    app.include_router(dashboard_router, prefix="/api/v1")
    app.include_router(system_router, prefix="/api/v1")
    Path("uploads").mkdir(parents=True, exist_ok=True)
    app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
    return app


app = create_app()
