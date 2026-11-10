"""Load the bundled local station database into Neon once.

The snapshot travels with the deployment because Render only has the Git
repository. A later restart sees the marker and leaves the server data alone.
"""

from pathlib import Path

from sqlalchemy import text

SNAPSHOT_ID = "local-2026-11-10"
_SNAPSHOT = Path(__file__).resolve().parent / "data" / "hosted_snapshot.db"


def import_hosted_snapshot_once(engine) -> None:
    if str(engine.url).startswith("sqlite") or not _SNAPSHOT.exists():
        return
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS hosted_imports (
                    snapshot_id VARCHAR(64) PRIMARY KEY,
                    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
        )
        already = connection.execute(
            text("SELECT 1 FROM hosted_imports WHERE snapshot_id = :snapshot_id"),
            {"snapshot_id": SNAPSHOT_ID},
        ).first()
    if already:
        return

    from config import settings
    from scripts.copy_database import copy_database

    copy_database(
        "sqlite:///" + _SNAPSHOT.resolve().as_posix(),
        settings.database_url,
        replace=True,
    )
    with engine.begin() as connection:
        connection.execute(
            text("INSERT INTO hosted_imports (snapshot_id) VALUES (:snapshot_id)"),
            {"snapshot_id": SNAPSHOT_ID},
        )
