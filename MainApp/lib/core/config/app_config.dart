import 'dart:io';
import 'package:path/path.dart' as path;

/// Application configuration constants and paths.
class AppConfig {
  AppConfig._();

  static const String appName = 'IntrinsicAI';
  static const String appVersion = '1.0.0';

  /// Minimum years of data required for reliable analysis.
  static const int minYearsRequired = 7;

  /// Rule #1 growth threshold (10%).
  static const double growthThreshold = 0.10;

  /// Rule #1 ROIC threshold (10%).
  static const double roicThreshold = 0.10;

  /// Returns the platform-specific application data directory.
  static String getAppDataDir() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          path.join(Platform.environment['USERPROFILE'] ?? '', 'AppData', 'Roaming');
      return path.join(appData, appName);
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return path.join(home, 'Library', 'Application Support', appName);
    } else {
      // Linux and other Unix-like systems
      final xdgData = Platform.environment['XDG_DATA_HOME'] ??
          path.join(Platform.environment['HOME'] ?? '', '.local', 'share');
      return path.join(xdgData, appName);
    }
  }

  /// Returns the path to the stocks database.
  static String getDatabasePath() {
    return path.join(getAppDataDir(), 'data', 'stocks.db');
  }
}
