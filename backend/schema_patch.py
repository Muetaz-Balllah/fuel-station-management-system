"""Lightweight SQLite column patches for local dev DBs (create_all does not ALTER)."""

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine


def apply_sqlite_patches(engine: Engine) -> None:
    url = str(engine.url)
    if not url.startswith("sqlite"):
        return
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    patches: list[tuple[str, str, str]] = [
        ("suppliers", "logo_url", "ALTER TABLE suppliers ADD COLUMN logo_url VARCHAR(300)"),
        ("users", "photo_url", "ALTER TABLE users ADD COLUMN photo_url VARCHAR(300)"),
        ("shift_duties", "rostered_user_id", "ALTER TABLE shift_duties ADD COLUMN rostered_user_id VARCHAR(36)"),
        ("shift_templates", "business_date", "ALTER TABLE shift_templates ADD COLUMN business_date DATE"),
    ]
    with engine.begin() as conn:
        for table, column, ddl in patches:
            if table not in tables:
                continue
            names = {col["name"] for col in inspector.get_columns(table)}
            if column not in names:
                conn.execute(text(ddl))
