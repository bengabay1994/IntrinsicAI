import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import '../config/app_config.dart';
import 'models/company.dart';
import 'models/financial.dart';
import 'models/ceo_letter.dart';

/// Service for accessing the stocks database (read-only).
class DatabaseService {
  Database? _database;

  /// Checks if the database file exists.
  bool databaseExists() {
    final dbPath = AppConfig.getDatabasePath();
    return File(dbPath).existsSync();
  }

  /// Opens the database connection.
  void open() {
    if (_database != null) return;

    final dbPath = AppConfig.getDatabasePath();
    if (!File(dbPath).existsSync()) {
      throw DatabaseNotFoundException(
        'Database not found at $dbPath. Please run the Updater first.',
      );
    }

    _database = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  }

  /// Closes the database connection.
  void close() {
    _database?.dispose();
    _database = null;
  }

  /// Gets all available tickers from the database.
  List<Company> getAllCompanies() {
    _ensureOpen();
    final results = _database!.select(
      'SELECT ticker, name, sector, last_updated FROM companies ORDER BY ticker',
    );

    return results.map((row) => Company.fromMap(row)).toList();
  }

  /// Gets company info by ticker.
  Company? getCompany(String ticker) {
    _ensureOpen();
    final results = _database!.select(
      'SELECT ticker, name, sector, last_updated FROM companies WHERE ticker = ?',
      [ticker],
    );

    if (results.isEmpty) return null;
    return Company.fromMap(results.first);
  }

  /// Gets financial history for a ticker (up to 11 years for 10yr calculations).
  List<Financial> getFinancials(String ticker, {int limit = 11}) {
    _ensureOpen();
    final results = _database!.select(
      '''
      SELECT ticker, year, revenue, net_income, eps_diluted, total_equity,
             cash_flow_ops, free_cash_flow, capital_exp, roic, shares_outstanding
      FROM financials
      WHERE ticker = ?
      ORDER BY year DESC
      LIMIT ?
      ''',
      [ticker, limit],
    );

    return results.map((row) => Financial.fromMap(row)).toList();
  }

  /// Searches for tickers matching a query.
  List<Company> searchTickers(String query) {
    _ensureOpen();
    final searchPattern = '%${query.toUpperCase()}%';
    final results = _database!.select(
      '''
      SELECT ticker, name, sector, last_updated 
      FROM companies 
      WHERE ticker LIKE ? OR UPPER(name) LIKE ?
      ORDER BY ticker
      LIMIT 20
      ''',
      [searchPattern, searchPattern],
    );

    return results.map((row) => Company.fromMap(row)).toList();
  }

  /// Gets CEO letters to shareholders for a ticker, ordered by fiscal year descending.
  /// Returns an empty list if the ceo_letters table doesn't exist yet
  /// (Updater hasn't been run with --letters).
  List<CeoLetter> getCeoLetters(String ticker) {
    _ensureOpen();
    try {
      final results = _database!.select(
        '''
        SELECT ticker, fiscal_year, filing_date, raw_excerpt, summary, fetched_at
        FROM ceo_letters
        WHERE ticker = ?
        ORDER BY fiscal_year DESC
        ''',
        [ticker],
      );

      return results.map((row) => CeoLetter.fromMap(row)).toList();
    } catch (e) {
      // Table may not exist if Updater hasn't been run with --letters
      return [];
    }
  }

  /// Checks if CEO letters are available for any ticker.
  bool hasCeoLettersTable() {
    _ensureOpen();
    try {
      _database!.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='ceo_letters'",
      );
      final results = _database!.select(
        "SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name='ceo_letters'",
      );
      return results.isNotEmpty && (results.first['cnt'] as int) > 0;
    } catch (e) {
      return false;
    }
  }

  void _ensureOpen() {
    if (_database == null) {
      open();
    }
  }
}

/// Exception thrown when the database is not found.
class DatabaseNotFoundException implements Exception {
  final String message;
  DatabaseNotFoundException(this.message);

  @override
  String toString() => message;
}
