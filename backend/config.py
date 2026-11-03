from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _normalize_database_url(url: str) -> str:
    """Neon and other hosts often give postgresql://; SQLModel needs postgresql+psycopg://."""
    if url.startswith("postgresql+psycopg://"):
        return url
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url.removeprefix("postgresql://")
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url.removeprefix("postgres://")
    return url


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # sqlite:///./fuel_station.db for local work. PostgreSQL is the same code:
    # postgresql+psycopg://fuel:fuel@localhost:5432/fuel_station
    database_url: str = "sqlite:///./fuel_station.db"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "dev-only-change-me-please-use-32-chars"
    access_token_minutes: int = 15
    refresh_token_days: int = 7
    refresh_token_remember_days: int = 30
    lockout_attempts: int = 5
    lockout_minutes: int = 15
    seed_on_startup: bool = True
    auto_create_tables: bool = True
    seed_manager_username: str = "manager"
    seed_manager_password: str = "Manager@12345"
    seed_operator_username: str = "operator"
    seed_operator_password: str = "Operator@12345"
    seed_admin_username: str = "admin"
    seed_admin_password: str = "Admin@12345"
    seed_demo_assets: bool = True
    cors_origins: str = "*"
    app_name: str = "Fuel Station Management System"

    @field_validator("database_url", mode="before")
    @classmethod
    def _coerce_database_url(cls, value: object) -> object:
        if isinstance(value, str):
            return _normalize_database_url(value)
        return value


settings = Settings()
