# IntrinsicAI

A local-first autonomous value investing analysis tool based on Phil Town's **Rule #1** investing strategy.

## Overview

IntrinsicAI helps value investors analyze stocks using the "Big 5" financial metrics:
- **EPS Growth** (Earnings Per Share)
- **Equity Growth** (Book Value)
- **Revenue Growth**
- **Free Cash Flow Growth**
- **Operating Cash Flow Growth**
- **ROIC** (Return on Invested Capital)

The system calculates CAGR (Compound Annual Growth Rate) over 1, 5, and 10 year periods, determines if stocks meet Rule #1 criteria (10%+ growth), and provides AI-powered insights via Google Gemini.

## Architecture

```
IntrinsicAI/
├── MainApp/          # Flutter Desktop Application (Windows/macOS/Linux)
├── Updater/          # Python CLI for fetching financial data
└── README.md         # This file
```

### Data Flow

```
EODHD API → Updater (Python) → SQLite Database → MainApp (Flutter) → User
                                                        ↓
                                              Gemini AI (Optional)
```

1. **Updater** fetches financial data from EODHD API and stores it in a local SQLite database
2. **MainApp** reads the database, performs Rule #1 analysis, and displays results
3. **Gemini AI** (optional) provides additional investment insights when authenticated

## Quick Start

### Prerequisites
- Python 3.11+ with [uv](https://github.com/astral-sh/uv) package manager
- Flutter 3.7+ with desktop support enabled
- EODHD API key (get one at [eodhistoricaldata.com](https://eodhistoricaldata.com/))

### 1. Set Up the Updater

```bash
cd Updater

# Install dependencies
uv sync

# Create .env file with your API key
echo "EODHD_API_KEY=your_api_key_here" > .env

# Fetch data for stocks (e.g., AAPL, MSFT, GOOGL)
uv run python update.py --tickers AAPL,MSFT,GOOGL
```

### 2. Run the Desktop App

```bash
cd MainApp

# Get Flutter dependencies
flutter pub get

# Run the app (choose your platform)
flutter run -d windows
flutter run -d macos
flutter run -d linux
```

### 3. (Optional) Enable AI Insights

1. Open the app and go to **Settings**
2. Click **Connect with Google**
3. Sign in with your Google account
4. Return to stock analysis and click **Generate Analysis**

## Rule #1 Criteria

A stock passes Rule #1 analysis if:

| Metric | Requirement |
|--------|-------------|
| EPS Growth (10yr CAGR) | ≥ 10% |
| Equity Growth (10yr CAGR) | ≥ 10% |
| Revenue Growth (10yr CAGR) | ≥ 10% |
| FCF Growth (10yr CAGR) | ≥ 10% |
| OCF Growth (10yr CAGR) | ≥ 10% |
| ROIC (10yr Average) | ≥ 10% |

### Status Colors
- **GREEN**: Passes all Rule #1 criteria
- **YELLOW**: Needs review (turnaround situations, partial data)
- **RED**: Fails one or more criteria

## Database Location

The SQLite database is stored in platform-specific locations:

| Platform | Path |
|----------|------|
| Windows | `%APPDATA%\IntrinsicAI\data\stocks.db` |
| macOS | `~/Library/Application Support/IntrinsicAI/data/stocks.db` |
| Linux | `~/.local/share/IntrinsicAI/data/stocks.db` |

## Project Documentation

- [MainApp README](./MainApp/README.md) - Flutter desktop application details
- [Updater README](./Updater/README.md) - Python data updater details
- [ROIC/GuruFocus calibration plan](./docs/specs/roic-gurufocus-calibration-plan-v1.md) - Parity methodology and acceptance thresholds
- [ROIC/GuruFocus comparison template](./docs/templates/roic-gurufocus-comparison-template.csv) - Reusable capture sheet for parity checks

## Tech Stack

### MainApp (Flutter)
- **State Management**: Riverpod
- **Database**: sqlite3 + sqlite3_flutter_libs
- **Authentication**: OAuth 2.0 with PKCE (Google)
- **AI**: Google Gemini API
- **UI**: Material Design 3

### Updater (Python)
- **HTTP Client**: httpx
- **Database**: sqlite3
- **Data Source**: EODHD API

## Disclaimer

This tool is for educational and informational purposes only. It is not financial advice. Always do your own research and consult with a qualified financial advisor before making investment decisions.
