"""Copy every application table from one database into another.

The target schema comes from the current models, so leftover columns such as
``tanks.is_demo`` and ``pumps.is_demo`` are not created. Values that exist only
in the source are reported and left behind. Columns that exist only in the
target keep their model default.

Run from the backend directory.

New local SQLite file (safe: refuses to overwrite a file that already has rows
unless ``--replace`` is set)::

    python -m scripts.copy_database --target sqlite:///./fuel_station.fresh.db

Later, copy the local database onto the Postgres database on the server.
``--replace`` deletes rows in the application tables on the target first.
Pass the server URL explicitly; the script never assumes a production URL::

    python -m scripts.copy_database ^
        --source sqlite:///./fuel_station.db ^
        --target "postgresql://USER:PASSWORD@HOST/neondb?sslmode=require" ^
        --replace

``postgresql://`` and ``postgres://`` are rewritten to ``postgresql+psycopg://``.
"""

from __future__ import annotations

import argparse
import sys
import uuid
from datetime import date, datetime, time, timezone
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sqlalchemy import Boolean, Date, DateTime, Float, Integer, Numeric, Time, func, inspect, select, text
from sqlalchemy.types import TypeDecorator
from sqlalchemy.engine import Engine
from sqlmodel import SQLModel, create_engine

from config import _normalize_database_url, settings

# Columns removed from the models. Dropped on the target when an older file
# or the server database still has them, so inserts do not hit NOT NULL.
_REMOVED_COLUMNS = (
    ("tanks", "is_demo"),
    ("pumps", "is_demo"),
)


def _load_models() -> None:
    import assets.models  # noqa: F401
    import attendance.models  # noqa: F401
    import shifts.models  # noqa: F401
    import stations.models  # noqa: F401
    import supply.models  # noqa: F401
    import users.models  # noqa: F401


def _make_engine(url: str) -> Engine:
    if url.startswith("sqlite"):
        engine = create_engine(url, connect_args={"check_same_thread": False})

        from sqlalchemy import event

        @event.listens_for(engine, "connect")
        def _set_pragma(dbapi_connection, _connection_record) -> None:
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

        return engine
    return create_engine(url, pool_pre_ping=True)


def _sqlite_file(url: str) -> Path | None:
    if not url.startswith("sqlite"):
        return None
    if url in {"sqlite://", "sqlite:///:memory:"} or ":memory:" in url:
        raise SystemExit("In-memory SQLite cannot be a copy source or target.")
    path_part = url.split("?", 1)[0].removeprefix("sqlite:///")
    return Path(path_part).expanduser().resolve()


def _remove_sqlite_files(path: Path) -> None:
    for suffix in ("", "-wal", "-shm"):
        candidate = Path(str(path) + suffix) if suffix else path
        if candidate.exists():
            candidate.unlink()


def _is_uuid(impl: object) -> bool:
    return "uuid" in type(impl).__name__.lower()


def _concrete_type(column_type):
    """Unwrap SQLModel TypeDecorators such as UTCDateTime down to the SQLAlchemy type."""
    current = column_type
    for _ in range(6):
        if isinstance(current, TypeDecorator):
            current = current.impl
            continue
        break
    if isinstance(current, type):
        current = current()
    return current


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _coerce(value: object, column) -> object:
    if value is None:
        return None
    impl = _concrete_type(column.type)
    if _is_uuid(column.type) or _is_uuid(impl):
        if isinstance(value, uuid.UUID):
            return value
        text_value = str(value).strip()
        return uuid.UUID(text_value) if text_value else None
    if isinstance(impl, Boolean):
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return bool(int(value))
        return str(value).strip().lower() in {"1", "true", "t", "yes"}
    if isinstance(impl, DateTime):
        if isinstance(value, datetime):
            parsed = value
        else:
            text_value = str(value).strip().replace("Z", "+00:00")
            if not text_value:
                return None
            parsed = datetime.fromisoformat(text_value)
        return _as_utc(parsed)
    if isinstance(impl, Date):
        if isinstance(value, datetime):
            return value.date()
        if isinstance(value, date):
            return value
        text_value = str(value).strip()
        return date.fromisoformat(text_value[:10]) if text_value else None
    if isinstance(impl, Time):
        if isinstance(value, datetime):
            return value.time()
        if isinstance(value, time):
            return value
        text_value = str(value).strip()
        return time.fromisoformat(text_value) if text_value else None
    if isinstance(impl, Numeric):
        if isinstance(value, Decimal):
            return value
        return Decimal(str(value))
    if isinstance(impl, Float):
        return float(value)
    if isinstance(impl, Integer) and not isinstance(value, bool):
        return int(value)
    return value


def _source_tables(engine: Engine) -> set[str]:
    names = set(inspect(engine).get_table_names())
    return {name for name in names if not name.startswith("sqlite_")}


def _count(connection, table) -> int:
    value = connection.execute(select(func.count()).select_from(table)).scalar_one()
    return int(value or 0)


def copy_database(source_url: str, target_url: str, *, replace: bool = False) -> dict[str, int]:
    """Create the target schema from the models and copy every shared row.

    Returns inserted row counts keyed by table name.
    """
    source_url = _normalize_database_url(source_url)
    target_url = _normalize_database_url(target_url)
    source_file = _sqlite_file(source_url)
    target_file = _sqlite_file(target_url)
    if source_file is not None and target_file is not None and source_file == target_file:
        raise SystemExit("Source and target are the same SQLite file.")
    if source_url == target_url:
        raise SystemExit("Source and target URLs are the same.")

    _load_models()
    source = _make_engine(source_url)
    try:
        present = _source_tables(source)
        known = {table.name for table in SQLModel.metadata.sorted_tables}
        unknown = sorted(present - known)
        if unknown:
            raise SystemExit(
                "Source has tables that are not in the models, so they would be left behind: "
                + ", ".join(unknown)
            )
        if replace and target_file is not None and target_file.exists():
            _remove_sqlite_files(target_file)

        target = _make_engine(target_url)
        try:
            SQLModel.metadata.create_all(target)
            from schema_patch import apply_sqlite_patches

            apply_sqlite_patches(target)
            ordered = list(SQLModel.metadata.sorted_tables)
            with target.connect() as probe:
                existing_rows = sum(_count(probe, table) for table in ordered)
            if existing_rows and not replace:
                raise SystemExit(
                    f"Target already has {existing_rows} rows. Re-run with --replace to replace them."
                )

            source_columns = {
                table.name: {column["name"] for column in inspect(source).get_columns(table.name)}
                for table in ordered
                if table.name in present
            }
            skipped: dict[str, list[str]] = {}
            for table in ordered:
                if table.name not in present:
                    continue
                extra = sorted(source_columns[table.name] - {column.name for column in table.columns})
                if extra:
                    skipped[table.name] = extra
                for column in table.columns:
                    if column.name in source_columns[table.name]:
                        continue
                    if column.nullable or column.default is not None or column.server_default is not None:
                        continue
                    raise SystemExit(
                        f"{table.name}.{column.name} is required on the target but missing from the source."
                    )

            counts: dict[str, int] = {}
            with target.connect() as connection:
                if connection.dialect.name == "sqlite":
                    connection.exec_driver_sql("PRAGMA foreign_keys=OFF")
                    connection.commit()
                with connection.begin():
                    if replace:
                        for table in reversed(ordered):
                            connection.execute(table.delete())
                    for table_name, column_name in _REMOVED_COLUMNS:
                        table_names = set(inspect(connection).get_table_names())
                        if table_name not in table_names:
                            continue
                        names = {column["name"] for column in inspect(connection).get_columns(table_name)}
                        if column_name not in names:
                            continue
                        if connection.dialect.name == "sqlite":
                            connection.execute(text(f"ALTER TABLE {table_name} DROP COLUMN {column_name}"))
                        else:
                            connection.execute(
                                text(f"ALTER TABLE {table_name} DROP COLUMN IF EXISTS {column_name}")
                            )
                    with source.connect() as incoming:
                        for table in ordered:
                            if table.name not in present:
                                counts[table.name] = 0
                                continue
                            rows = incoming.execute(text(f'SELECT * FROM "{table.name}"')).mappings().all()
                            payload = [
                                {
                                    column.name: _coerce(row[column.name], column)
                                    for column in table.columns
                                    if column.name in source_columns[table.name]
                                }
                                for row in rows
                            ]
                            for start in range(0, len(payload), 200):
                                connection.execute(table.insert(), payload[start : start + 200])
                            counts[table.name] = len(payload)
                            note = ""
                            if table.name in skipped:
                                note = " (left behind: " + ", ".join(skipped[table.name]) + ")"
                            print(f"{table.name}: {counts[table.name]}{note}")
                    if connection.dialect.name == "sqlite":
                        broken = connection.execute(text("PRAGMA foreign_key_check")).fetchall()
                        if broken:
                            raise SystemExit(f"Foreign key check failed after copy: {broken}")
                    for table in ordered:
                        copied = _count(connection, table)
                        if copied != counts[table.name]:
                            raise SystemExit(
                                f"Count mismatch on {table.name}: copied {counts[table.name]}, table has {copied}."
                            )
            return counts
        finally:
            target.dispose()
    finally:
        source.dispose()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Copy all application data into a new SQLite file or an existing Postgres database."
    )
    parser.add_argument(
        "--source",
        default=settings.database_url,
        help="Database to read. Defaults to DATABASE_URL / the local SQLite file.",
    )
    parser.add_argument(
        "--target",
        required=True,
        help="Database to write. SQLite file URL, or postgresql://... for the server.",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Replace target rows. For a SQLite file this rebuilds the file. For Postgres this deletes application rows first.",
    )
    args = parser.parse_args(argv)
    counts = copy_database(args.source, args.target, replace=args.replace)
    total = sum(counts.values())
    print(f"Copied {total} rows across {len(counts)} tables.")


if __name__ == "__main__":
    main()
