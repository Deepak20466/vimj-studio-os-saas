from sqlalchemy import create_engine, event
from sqlalchemy.engine import make_url
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy.pool import NullPool

from app.config import settings


def normalize_database_url(database_url: str) -> str:
    # Managed Postgres providers commonly hand out "postgres://" URLs, a
    # scheme SQLAlchemy dropped support for in 1.4+.
    if database_url.startswith("postgres://"):
        return database_url.replace("postgres://", "postgresql+psycopg2://", 1)
    return database_url


def create_database_engine(database_url: str):
    normalized_url = normalize_database_url(database_url)
    parsed_url = make_url(normalized_url)

    if parsed_url.get_backend_name() == "postgresql":
        if parsed_url.port == 6543:
            # Supabase transaction pooling does not preserve a client-side
            # SQLAlchemy pool between transactions. Close each DBAPI connection
            # when its Session releases it instead of retaining pooler clients.
            # The pinned psycopg2 driver also does not auto-create named
            # prepared statements; psycopg 3's prepare_threshold option does
            # not apply here and must not be passed as a psycopg2 connect arg.
            return create_engine(normalized_url, poolclass=NullPool)

        # Bound each Gunicorn worker's retained client connections. The service
        # currently runs four workers, so this keeps the idle app-side pool at
        # no more than eight connections per instance.
        return create_engine(
            normalized_url,
            pool_pre_ping=True,
            pool_size=2,
            max_overflow=0,
        )

    # Preserve the existing behavior for local SQLite and other development DBs.
    return create_engine(
        normalized_url,
        pool_pre_ping=True,
        pool_size=10,
        max_overflow=20,
    )


engine = create_database_engine(settings.DATABASE_URL)

if engine.dialect.name == "sqlite":
    # SQLite ignores FK constraints (and ON DELETE CASCADE) unless explicitly enabled per connection.
    # Postgres enforces these by default, so this keeps dev (SQLite) behavior matching production.
    @event.listens_for(engine, "connect")
    def _enable_sqlite_foreign_keys(dbapi_connection, _):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
