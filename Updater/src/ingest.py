import argparse
import logging
import sqlite3
import json
import os
import time
from pathlib import Path
from datetime import datetime
from src.eodhd_client import EODHDDataClient
from src.db import get_db_connection, initialize_db, get_app_data_dir

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def get_debug_dir() -> Path:
    """Returns the debug directory path (local to Updater project)."""
    return Path(__file__).parent.parent / "data" / "debug"


def parse_and_save_fundamentals(ticker, data, conn):
    """
    Parses the EODHD fundamentals JSON and upserts into SQLite.
    """
    if not data:
        return

    # Save raw data for debugging (local to Updater project)
    debug_dir = get_debug_dir()
    debug_dir.mkdir(parents=True, exist_ok=True)
    debug_path = debug_dir / f"{ticker}_raw.json"

    try:
        with open(debug_path, "w") as f:
            json.dump(data, f, indent=4)
        logger.info(f"Saved raw debug data to {debug_path}")
    except Exception as e:
        logger.error(f"Failed to save debug data: {e}")

    cursor = conn.cursor()

    # 1. Update Companies Table
    general = data.get("General", {})
    name = general.get("Name")
    sector = general.get("Sector")

    cursor.execute(
        """
        INSERT INTO companies (ticker, name, sector, last_updated)
        VALUES (?, ?, ?, DATE('now'))
        ON CONFLICT(ticker) DO UPDATE SET
            name=excluded.name,
            sector=excluded.sector,
            last_updated=excluded.last_updated
    """,
        (ticker, name, sector),
    )

    # 2. Update Financials Table
    financials = data.get("Financials", {})
    income_statement = financials.get("Income_Statement", {}).get("yearly", {})
    balance_sheet = financials.get("Balance_Sheet", {}).get("yearly", {})
    cash_flow = financials.get("Cash_Flow", {}).get("yearly", {})

    # Collecting all available dates
    all_dates = (
        set(income_statement.keys()) | set(balance_sheet.keys()) | set(cash_flow.keys())
    )

    for date_str in all_dates:
        # Extract Year from date_str (usually "YYYY-MM-DD")
        try:
            year = int(date_str.split("-")[0])
        except (ValueError, IndexError):
            continue

        # Helper to safely get float values (returns None for missing data)
        def get_val(source, date_k, key):
            try:
                val = source.get(date_k, {}).get(key)
                if val is not None:
                    return float(val)
                return None
            except (ValueError, TypeError):
                return None

        # Income Statement
        revenue = get_val(income_statement, date_str, "totalRevenue")
        net_income = get_val(income_statement, date_str, "netIncome")
        ebit = get_val(income_statement, date_str, "ebit")
        tax_provision = get_val(income_statement, date_str, "taxProvision")
        income_before_tax = get_val(income_statement, date_str, "incomeBeforeTax")

        # Balance Sheet
        total_equity = get_val(balance_sheet, date_str, "totalStockholderEquity")
        shares_outstanding = get_val(
            balance_sheet, date_str, "commonStockSharesOutstanding"
        )
        long_term_debt = get_val(balance_sheet, date_str, "longTermDebt")
        short_term_debt = get_val(balance_sheet, date_str, "shortTermDebt")
        cash = get_val(balance_sheet, date_str, "cash")

        # Cash Flow
        cash_flow_ops = get_val(cash_flow, date_str, "totalCashFromOperatingActivities")
        capital_exp = get_val(cash_flow, date_str, "capitalExpenditures")
        free_cash_flow = get_val(cash_flow, date_str, "freeCashFlow")

        # Derived Metrics

        # 1. EPS Diluted
        eps_diluted = None
        if shares_outstanding and shares_outstanding > 0 and net_income is not None:
            eps_diluted = net_income / shares_outstanding

        # 2. ROIC Calculation (Rule #1 Style)
        # ROIC = NOPAT / Invested Capital
        # NOPAT = EBIT * (1 - Tax Rate)
        # Invested Capital = Total Equity + Total Debt - Cash
        roic = None
        try:
            if ebit is not None and total_equity is not None:
                # Calculate Tax Rate
                tax_rate = 0.25  # Default assumption
                if (
                    income_before_tax
                    and income_before_tax != 0
                    and tax_provision is not None
                ):
                    tax_rate = tax_provision / income_before_tax

                nopat = ebit * (1 - tax_rate)

                total_debt = (long_term_debt or 0) + (short_term_debt or 0)
                invested_capital = total_equity + total_debt - (cash or 0)

                if invested_capital != 0:
                    roic = nopat / invested_capital
        except Exception:
            roic = None

        cursor.execute(
            """
            INSERT INTO financials (
                ticker, year, revenue, net_income, eps_diluted, total_equity, 
                cash_flow_ops, free_cash_flow, capital_exp, roic, shares_outstanding
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(ticker, year) DO UPDATE SET
                revenue=excluded.revenue,
                net_income=excluded.net_income,
                eps_diluted=excluded.eps_diluted,
                total_equity=excluded.total_equity,
                cash_flow_ops=excluded.cash_flow_ops,
                free_cash_flow=excluded.free_cash_flow,
                capital_exp=excluded.capital_exp,
                roic=excluded.roic,
                shares_outstanding=excluded.shares_outstanding
        """,
            (
                ticker,
                year,
                revenue,
                net_income,
                eps_diluted,
                total_equity,
                cash_flow_ops,
                free_cash_flow,
                capital_exp,
                roic,
                shares_outstanding,
            ),
        )

    conn.commit()
    logger.info(f"Updated data for {ticker}")


def run_updater(mode, tickers, local_file=None):
    initialize_db()
    conn = get_db_connection()

    # Log where database is located
    app_dir = get_app_data_dir()
    logger.info(f"Database location: {app_dir / 'data' / 'stocks.db'}")

    if local_file:
        logger.info(f"Ingesting from local file: {local_file}")
        try:
            with open(local_file, "r") as f:
                data = json.load(f)
            # Infer ticker from filename or data
            ticker = data.get("General", {}).get("Code")
            if not ticker:
                # Try from filename
                base = os.path.basename(local_file)
                ticker = (
                    base.split("_")[0] if "_" in base else base.replace(".json", "")
                )

            # Ensure .US if needed (though raw data has PrimaryTicker)
            if data.get("General", {}).get("CountryISO") == "US" and "." not in ticker:
                ticker = f"{ticker}.US"

            parse_and_save_fundamentals(ticker, data, conn)
        except Exception as e:
            logger.error(f"Failed to ingest local file: {e}")
        finally:
            conn.close()
        return

    client = EODHDDataClient()
    logger.info(f"Starting updater in {mode} mode.")

    for ticker in tickers:
        # Handle ticker format: append .US if no dot present
        if "." not in ticker:
            ticker_formatted = f"{ticker}.US"
            logger.warning(f"Assuming US exchange for {ticker} -> {ticker_formatted}")
        else:
            ticker_formatted = ticker

        try:
            data = client.get_fundamentals(ticker_formatted)
            if data:
                parse_and_save_fundamentals(ticker_formatted, data, conn)
            else:
                logger.warning(f"No data found for {ticker_formatted}")

            # Simple rate limiting protection
            time.sleep(1)

        except Exception as e:
            logger.error(f"Failed to update {ticker_formatted}: {e}")

    conn.close()
    logger.info("Update complete.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode", choices=["bulk", "daily"], default="daily", help="Update mode"
    )
    parser.add_argument(
        "--tickers",
        nargs="+",
        default=["AAPL", "MSFT", "GOOGL"],
        help="List of tickers",
    )

    args = parser.parse_args()

    run_updater(args.mode, args.tickers)
