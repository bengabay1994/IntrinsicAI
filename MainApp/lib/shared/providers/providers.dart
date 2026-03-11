import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_service.dart';
import '../../core/database/models/ceo_letter.dart';
import '../../core/analysis/rule1_analyzer.dart';
import '../../core/analysis/models/analysis_result.dart';

/// Provider for the database service.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(() => service.close());
  return service;
});

/// Provider for the Rule #1 analyzer.
final analyzerProvider = Provider<Rule1Analyzer>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return Rule1Analyzer(dbService);
});

/// Provider to check if database exists.
final databaseExistsProvider = Provider<bool>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.databaseExists();
});

/// State for the current analysis.
class AnalysisState {
  final bool isLoading;
  final AnalysisResult? result;
  final String? error;

  const AnalysisState({
    this.isLoading = false,
    this.result,
    this.error,
  });

  AnalysisState copyWith({
    bool? isLoading,
    AnalysisResult? result,
    String? error,
  }) {
    return AnalysisState(
      isLoading: isLoading ?? this.isLoading,
      result: result,
      error: error,
    );
  }
}

/// Notifier for managing analysis state.
class AnalysisNotifier extends StateNotifier<AnalysisState> {
  final Rule1Analyzer _analyzer;

  AnalysisNotifier(this._analyzer) : super(const AnalysisState());

  Future<void> analyze(String ticker) async {
    state = const AnalysisState(isLoading: true);

    try {
      final result = _analyzer.analyze(ticker);
      state = AnalysisState(result: result);
    } catch (e) {
      state = AnalysisState(error: e.toString());
    }
  }

  void clear() {
    state = const AnalysisState();
  }
}

/// Provider for analysis state.
final analysisProvider = StateNotifierProvider<AnalysisNotifier, AnalysisState>(
  (ref) {
    final analyzer = ref.watch(analyzerProvider);
    return AnalysisNotifier(analyzer);
  },
);

/// Provider for the current ticker being searched.
final tickerSearchProvider = StateProvider<String>((ref) => '');

/// State for CEO letters.
class CeoLetterState {
  final bool isLoading;
  final List<CeoLetter> letters;
  final String? error;

  const CeoLetterState({
    this.isLoading = false,
    this.letters = const [],
    this.error,
  });
}

/// Notifier for loading CEO letters from the database.
class CeoLetterNotifier extends StateNotifier<CeoLetterState> {
  final DatabaseService _dbService;

  CeoLetterNotifier(this._dbService) : super(const CeoLetterState());

  void loadLetters(String ticker) {
    state = const CeoLetterState(isLoading: true);

    try {
      final letters = _dbService.getCeoLetters(ticker);
      state = CeoLetterState(letters: letters);
    } catch (e) {
      state = CeoLetterState(error: e.toString());
    }
  }

  void clear() {
    state = const CeoLetterState();
  }
}

/// Provider for CEO letter state.
final ceoLetterProvider =
    StateNotifierProvider<CeoLetterNotifier, CeoLetterState>((ref) {
      final dbService = ref.watch(databaseServiceProvider);
      return CeoLetterNotifier(dbService);
    });
