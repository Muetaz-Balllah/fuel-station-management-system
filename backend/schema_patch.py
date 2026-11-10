"""Add columns that create_all will not alter onto an existing SQLite file."""

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine


def apply_schema_updates(engine: Engine) -> None:
    """Bring an existing database in line with the current models.

    Local development uses SQLite. Render uses Neon PostgreSQL, and create_all
    does not alter tables that already exist.
    """
    if str(engine.url).startswith("sqlite"):
        apply_sqlite_patches(engine)
        return
    _migrate_user_role_postgres(engine)
    drop_copied_meter_columns(engine)


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
    ]
    with engine.begin() as conn:
        for table, column, ddl in patches:
            if table not in tables:
                continue
            names = {col["name"] for col in inspector.get_columns(table)}
            if column not in names:
                conn.execute(text(ddl))
    _migrate_user_role(engine)
    drop_copied_meter_columns(engine)


def drop_copied_meter_columns(engine: Engine) -> None:
    """The correction log is nozzle_meter_adjustments. These reading columns copied it."""
    inspector = inspect(engine)
    if "shift_readings" not in set(inspector.get_table_names()):
        return
    names = {col["name"] for col in inspector.get_columns("shift_readings")}
    extras = [
        name
        for name in ("meter_adjusted", "previous_meter", "meter_reason", "adjusted_by")
        if name in names
    ]
    if not extras:
        return
    with engine.begin() as conn:
        for name in extras:
            conn.execute(text(f"ALTER TABLE shift_readings DROP COLUMN {name}"))


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


def _migrate_user_role_postgres(engine: Engine) -> None:
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if "users" not in tables:
        return
    names = {col["name"] for col in inspector.get_columns("users")}
    role_code = "code" in {
        col["name"] for col in inspector.get_columns("roles")
    } if "roles" in tables else False
    with engine.begin() as conn:
        if "role" not in names:
            conn.execute(text("ALTER TABLE users ADD COLUMN role VARCHAR(32)"))
        if "role_id" in names and role_code:
            conn.execute(
                text(
                    """
                    UPDATE users AS u
                    SET role = r.code
                    FROM roles AS r
                    WHERE u.role_id = r.id
                      AND (u.role IS NULL OR btrim(u.role) = '')
                    """
                )
            )
        conn.execute(
            text(
                """
                UPDATE users
                SET role = 'operator'
                WHERE role IS NULL OR btrim(role) = '' OR role = 'system_admin'
                """
            )
        )
        if "role_id" in names:
            conn.execute(
                text(
                    """
                    DO $$
                    DECLARE constraint_row record;
                    BEGIN
                      FOR constraint_row IN
                        SELECT c.conname
                        FROM pg_constraint c
                        JOIN pg_class t ON t.oid = c.conrelid
                        JOIN pg_attribute a
                          ON a.attrelid = t.oid AND a.attnum = ANY (c.conkey)
                        WHERE t.relname = 'users'
                          AND a.attname = 'role_id'
                      LOOP
                        EXECUTE format(
                          'ALTER TABLE users DROP CONSTRAINT %I',
                          constraint_row.conname
                        );
                      END LOOP;
                    END $$;
                    """
                )
            )
            conn.execute(text("ALTER TABLE users DROP COLUMN IF EXISTS role_id"))
        conn.execute(text("ALTER TABLE users ALTER COLUMN role SET NOT NULL"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_users_role ON users (role)"))
        for table in ("role_permissions", "permissions", "roles"):
            conn.execute(text(f"DROP TABLE IF EXISTS {table} CASCADE"))
