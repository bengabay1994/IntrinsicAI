import sqlite3
import os
import sys
from pathlib import Path
from typing import Callable


MigrationFn = Callable[[sqlite3.Connection], None]


def get_app_data_dir() -> Path:
    """
    Returns the platform-specific application data directory for IntrinsicAI.

    - Windows: %APPDATA%/IntrinsicAI
    - macOS: ~/Library/Application Support/IntrinsicAI
    - Linux: ~/.local/share/IntrinsicAI
    """
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        # Linux and other Unix-like systems
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))

    app_dir = base / "IntrinsicAI"
    return app_dir


def get_db_path() -> Path:
    """Returns the path to the stocks database."""
    app_dir = get_app_data_dir()
    return app_dir / "data" / "stocks.db"


def ensure_data_dir():
    """Creates the data directory if it doesn't exist."""
    db_path = get_db_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    return db_path


# For backward compatibility
DB_PATH = get_db_path()


SCHEMA_MIGRATIONS_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"""


def get_db_connection():
    """Establishes a connection to the SQLite database."""
    db_path = ensure_data_dir()
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def _column_exists(conn: sqlite3.Connection, table_name: str, column_name: str) -> bool:
    cursor = conn.execute(f"PRAGMA table_info({table_name})")
    return any(row["name"] == column_name for row in cursor.fetchall())


def _migration_1_create_core_tables(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS companies (
            ticker TEXT PRIMARY KEY,
            name TEXT,
            sector TEXT,
            last_updated DATE
        );
        """
    )

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS financials (
            ticker TEXT,
            year INTEGER,
            revenue REAL,
            net_income REAL,
            eps_diluted REAL,
            total_equity REAL,
            cash_flow_ops REAL,
            capital_exp REAL,
            roic REAL,
            shares_outstanding REAL,
            PRIMARY KEY (ticker, year)
        );
        """
    )


def _migration_2_add_free_cash_flow(conn: sqlite3.Connection) -> None:
    if not _column_exists(conn, "financials", "free_cash_flow"):
        conn.execute("ALTER TABLE financials ADD COLUMN free_cash_flow REAL;")


def _migration_3_create_ceo_letters(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS ceo_letters (
            ticker      TEXT NOT NULL,
            fiscal_year INTEGER NOT NULL,
            filing_date TEXT,
            raw_excerpt TEXT,
            summary     TEXT,
            fetched_at  TEXT NOT NULL,
            PRIMARY KEY (ticker, fiscal_year)
        );
        """
    )


MIGRATIONS: list[tuple[int, str, MigrationFn]] = [
    (1, "create_core_tables", _migration_1_create_core_tables),
    (2, "add_free_cash_flow", _migration_2_add_free_cash_flow),
    (3, "create_ceo_letters", _migration_3_create_ceo_letters),
]


def _ensure_migrations_table(conn: sqlite3.Connection) -> None:
    conn.execute(SCHEMA_MIGRATIONS_TABLE_SQL)
    conn.commit()


def _get_applied_versions(conn: sqlite3.Connection) -> set[int]:
    cursor = conn.execute("SELECT version FROM schema_migrations")
    return {int(row["version"]) for row in cursor.fetchall()}


def _record_migration(conn: sqlite3.Connection, version: int, name: str) -> None:
    conn.execute(
        "INSERT INTO schema_migrations (version, name) VALUES (?, ?)",
        (version, name),
    )


def _apply_migrations(conn: sqlite3.Connection) -> None:
    _ensure_migrations_table(conn)
    applied_versions = _get_applied_versions(conn)

    for version, name, migrate_fn in MIGRATIONS:
        if version in applied_versions:
            continue

        try:
            conn.execute("BEGIN")
            migrate_fn(conn)
            _record_migration(conn, version, name)
            conn.commit()
            print(f"Applied migration {version}: {name}")
        except Exception:
            conn.rollback()
            raise


def _validate_required_schema(conn: sqlite3.Connection) -> None:
    required_tables = {"companies", "financials", "ceo_letters", "schema_migrations"}
    cursor = conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
    existing_tables = {row["name"] for row in cursor.fetchall()}

    missing_tables = required_tables - existing_tables
    if missing_tables:
        missing = ", ".join(sorted(missing_tables))
        raise RuntimeError(f"Missing required tables after migration: {missing}")

    if not _column_exists(conn, "financials", "free_cash_flow"):
        raise RuntimeError("Missing required column financials.free_cash_flow")


def initialize_db() -> None:
    """Initializes database schema using forward-only, tracked migrations."""
    conn = get_db_connection()
    try:
        _apply_migrations(conn)
        _validate_required_schema(conn)
    finally:
        conn.close()

    db_path = get_db_path()
    print(f"Database initialized at {db_path}")


if __name__ == "__main__":
    initialize_db()
