from collections.abc import Generator

from sqlalchemy import event
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, create_engine

from config import settings


def _make_engine():
    url = settings.database_url
    if url.startswith("sqlite"):
        connect_args = {"check_same_thread": False}
        # One shared connection keeps the in-memory database used by tests alive.
        if url in {"sqlite://", "sqlite:///:memory:"}:
            engine = create_engine(url, connect_args=connect_args, poolclass=StaticPool)
        else:
            engine = create_engine(url, connect_args=connect_args)
        _enable_sqlite_foreign_keys(engine)
        return engine
    return create_engine(url, pool_pre_ping=True)


def _enable_sqlite_foreign_keys(engine) -> None:
    @event.listens_for(engine, "connect")
    def _set_pragma(dbapi_connection, _connection_record) -> None:
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


engine = _make_engine()


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
