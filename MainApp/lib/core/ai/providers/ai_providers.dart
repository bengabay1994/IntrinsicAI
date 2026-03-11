import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/token_storage_service.dart';
import '../services/oauth_service.dart';
import '../services/gemini_service.dart';
import '../gemini_oauth_config.dart';

/// Provider for token storage service.
final tokenStorageProvider = Provider<TokenStorageService>((ref) {
  return TokenStorageService();
});

/// Provider for OAuth service.
final oauthServiceProvider = Provider<OAuthService>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return OAuthService(tokenStorage: tokenStorage);
});

/// Provider for Gemini service.
final geminiServiceProvider = Provider<GeminiService>((ref) {
  final oauthService = ref.watch(oauthServiceProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  return GeminiService(oauthService: oauthService, tokenStorage: tokenStorage);
});

/// Authentication state.
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? userEmail;
  final String? error;
  final String selectedModel;
  final String? managedProjectId;
  final List<GeminiModel> availableModels;
  final bool isLoadingModels;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.userEmail,
    this.error,
    this.selectedModel = 'gemini-2.5-flash',
    this.managedProjectId,
    this.availableModels = const [],
    this.isLoadingModels = false,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? userEmail,
    String? error,
    String? selectedModel,
    String? managedProjectId,
    List<GeminiModel>? availableModels,
    bool? isLoadingModels,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      userEmail: userEmail,
      error: error,
      selectedModel: selectedModel ?? this.selectedModel,
      managedProjectId: managedProjectId ?? this.managedProjectId,
      availableModels: availableModels ?? this.availableModels,
      isLoadingModels: isLoadingModels ?? this.isLoadingModels,
    );
  }
}

/// Notifier for managing authentication state.
class AuthNotifier extends StateNotifier<AuthState> {
  final OAuthService _oauthService;
  final GeminiService _geminiService;

  AuthNotifier(this._oauthService, this._geminiService) : super(const AuthState()) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      // Load selected model from storage
      final storedModel = await _oauthService.getSelectedModel();
      String currentModel = storedModel ?? GeminiOAuthConfig.defaultModel;

      // Load managed project ID
      final managedProjectId = await _oauthService.getManagedProjectId();

      final token = await _oauthService.getCurrentToken();
      if (token != null && token.isValid) {
        state = AuthState(
          isAuthenticated: true,
          userEmail: token.userEmail,
          selectedModel: currentModel,
          managedProjectId: managedProjectId,
        );
        // Fetch available models in background
        _fetchAvailableModels();
      } else if (token != null && token.refreshToken != null) {
        // Try to refresh
        final result = await _oauthService.refreshAccessToken();
        if (result.success) {
          state = AuthState(
            isAuthenticated: true,
            userEmail: result.token?.userEmail,
            selectedModel: currentModel,
            managedProjectId: managedProjectId,
          );
          // Fetch available models in background
          _fetchAvailableModels();
        } else {
          state = AuthState(
            isAuthenticated: false,
            selectedModel: currentModel,
            managedProjectId: managedProjectId,
          );
        }
      } else {
        state = AuthState(
          isAuthenticated: false,
          selectedModel: currentModel,
          managedProjectId: managedProjectId,
        );
      }
    } catch (e) {
      state = AuthState(isAuthenticated: false, error: e.toString());
    }
  }

  Future<void> _fetchAvailableModels() async {
    state = state.copyWith(isLoadingModels: true);
    try {
      final models = await _geminiService.fetchAvailableModels();
      
      // Validate selected model exists in the list
      String validModel = state.selectedModel;
      if (!models.any((m) => m.id == validModel)) {
        validModel = GeminiOAuthConfig.defaultModel;
        await _oauthService.saveSelectedModel(validModel);
      }
      
      state = state.copyWith(
        availableModels: models,
        selectedModel: validModel,
        isLoadingModels: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingModels: false);
    }
  }

  Future<void> refreshModels() async {
    _geminiService.clearCache();
    await _fetchAvailableModels();
  }

  Future<void> signIn() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _oauthService.startAuthFlow();
      if (result.success) {
        state = AuthState(
          isAuthenticated: true,
          userEmail: result.token?.userEmail,
          selectedModel: GeminiOAuthConfig.defaultModel,
        );
        // Fetch available models after sign in
        _fetchAvailableModels();
      } else {
        state = AuthState(isAuthenticated: false, error: result.error);
      }
    } catch (e) {
      state = AuthState(isAuthenticated: false, error: e.toString());
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    await _oauthService.signOut();
    _geminiService.clearCache();
    state = const AuthState(isAuthenticated: false);
  }

  Future<void> updateModel(String model) async {
    await _oauthService.saveSelectedModel(model);
    state = state.copyWith(selectedModel: model);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Provider for authentication state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final oauthService = ref.watch(oauthServiceProvider);
  final geminiService = ref.watch(geminiServiceProvider);
  return AuthNotifier(oauthService, geminiService);
});

/// AI Analysis state.
class AiInsightState {
  final bool isLoading;
  final String? insight;
  final String? error;

  const AiInsightState({this.isLoading = false, this.insight, this.error});

  AiInsightState copyWith({bool? isLoading, String? insight, String? error}) {
    return AiInsightState(
      isLoading: isLoading ?? this.isLoading,
      insight: insight,
      error: error,
    );
  }
}

/// Notifier for managing AI insight generation.
class AiInsightNotifier extends StateNotifier<AiInsightState> {
  final GeminiService _geminiService;

  AiInsightNotifier(this._geminiService) : super(const AiInsightState());

  Future<void> generateInsight({
    required String ticker,
    required String companyName,
    required Map<String, dynamic> analysisData,
  }) async {
    state = const AiInsightState(isLoading: true);

    final result = await _geminiService.analyzeStock(
      ticker: ticker,
      companyName: companyName,
      analysisData: analysisData,
    );

    if (result.success) {
      state = AiInsightState(insight: result.response);
    } else {
      state = AiInsightState(error: result.error);
    }
  }

  void clear() {
    state = const AiInsightState();
  }
}

/// Provider for AI insight state.
final aiInsightProvider =
    StateNotifierProvider<AiInsightNotifier, AiInsightState>((ref) {
      final geminiService = ref.watch(geminiServiceProvider);
      return AiInsightNotifier(geminiService);
    });
