# IntrinsicAI - Updater

Python CLI tool for fetching financial data from EODHD API and storing it in the local SQLite database.

## Features

- Fetches fundamental financial data from EODHD API
- Stores raw JSON responses for debugging
- Parses and stores structured data in SQLite
- Supports bulk and daily update modes
- Cross-platform database path support

## Prerequisites

- Python 3.10 or later
- [uv](https://github.com/astral-sh/uv) package manager
- EODHD API key ([sign up here](https://eodhistoricaldata.com/))

## Installation

```bash
cd Updater

# Install dependencies with uv
uv sync
```

## Configuration

Create a `.env` file in the Updater directory:

```env
EODHD_API_KEY=your_api_key_here
```

## Usage

### Basic Usage

```bash
# Update specific tickers
uv run python update.py --tickers AAPL MSFT GOOGL

# Update with default tickers (AAPL, MSFT, GOOGL, AMZN, META)
uv run python update.py
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--tickers` | Space-separated list of ticker symbols | AAPL MSFT GOOGL AMZN META |
| `--mode` | Update mode: `bulk` or `daily` | daily |
| `--local` | Path to local JSON file to ingest | None |

### Examples

```bash
# Fetch data for specific stocks
uv run python update.py --tickers AAPL TSLA NVDA

# Ingest from a local JSON file (for testing)
uv run python update.py --local path/to/data.json

# Bulk mode (fetches more historical data)
uv run python update.py --mode bulk --tickers AAPL
```

## Project Structure

```
Updater/
├── update.py           # Main entry point
├── src/
│   ├── __init__.py
│   ├── eodhd_client.py # EODHD API client
│   ├── ingest.py       # Data ingestion logic
│   └── db.py           # SQLite database operations
├── pyproject.toml      # Project dependencies
├── .env                # API key (create this)
└── README.md           # This file
```

## Database Schema

### companies
| Column | Type | Description |
|--------|------|-------------|
| ticker | TEXT | Primary key (e.g., "AAPL.US") |
| name | TEXT | Company name |
| sector | TEXT | Business sector |
| last_updated | TEXT | ISO timestamp |

### financials
| Column | Type | Description |
|--------|------|-------------|
| ticker | TEXT | Foreign key to companies |
| year | INTEGER | Fiscal year |
| revenue | REAL | Total revenue |
| net_income | REAL | Net income |
| eps_diluted | REAL | Diluted EPS |
| total_equity | REAL | Total stockholder equity |
| cash_flow_ops | REAL | Operating cash flow |
| free_cash_flow | REAL | Free cash flow |
| capital_exp | REAL | Capital expenditures |
| roic | REAL | Return on invested capital |
| shares_outstanding | REAL | Shares outstanding |

## Database Location

The database is created at platform-specific locations:

| Platform | Path |
|----------|------|
| Windows | `%APPDATA%\IntrinsicAI\data\stocks.db` |
| macOS | `~/Library/Application Support/IntrinsicAI/data/stocks.db` |
| Linux | `~/.local/share/IntrinsicAI/data/stocks.db` |

Raw JSON responses are saved to `<db_dir>/raw/<TICKER>_raw.json` for debugging.

## Data Source

Financial data is provided by [EODHD](https://eodhistoricaldata.com/):
- Fundamental data (balance sheet, income statement, cash flow)
- Up to 30+ years of historical data
- Global stock coverage

## Troubleshooting

### "API key not found"
Ensure you have created a `.env` file with your EODHD API key.

### "No data returned"
- Check that the ticker symbol is correct (e.g., "AAPL" not "APPLE")
- Some tickers may not have fundamental data available
- Verify your API key has access to fundamental data

### Database not created
The Updater creates the database directory automatically. If issues persist, manually create the directory:
```bash
# Windows
mkdir %APPDATA%\IntrinsicAI\data

# macOS/Linux
mkdir -p ~/.local/share/IntrinsicAI/data
```

## License

MIT License - See root LICENSE file for details.
