import sqlite3
import json
from pathlib import Path

import pytest

from src.ingest import parse_and_save_fundamentals


@pytest.fixture
def in_memory_db():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row

    conn.execute(
        """
        CREATE TABLE companies (
            ticker TEXT PRIMARY KEY,
            name TEXT,
            sector TEXT,
            last_updated DATE
        )
        """
    )

    conn.execute(
        """
        CREATE TABLE financials (
            ticker TEXT,
            year INTEGER,
            revenue REAL,
            net_income REAL,
            eps_diluted REAL,
            total_equity REAL,
            cash_flow_ops REAL,
            free_cash_flow REAL,
            capital_exp REAL,
            roic REAL,
            shares_outstanding REAL,
            PRIMARY KEY (ticker, year)
        )
        """
    )

    try:
        yield conn
    finally:
        conn.close()


@pytest.mark.parametrize("fixture_payload", ["normal_payload.json"], indirect=True)
def test_parse_and_save_normal_payload(
    monkeypatch, in_memory_db, fixture_payload, tmp_path
):
    monkeypatch.setattr("src.ingest.get_debug_dir", lambda: tmp_path / "debug")

    parse_and_save_fundamentals("NORM.US", fixture_payload, in_memory_db)

    company = in_memory_db.execute(
        "SELECT ticker, name, sector FROM companies WHERE ticker = ?", ("NORM.US",)
    ).fetchone()
    assert company is not None
    assert company["name"] == "Normal Corp"
    assert company["sector"] == "Technology"

    financial = in_memory_db.execute(
        """
        SELECT revenue, net_income, eps_diluted, total_equity,
               cash_flow_ops, free_cash_flow, capital_exp,
               roic, shares_outstanding
        FROM financials
        WHERE ticker = ? AND year = ?
        """,
        ("NORM.US", 2024),
    ).fetchone()

    assert financial is not None
    assert financial["revenue"] == pytest.approx(1500.0)
    assert financial["net_income"] == pytest.approx(200.0)
    assert financial["eps_diluted"] == pytest.approx(2.0)
    assert financial["total_equity"] == pytest.approx(1000.0)
    assert financial["cash_flow_ops"] == pytest.approx(250.0)
    assert financial["free_cash_flow"] == pytest.approx(120.0)
    assert financial["capital_exp"] == pytest.approx(-80.0)
    assert financial["shares_outstanding"] == pytest.approx(100.0)
    assert financial["roic"] == pytest.approx(0.18)


@pytest.mark.parametrize("fixture_payload", ["sparse_payload.json"], indirect=True)
def test_sparse_payload_is_tolerated(
    monkeypatch, in_memory_db, fixture_payload, tmp_path
):
    monkeypatch.setattr("src.ingest.get_debug_dir", lambda: tmp_path / "debug")

    parse_and_save_fundamentals("SPRS.US", fixture_payload, in_memory_db)

    company_count = in_memory_db.execute(
        "SELECT COUNT(*) AS count FROM companies WHERE ticker = ?", ("SPRS.US",)
    ).fetchone()["count"]
    assert company_count == 1

    financial_count = in_memory_db.execute(
        "SELECT COUNT(*) AS count FROM financials WHERE ticker = ?", ("SPRS.US",)
    ).fetchone()["count"]
    assert financial_count == 1

    financial = in_memory_db.execute(
        "SELECT year, total_equity, revenue, net_income FROM financials WHERE ticker = ?",
        ("SPRS.US",),
    ).fetchone()
    assert financial["year"] == 2023
    assert financial["total_equity"] == pytest.approx(500.0)
    assert financial["revenue"] is None
    assert financial["net_income"] is None


@pytest.mark.parametrize("fixture_payload", ["malformed_payload.json"], indirect=True)
def test_malformed_values_do_not_crash_and_null_out(
    monkeypatch, in_memory_db, fixture_payload, tmp_path
):
    monkeypatch.setattr("src.ingest.get_debug_dir", lambda: tmp_path / "debug")

    parse_and_save_fundamentals("BAD1.US", fixture_payload, in_memory_db)

    row = in_memory_db.execute(
        """
        SELECT year, revenue, net_income, eps_diluted, cash_flow_ops, capital_exp, roic
        FROM financials
        WHERE ticker = ?
        """,
        ("BAD1.US",),
    ).fetchone()

    assert row is not None
    assert row["year"] == 2022
    assert row["revenue"] is None
    assert row["net_income"] is None
    assert row["eps_diluted"] is None
    assert row["cash_flow_ops"] is None
    assert row["capital_exp"] is None
    assert row["roic"] is None


def test_conflicting_payloads_upsert_predictably(monkeypatch, in_memory_db, tmp_path):
    monkeypatch.setattr("src.ingest.get_debug_dir", lambda: tmp_path / "debug")

    base = Path(__file__).parent / "fixtures" / "ingest"
    with (base / "conflicting_payload_first.json").open("r", encoding="utf-8") as f:
        first_payload = json.load(f)
    with (base / "conflicting_payload_second.json").open("r", encoding="utf-8") as f:
        second_payload = json.load(f)

    parse_and_save_fundamentals("CNFL.US", first_payload, in_memory_db)
    parse_and_save_fundamentals("CNFL.US", second_payload, in_memory_db)

    company = in_memory_db.execute(
        "SELECT name, sector FROM companies WHERE ticker = ?", ("CNFL.US",)
    ).fetchone()
    assert company["name"] == "Conflict Co Revised"
    assert company["sector"] == "Consumer Defensive"

    financial = in_memory_db.execute(
        """
        SELECT revenue, net_income, eps_diluted, free_cash_flow, roic
        FROM financials
        WHERE ticker = ? AND year = ?
        """,
        ("CNFL.US", 2021),
    ).fetchone()
    assert financial["revenue"] == pytest.approx(1200.0)
    assert financial["net_income"] == pytest.approx(180.0)
    assert financial["eps_diluted"] == pytest.approx(2.0)
    assert financial["free_cash_flow"] == pytest.approx(160.0)
    assert financial["roic"] == pytest.approx(0.1811320755)
