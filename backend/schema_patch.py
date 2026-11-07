"""Add columns that create_all will not alter onto an existing SQLite file."""

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine


def apply_sqlite_patches(engine: Engine) -> None:
    if not str(engine.url).startswith("sqlite"):
        return
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    patches = [
        ("suppliers", "logo_url", "ALTER TABLE suppliers ADD COLUMN logo_url VARCHAR(300)"),
        ("users", "photo_url", "ALTER TABLE users ADD COLUMN photo_url VARCHAR(300)"),
        ("shift_duties", "rostered_user_id", "ALTER TABLE shift_duties ADD COLUMN rostered_user_id VARCHAR(36)"),
        ("shift_templates", "business_date", "ALTER TABLE shift_templates ADD COLUMN business_date DATE"),
        ("shift_readings", "meter_adjusted", "ALTER TABLE shift_readings ADD COLUMN meter_adjusted BOOLEAN NOT NULL DEFAULT 0"),
        ("shift_readings", "previous_meter", "ALTER TABLE shift_readings ADD COLUMN previous_meter NUMERIC(16, 3)"),
        ("shift_readings", "meter_reason", "ALTER TABLE shift_readings ADD COLUMN meter_reason VARCHAR(300)"),
        ("shift_readings", "adjusted_by", "ALTER TABLE shift_readings ADD COLUMN adjusted_by VARCHAR(36)"),
    ]
    with engine.begin() as conn:
        for table, column, ddl in patches:
            if table not in tables:
                continue
            names = {col["name"] for col in inspector.get_columns(table)}
            if column not in names:
                conn.execute(text(ddl))
    _migrate_user_role(engine)


def _migrate_user_role(engine: Engine) -> None:
    inspector = inspect(engine)
    if "users" not in set(inspector.get_table_names()):
        return
    columns = inspector.get_columns("users")
    names = {col["name"] for col in columns}
    if "role_id" not in names:
        return
    raw = engine.raw_connection()
    try:
        cursor = raw.cursor()
        cursor.execute("PRAGMA foreign_keys=OFF")
        if "role" not in names:
            cursor.execute("ALTER TABLE users ADD COLUMN role VARCHAR(32)")
        if "roles" in set(inspector.get_table_names()):
            cursor.execute(
                """
                UPDATE users
                SET role = (
                    SELECT roles.code FROM roles WHERE roles.id = users.role_id
                )
                WHERE role IS NULL OR role = ''
                """
            )
        cursor.execute(
            """
            UPDATE users
            SET role = 'operator'
            WHERE role IS NULL OR role = '' OR role = 'system_admin'
            """
        )
        kept = [col["name"] for col in columns if col["name"] != "role_id"]
        if "role" not in kept:
            kept.append("role")
        column_sql = ", ".join(kept)
        cursor.execute(
            f"""
            CREATE TABLE users_role_migrated (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                station_id VARCHAR(36) NOT NULL,
                role VARCHAR(32) NOT NULL,
                employee_code VARCHAR(32) NOT NULL,
                full_name VARCHAR(200) NOT NULL,
                username VARCHAR(64) NOT NULL,
                email VARCHAR(200),
                password_hash VARCHAR(255) NOT NULL,
                job_title VARCHAR(120) NOT NULL DEFAULT '',
                photo_url VARCHAR(300),
                is_active BOOLEAN NOT NULL DEFAULT 1,
                is_maintenance BOOLEAN NOT NULL DEFAULT 0,
                failed_login_count INTEGER NOT NULL DEFAULT 0,
                locked_until DATETIME,
                last_login_at DATETIME,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            )
            """
        )
        cursor.execute(
            f"""
            INSERT INTO users_role_migrated ({column_sql})
            SELECT {column_sql} FROM users
            """
        )
        cursor.execute("DROP TABLE users")
        cursor.execute("ALTER TABLE users_role_migrated RENAME TO users")
        cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_users_station_username ON users (station_id, username)")
        cursor.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_users_station_employee_code ON users (station_id, employee_code)"
        )
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_users_station_id ON users (station_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_users_role ON users (role)")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_users_username ON users (username)")
        cursor.execute("DROP TABLE IF EXISTS role_permissions")
        cursor.execute("DROP TABLE IF EXISTS permissions")
        cursor.execute("DROP TABLE IF EXISTS roles")
        cursor.execute("PRAGMA foreign_keys=ON")
        raw.commit()
    finally:
        raw.close()
