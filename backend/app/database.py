"""
SQLAlchemy database engine and session management.
Replaces Spring Data JPA + H2 configuration.
"""
import logging
from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker, Session
from typing import Generator

logger = logging.getLogger(__name__)

from app.config import settings


# Create SQLite engine
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False},  # Required for SQLite
    echo=False,  # Set True for SQL debugging (replaces spring.jpa.show-sql)
)

# Enable WAL mode and foreign keys for SQLite
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


# Session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


# Base class for all models (replaces JPA @Entity base)
class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    """
    Dependency that provides a database session.
    Replaces Spring's @Autowired repository injection.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_tables():
    """
    Create all tables from model definitions.
    Replaces spring.jpa.hibernate.ddl-auto=update.
    """
    Base.metadata.create_all(bind=engine)


def migrate_schema():
    """
    Lightweight auto-migration: adds any columns present in models
    but missing from the actual database tables.

    SQLAlchemy's create_all() only creates new tables; it won't ALTER
    existing ones. This function bridges that gap for simple column adds.
    """
    inspector = inspect(engine)
    with engine.begin() as conn:
        for table_name, table in Base.metadata.tables.items():
            if not inspector.has_table(table_name):
                continue
            existing = {col["name"] for col in inspector.get_columns(table_name)}
            for col in table.columns:
                if col.name in existing:
                    continue
                col_type = col.type.compile(dialect=engine.dialect)
                default_clause = ""
                if col.server_default is not None:
                    default_clause = f" DEFAULT {col.server_default.arg}"
                nullable_clause = "" if col.nullable else " NOT NULL"
                stmt = (
                    f"ALTER TABLE {table_name} "
                    f"ADD COLUMN {col.name} {col_type}"
                    f"{default_clause}{nullable_clause}"
                )
                logger.info("Auto-migration: %s", stmt)
                conn.execute(text(stmt))

        # Recreate missing indexes for newly added columns
        for table_name, table in Base.metadata.tables.items():
            if not inspector.has_table(table_name):
                continue
            existing_idx_cols = set()
            for idx in inspector.get_indexes(table_name):
                for c in idx["column_names"]:
                    existing_idx_cols.add(c)
            for idx in table.indexes:
                idx_cols = {c.name for c in idx.columns}
                if not idx_cols - existing_idx_cols:
                    continue
                create_sql = f"CREATE INDEX IF NOT EXISTS {idx.name} ON {table_name} ({', '.join(c.name for c in idx.columns)})"
                logger.info("Auto-migration index: %s", create_sql)
                conn.execute(text(create_sql))
