from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, declarative_base

from app.config import settings

# Managed Postgres providers (Render, Heroku, etc.) commonly hand out
# "postgres://" URLs, a scheme SQLAlchemy dropped support for in 1.4+.
_database_url = settings.DATABASE_URL
if _database_url.startswith("postgres://"):
    _database_url = _database_url.replace("postgres://", "postgresql+psycopg2://", 1)

engine = create_engine(_database_url, pool_pre_ping=True, pool_size=10, max_overflow=20)

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
