import sqlite3
import os
import sys
from pathlib import Path


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


def get_db_connection():
    """Establishes a connection to the SQLite database."""
    db_path = ensure_data_dir()
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def initialize_db():
    """Initializes the database with the required schema."""
    conn = get_db_connection()
    cursor = conn.cursor()

    # Table: companies
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS companies (
        ticker TEXT PRIMARY KEY,
        name TEXT,
        sector TEXT,
        last_updated DATE
    );
    """)

    # Table: financials (Annual)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS financials (
        ticker TEXT,
        year INTEGER,
        revenue REAL,              -- Sales/Revenue
        net_income REAL,           -- Net Income
        eps_diluted REAL,          -- Earnings Per Share (Diluted)
        total_equity REAL,         -- Book Value / Stockholder Equity
        cash_flow_ops REAL,        -- Operating Cash Flow
        free_cash_flow REAL,       -- Free Cash Flow
        capital_exp REAL,          -- Capital Expenditures
        roic REAL,                 -- Return on Invested Capital
        shares_outstanding REAL,
        PRIMARY KEY (ticker, year)
    );
    """)

    # Table: ceo_letters (CEO annual letters to shareholders)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS ceo_letters (
        ticker        TEXT NOT NULL,
        fiscal_year   INTEGER NOT NULL,
        filing_date   TEXT,
        raw_excerpt   TEXT,
        summary       TEXT,
        fetched_at    TEXT NOT NULL,
        PRIMARY KEY (ticker, fiscal_year)
    );
    """)

    # Migration: Add free_cash_flow column if it doesn't exist
    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN free_cash_flow REAL;")
        conn.commit()
        print("Added free_cash_flow column to financials table.")
    except sqlite3.OperationalError:
        # Column already exists
        pass

    conn.commit()
    conn.close()

    db_path = get_db_path()
    print(f"Database initialized at {db_path}")


if __name__ == "__main__":
    initialize_db()
