# IntrinsicAI - MainApp

Flutter desktop application for Rule #1 value investing analysis.

## Features

- **Stock Analysis**: Analyze stocks using Phil Town's Rule #1 "Big 5" metrics
- **CAGR Calculations**: 1-year, 5-year, and 10-year compound annual growth rates
- **Sticker Price**: Calculate intrinsic value and margin of safety price
- **AI Insights**: Optional Google Gemini integration for deeper analysis
- **Cross-Platform**: Windows, macOS, and Linux support

## Prerequisites

- Flutter 3.7 or later
- Desktop development enabled:
  ```bash
  flutter config --enable-windows-desktop
  flutter config --enable-macos-desktop
  flutter config --enable-linux-desktop
  ```
- Platform-specific requirements:
  - **Windows**: Visual Studio 2022 with "Desktop development with C++" workload
  - **macOS**: Xcode 14+
  - **Linux**: GTK 3.0, pkg-config, CMake, ninja-build

## Installation

```bash
# Clone the repository (if not already done)
cd MainApp

# Get dependencies
flutter pub get

# Run the app
flutter run -d windows    # Windows
flutter run -d macos      # macOS
flutter run -d linux      # Linux
```

## Building for Release

```bash
# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

Build outputs are located in `build/<platform>/runner/Release/`.

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── core/
│   ├── config/
│   │   └── app_config.dart      # App configuration and paths
│   ├── database/
│   │   ├── database_service.dart # SQLite database access
│   │   └── models/              # Data models (Company, Financial)
│   ├── analysis/
│   │   ├── math_core.dart       # CAGR and valuation calculations
│   │   ├── rule1_analyzer.dart  # Rule #1 analysis engine
│   │   └── models/              # Analysis models (MetricResult, AnalysisResult)
│   └── ai/
│       ├── gemini_oauth_config.dart  # OAuth configuration
│       ├── services/
│       │   ├── token_storage_service.dart  # Secure token storage
│       │   ├── oauth_service.dart          # OAuth 2.0 with PKCE
│       │   └── gemini_service.dart         # Gemini API client
│       └── providers/
│           └── ai_providers.dart           # Riverpod providers for AI
├── features/
│   ├── home/
│   │   └── home_screen.dart     # Main screen with search
│   ├── analysis/
│   │   ├── analysis_screen.dart # Analysis results display
│   │   └── widgets/             # UI components for analysis
│   └── settings/
│       └── settings_screen.dart # Settings and OAuth
└── shared/
    ├── theme/
    │   └── app_theme.dart       # Material 3 theme
    └── providers/
        └── providers.dart       # Core Riverpod providers
```

## Dependencies

| Package | Purpose |
|---------|---------|
| flutter_riverpod | State management |
| sqlite3 | Database core |
| sqlite3_flutter_libs | SQLite native libraries |
| path_provider | Platform paths |
| http | HTTP client |
| url_launcher | OAuth browser launch |
| flutter_secure_storage | Secure token storage |
| shelf | OAuth callback server |
| crypto | PKCE code challenge |
| intl | Number formatting |
| equatable | Value equality |

## Configuration

### Database Path

The app expects the SQLite database at platform-specific locations:

| Platform | Path |
|----------|------|
| Windows | `%APPDATA%\IntrinsicAI\data\stocks.db` |
| macOS | `~/Library/Application Support/IntrinsicAI/data/stocks.db` |
| Linux | `~/.local/share/IntrinsicAI/data/stocks.db` |

Run the **Updater** tool first to create the database.

### OAuth (Gemini AI)

The OAuth flow uses:
- **Callback Port**: 8085 (localhost)
- **Scopes**: OpenID, email, cloud-platform

Ensure port 8085 is available when signing in.

## Usage

1. **First Run**: If no database exists, the app shows setup instructions
2. **Search**: Enter a ticker symbol (e.g., "AAPL") and click "Analyze"
3. **Review Results**: 
   - Status badge (GREEN/YELLOW/RED)
   - Growth metrics with CAGR percentages
   - ROIC averages
   - Historical data table
4. **AI Insights** (optional):
   - Go to Settings → Connect with Google
   - Return to analysis → Click "Generate Analysis"

## Troubleshooting

### "No Database Found"
Run the Updater tool first:
```bash
cd ../Updater
uv run python update.py --tickers AAPL
```

### OAuth fails to open browser
Ensure `url_launcher` has proper permissions on your platform.

### Port 8085 in use
Another application is using the OAuth callback port. Close it and try again.

## License

MIT License - See root LICENSE file for details.
