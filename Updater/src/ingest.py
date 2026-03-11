import argparse
import logging
import sqlite3
import json
import os
import time
from pathlib import Path
from datetime import datetime
from enum import Enum
from typing import Any
from src.eodhd_client import EODHDDataClient
from src.db import get_db_connection, initialize_db, get_app_data_dir

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class ParseErrorCode(str, Enum):
    MISSING_REQUIRED_SECTION = "missing_required_section"
    INVALID_SECTION_FORMAT = "invalid_section_format"
    MALFORMED_DATE = "malformed_date"
    INVALID_NUMERIC = "invalid_numeric"
    UNEXPECTED_RECORD_ERROR = "unexpected_record_error"


class FundamentalsParseError(Exception):
    def __init__(
        self,
        code: ParseErrorCode,
        message: str,
        *,
        section: str | None = None,
        field: str | None = None,
        date: str | None = None,
        value: Any = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.section = section
        self.field = field
        self.date = date
        self.value = value


def _log_parse_failure(ticker: str, error: FundamentalsParseError) -> None:
    payload = {
        "ticker": ticker,
        "code": error.code.value,
        "message": str(error),
    }
    if error.section is not None:
        payload["section"] = error.section
    if error.field is not None:
        payload["field"] = error.field
    if error.date is not None:
        payload["date"] = error.date
    if error.value is not None:
        payload["value"] = error.value

    logger.warning("fundamentals_parse_failure %s", payload)


def _require_mapping(value: Any, *, section: str) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    raise FundamentalsParseError(
        ParseErrorCode.INVALID_SECTION_FORMAT,
        f"Section '{section}' must be an object",
        section=section,
        value=type(value).__name__,
    )


def _require_section(data: dict[str, Any], section: str) -> dict[str, Any]:
    section_value = data.get(section)
    if section_value is None:
        raise FundamentalsParseError(
            ParseErrorCode.MISSING_REQUIRED_SECTION,
            f"Required section '{section}' is missing",
            section=section,
        )
    return _require_mapping(section_value, section=section)


def _extract_yearly_section(
    financials: dict[str, Any],
    section_name: str,
    ticker: str,
) -> dict[str, Any]:
    section_value = financials.get(section_name)
    if section_value is None:
        _log_parse_failure(
            ticker,
            FundamentalsParseError(
                ParseErrorCode.MISSING_REQUIRED_SECTION,
                f"Section '{section_name}' is missing",
                section=section_name,
            ),
        )
        return {}

    section_mapping = _require_mapping(section_value, section=section_name)
    yearly = section_mapping.get("yearly")
    if yearly is None:
        _log_parse_failure(
            ticker,
            FundamentalsParseError(
                ParseErrorCode.MISSING_REQUIRED_SECTION,
                f"Section '{section_name}.yearly' is missing",
                section=f"{section_name}.yearly",
            ),
        )
        return {}

    return _require_mapping(yearly, section=f"{section_name}.yearly")


def _parse_fiscal_year(date_str: str) -> int:
    try:
        parsed = datetime.strptime(date_str, "%Y-%m-%d")
        return parsed.year
    except ValueError as error:
        raise FundamentalsParseError(
            ParseErrorCode.MALFORMED_DATE,
            f"Expected date format YYYY-MM-DD, received '{date_str}'",
            date=date_str,
        ) from error


def _parse_optional_float(
    value: Any,
    *,
    section: str,
    field: str,
    date: str,
) -> float | None:
    if value is None:
        return None

    if isinstance(value, bool):
        raise FundamentalsParseError(
            ParseErrorCode.INVALID_NUMERIC,
            f"Field '{field}' must be numeric",
            section=section,
            field=field,
            date=date,
            value=value,
        )

    if isinstance(value, (int, float)):
        return float(value)

    if isinstance(value, str):
        normalized = value.strip().replace(",", "")
        if normalized == "":
            return None
        try:
            return float(normalized)
        except ValueError as error:
            raise FundamentalsParseError(
                ParseErrorCode.INVALID_NUMERIC,
                f"Field '{field}' is not a valid number",
                section=section,
                field=field,
                date=date,
                value=value,
            ) from error

    raise FundamentalsParseError(
        ParseErrorCode.INVALID_NUMERIC,
        f"Field '{field}' must be numeric",
        section=section,
        field=field,
        date=date,
        value=value,
    )


def _get_numeric_field(
    source: dict[str, Any],
    *,
    section_name: str,
    date_str: str,
    field: str,
    ticker: str,
) -> float | None:
    record = source.get(date_str, {})
    if not isinstance(record, dict):
        _log_parse_failure(
            ticker,
            FundamentalsParseError(
                ParseErrorCode.INVALID_SECTION_FORMAT,
                f"Record for '{section_name}' and '{date_str}' must be an object",
                section=section_name,
                date=date_str,
                value=type(record).__name__,
            ),
        )
        return None

    try:
        return _parse_optional_float(
            record.get(field),
            section=section_name,
            field=field,
            date=date_str,
        )
    except FundamentalsParseError as error:
        _log_parse_failure(ticker, error)
        return None


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
    try:
        financials = _require_section(data, "Financials")
    except FundamentalsParseError as error:
        _log_parse_failure(ticker, error)
        conn.commit()
        logger.info(f"Updated data for {ticker}")
        return

    try:
        income_statement = _extract_yearly_section(
            financials, "Income_Statement", ticker
        )
        balance_sheet = _extract_yearly_section(financials, "Balance_Sheet", ticker)
        cash_flow = _extract_yearly_section(financials, "Cash_Flow", ticker)
    except FundamentalsParseError as error:
        _log_parse_failure(ticker, error)
        conn.commit()
        logger.info(f"Updated data for {ticker}")
        return

    # Collecting all available dates
    all_dates = (
        set(income_statement.keys()) | set(balance_sheet.keys()) | set(cash_flow.keys())
    )

    for date_str in all_dates:
        # Extract Year from date_str (usually "YYYY-MM-DD")
        try:
            year = _parse_fiscal_year(date_str)
        except FundamentalsParseError as error:
            _log_parse_failure(ticker, error)
            continue

        # Income Statement
        revenue = _get_numeric_field(
            income_statement,
            section_name="Income_Statement",
            date_str=date_str,
            field="totalRevenue",
            ticker=ticker,
        )
        net_income = _get_numeric_field(
            income_statement,
            section_name="Income_Statement",
            date_str=date_str,
            field="netIncome",
            ticker=ticker,
        )
        ebit = _get_numeric_field(
            income_statement,
            section_name="Income_Statement",
            date_str=date_str,
            field="ebit",
            ticker=ticker,
        )
        tax_provision = _get_numeric_field(
            income_statement,
            section_name="Income_Statement",
            date_str=date_str,
            field="taxProvision",
            ticker=ticker,
        )
        income_before_tax = _get_numeric_field(
            income_statement,
            section_name="Income_Statement",
            date_str=date_str,
            field="incomeBeforeTax",
            ticker=ticker,
        )

        # Balance Sheet
        total_equity = _get_numeric_field(
            balance_sheet,
            section_name="Balance_Sheet",
            date_str=date_str,
            field="totalStockholderEquity",
            ticker=ticker,
        )
        shares_outstanding = _get_numeric_field(
            balance_sheet,
            section_name="Balance_Sheet",
            date_str=date_str,
            field="commonStockSharesOutstanding",
            ticker=ticker,
        )
        long_term_debt = _get_numeric_field(
            balance_sheet,
            section_name="Balance_Sheet",
            date_str=date_str,
            field="longTermDebt",
            ticker=ticker,
        )
        short_term_debt = _get_numeric_field(
            balance_sheet,
            section_name="Balance_Sheet",
            date_str=date_str,
            field="shortTermDebt",
            ticker=ticker,
        )
        cash = _get_numeric_field(
            balance_sheet,
            section_name="Balance_Sheet",
            date_str=date_str,
            field="cash",
            ticker=ticker,
        )

        # Cash Flow
        cash_flow_ops = _get_numeric_field(
            cash_flow,
            section_name="Cash_Flow",
            date_str=date_str,
            field="totalCashFromOperatingActivities",
            ticker=ticker,
        )
        capital_exp = _get_numeric_field(
            cash_flow,
            section_name="Cash_Flow",
            date_str=date_str,
            field="capitalExpenditures",
            ticker=ticker,
        )
        free_cash_flow = _get_numeric_field(
            cash_flow,
            section_name="Cash_Flow",
            date_str=date_str,
            field="freeCashFlow",
            ticker=ticker,
        )

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
        except Exception as error:
            _log_parse_failure(
                ticker,
                FundamentalsParseError(
                    ParseErrorCode.UNEXPECTED_RECORD_ERROR,
                    "Unexpected error during ROIC calculation",
                    date=date_str,
                    value=str(error),
                ),
            )
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
