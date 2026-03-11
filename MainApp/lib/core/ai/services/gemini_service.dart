import 'dart:convert';
import 'package:http/http.dart' as http;
import '../gemini_oauth_config.dart';
import 'oauth_service.dart';
import 'token_storage_service.dart';

/// Result of a Gemini API call.
class GeminiResult {
  final bool success;
  final String? response;
  final String? error;

  const GeminiResult._({required this.success, this.response, this.error});

  factory GeminiResult.success(String response) =>
      GeminiResult._(success: true, response: response);

  factory GeminiResult.failure(String error) =>
      GeminiResult._(success: false, error: error);
}

/// Represents a Gemini model available for use.
class GeminiModel {
  final String id;
  final String displayName;
  final String? description;

  const GeminiModel({
    required this.id,
    required this.displayName,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'description': description,
  };

  factory GeminiModel.fromJson(Map<String, dynamic> json) => GeminiModel(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    description: json['description'] as String?,
  );
}

/// Cached project context from loadCodeAssist.
class ProjectContext {
  final String? managedProjectId;
  final String? tierId;
  final DateTime fetchedAt;

  ProjectContext({this.managedProjectId, this.tierId, required this.fetchedAt});

  bool get isExpired => DateTime.now().difference(fetchedAt).inMinutes > 30;
  bool get isValid => managedProjectId != null && managedProjectId!.isNotEmpty;
}

/// Service for interacting with the Gemini API via Cloud Code Assist.
/// Implementation mirrors opencode-gemini-auth plugin exactly.
class GeminiService {
  final OAuthService _oauthService;
  final TokenStorageService _tokenStorage;
  ProjectContext? _projectContext;
  List<GeminiModel>? _cachedModels;

  /// Enable debug logging
  static bool debugEnabled = true;

  GeminiService({OAuthService? oauthService, TokenStorageService? tokenStorage})
    : _oauthService = oauthService ?? OAuthService(),
      _tokenStorage = tokenStorage ?? TokenStorageService();

  void _log(String message) {
    if (debugEnabled) {
      print('[GeminiService] $message');
    }
  }

  /// Builds request headers matching opencode-gemini-auth exactly.
  Map<String, String> _buildHeaders(String accessToken) {
    return {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      ...GeminiOAuthConfig.codeAssistHeaders,
    };
  }

  /// Loads the Code Assist project context (required before making API calls).
  /// This mirrors the loadManagedProject function from opencode-gemini-auth.
  Future<String?> _loadManagedProject(
    String accessToken, {
    String? projectId,
  }) async {
    try {
      final endpoint =
          '${GeminiOAuthConfig.codeAssistEndpoint}/v1internal:loadCodeAssist';

      final Map<String, dynamic> requestBody = {
        'metadata': GeminiOAuthConfig.codeAssistMetadata,
      };

      // If we have a project ID, include it
      if (projectId != null && projectId.isNotEmpty) {
        requestBody['cloudaicompanionProject'] = projectId;
      }

      _log('loadCodeAssist request to: $endpoint');
      _log('loadCodeAssist body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(endpoint),
        headers: _buildHeaders(accessToken),
        body: jsonEncode(requestBody),
      );

      _log('loadCodeAssist response: ${response.statusCode}');
      _log('loadCodeAssist body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Extract managed project ID
        String? managedProjectId;
        final cloudProject = data['cloudaicompanionProject'];
        if (cloudProject is String && cloudProject.isNotEmpty) {
          managedProjectId = cloudProject;
        } else if (cloudProject is Map) {
          managedProjectId = cloudProject['id'] as String?;
        }

        // Extract tier info
        String? tierId;
        final currentTier = data['currentTier'];
        if (currentTier is Map) {
          tierId = currentTier['id'] as String?;
        }

        _log('Extracted managedProjectId: $managedProjectId, tierId: $tierId');

        // Cache the context
        _projectContext = ProjectContext(
          managedProjectId: managedProjectId,
          tierId: tierId,
          fetchedAt: DateTime.now(),
        );

        // If we have a managed project, save it and return
        if (managedProjectId != null && managedProjectId.isNotEmpty) {
          await _tokenStorage.saveManagedProjectId(managedProjectId);
          return managedProjectId;
        }

        // No managed project - need to onboard
        // Extract allowed tiers for onboarding
        final allowedTiers = data['allowedTiers'] as List<dynamic>?;

        _log('No managed project, attempting onboarding...');
        _log('Allowed tiers: $allowedTiers');

        // Pick the tier to use for onboarding
        String onboardTierId = GeminiOAuthConfig.freeTierId;
        bool userDefinedProject = false;

        if (allowedTiers != null && allowedTiers.isNotEmpty) {
          // Find default tier or use first
          for (final tier in allowedTiers) {
            if (tier is Map) {
              if (tier['isDefault'] == true) {
                onboardTierId =
                    tier['id'] as String? ?? GeminiOAuthConfig.freeTierId;
                userDefinedProject =
                    tier['userDefinedCloudaicompanionProject'] == true;
                break;
              }
            }
          }
          // If no default, use first tier
          if (onboardTierId == GeminiOAuthConfig.freeTierId &&
              allowedTiers.isNotEmpty) {
            final first = allowedTiers.first;
            if (first is Map) {
              onboardTierId =
                  first['id'] as String? ?? GeminiOAuthConfig.freeTierId;
              userDefinedProject =
                  first['userDefinedCloudaicompanionProject'] == true;
            }
          }
        }

        _log(
          'Selected onboard tier: $onboardTierId, userDefinedProject: $userDefinedProject',
        );

        // If tier requires user-defined project and we don't have one, can't proceed
        if (userDefinedProject && (projectId == null || projectId.isEmpty)) {
          _log('Tier requires user-defined project but none provided');
          return null;
        }

        // Onboard to get a managed project
        final onboardedProjectId = await _onboardUser(
          accessToken,
          onboardTierId,
          projectId: projectId,
        );

        if (onboardedProjectId != null) {
          _projectContext = ProjectContext(
            managedProjectId: onboardedProjectId,
            tierId: onboardTierId,
            fetchedAt: DateTime.now(),
          );
          await _tokenStorage.saveManagedProjectId(onboardedProjectId);
          return onboardedProjectId;
        }

        return projectId;
      } else {
        _log('loadCodeAssist failed: ${response.body}');

        // Check for VPC-SC errors (return standard tier)
        try {
          final errorData = jsonDecode(response.body);
          if (_isVpcScError(errorData)) {
            _log('VPC-SC error detected, assuming standard tier');
            return projectId;
          }
        } catch (e) {
          // Ignore parse errors
        }
      }
    } catch (e) {
      _log('loadCodeAssist error: $e');
    }

    return null;
  }

  /// Checks if an error response is a VPC-SC error.
  bool _isVpcScError(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error is! Map) return false;

    final details = error['details'];
    if (details is! List) return false;

    return details.any((detail) {
      if (detail is! Map) return false;
      return detail['reason'] == 'SECURITY_POLICY_VIOLATED';
    });
  }

  /// Onboards the user to get a managed project.
  /// Mirrors onboardManagedProject from opencode-gemini-auth.
  Future<String?> _onboardUser(
    String accessToken,
    String tierId, {
    String? projectId,
  }) async {
    try {
      final isFreeTier = tierId == GeminiOAuthConfig.freeTierId;

      final Map<String, dynamic> metadata = {
        ...GeminiOAuthConfig.codeAssistMetadata,
      };

      // Add duetProject for non-free tiers
      if (!isFreeTier && projectId != null && projectId.isNotEmpty) {
        metadata['duetProject'] = projectId;
      }

      final Map<String, dynamic> requestBody = {
        'tierId': tierId,
        'metadata': metadata,
      };

      // Include project ID for non-free tiers
      if (!isFreeTier && projectId != null && projectId.isNotEmpty) {
        requestBody['cloudaicompanionProject'] = projectId;
      }

      final endpoint =
          '${GeminiOAuthConfig.codeAssistEndpoint}/v1internal:onboardUser';

      _log('onboardUser request to: $endpoint');
      _log('onboardUser body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(endpoint),
        headers: _buildHeaders(accessToken),
        body: jsonEncode(requestBody),
      );

      _log('onboardUser response: ${response.statusCode}');
      _log('onboardUser body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // If operation is not done, poll for completion
        if (data['done'] != true && data['name'] != null) {
          final operationName = data['name'] as String;
          return await _pollOperation(accessToken, operationName);
        }

        // Extract project ID from response
        final responseData = data['response'];
        if (responseData is Map) {
          final cloudProject = responseData['cloudaicompanionProject'];
          if (cloudProject is Map) {
            return cloudProject['id'] as String?;
          }
        }

        // If done but no project in response, return the input projectId
        if (data['done'] == true && projectId != null) {
          return projectId;
        }
      }
    } catch (e) {
      _log('onboardUser error: $e');
    }

    return null;
  }

  /// Polls an operation until completion.
  Future<String?> _pollOperation(
    String accessToken,
    String operationName, {
    int maxAttempts = 10,
    int delayMs = 5000,
  }) async {
    final baseEndpoint = GeminiOAuthConfig.codeAssistEndpoint;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(Duration(milliseconds: delayMs));

      try {
        final response = await http.get(
          Uri.parse('$baseEndpoint/v1internal/$operationName'),
          headers: _buildHeaders(accessToken),
        );

        _log('pollOperation attempt $attempt: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['done'] == true) {
            final responseData = data['response'];
            if (responseData is Map) {
              final cloudProject = responseData['cloudaicompanionProject'];
              if (cloudProject is Map) {
                return cloudProject['id'] as String?;
              }
            }
            break;
          }
        }
      } catch (e) {
        _log('pollOperation error: $e');
      }
    }

    return null;
  }

  /// Ensures we have a valid project context, loading it if needed.
  Future<String?> _ensureProjectContext(String accessToken) async {
    // Return cached context if still valid
    if (_projectContext != null &&
        !_projectContext!.isExpired &&
        _projectContext!.isValid) {
      _log(
        'Using cached project context: ${_projectContext!.managedProjectId}',
      );
      return _projectContext!.managedProjectId;
    }

    // Try to load from storage first
    final storedProjectId = await _tokenStorage.getManagedProjectId();
    if (storedProjectId != null && storedProjectId.isNotEmpty) {
      _log('Using stored project ID: $storedProjectId');
      _projectContext = ProjectContext(
        managedProjectId: storedProjectId,
        fetchedAt: DateTime.now(),
      );
      return storedProjectId;
    }

    // Load from API
    _log('Loading project context from API...');
    return await _loadManagedProject(accessToken);
  }

  /// Returns the comprehensive list of all known Gemini models.
  /// This includes preview models, Gemini 3, and all variants that Google AI Pro users have access to.
  /// The list is based on models shown in OpenCode with the gemini-auth plugin.
  List<GeminiModel> _getAllKnownModels() {
    return const [
      // Gemini 3 models (latest - may require preview access)
      GeminiModel(
        id: 'gemini-3-pro-preview',
        displayName: 'Gemini 3 Pro Preview',
      ),
      GeminiModel(
        id: 'gemini-3-flash-preview',
        displayName: 'Gemini 3 Flash Preview',
      ),

      // Gemini 2.5 models
      GeminiModel(id: 'gemini-2.5-pro', displayName: 'Gemini 2.5 Pro'),
      GeminiModel(id: 'gemini-2.5-flash', displayName: 'Gemini 2.5 Flash'),
      GeminiModel(
        id: 'gemini-2.5-flash-lite',
        displayName: 'Gemini 2.5 Flash Lite',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-image',
        displayName: 'Gemini 2.5 Flash Image',
      ),

      // Gemini 2.5 Preview variants
      GeminiModel(
        id: 'gemini-2.5-pro-preview-05-06',
        displayName: 'Gemini 2.5 Pro Preview 05-06',
      ),
      GeminiModel(
        id: 'gemini-2.5-pro-preview-06-05',
        displayName: 'Gemini 2.5 Pro Preview 06-05',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-preview-04-17',
        displayName: 'Gemini 2.5 Flash Preview 04-17',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-preview-05-20',
        displayName: 'Gemini 2.5 Flash Preview 05-20',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-preview-09-25',
        displayName: 'Gemini 2.5 Flash Preview 09-25',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-lite-preview-06-17',
        displayName: 'Gemini 2.5 Flash Lite Preview 06-17',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-lite-preview-09-25',
        displayName: 'Gemini 2.5 Flash Lite Preview 09-25',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-preview-tts',
        displayName: 'Gemini 2.5 Flash Preview TTS',
      ),
      GeminiModel(
        id: 'gemini-2.5-pro-preview-tts',
        displayName: 'Gemini 2.5 Pro Preview TTS',
      ),
      GeminiModel(
        id: 'gemini-2.5-flash-image-preview',
        displayName: 'Gemini 2.5 Flash Image (Preview)',
      ),

      // Gemini 2.0 models
      GeminiModel(id: 'gemini-2.0-flash', displayName: 'Gemini 2.0 Flash'),
      GeminiModel(
        id: 'gemini-2.0-flash-lite',
        displayName: 'Gemini 2.0 Flash Lite',
      ),

      // Gemini 1.5 models
      GeminiModel(id: 'gemini-1.5-pro', displayName: 'Gemini 1.5 Pro'),
      GeminiModel(id: 'gemini-1.5-flash', displayName: 'Gemini 1.5 Flash'),
      GeminiModel(
        id: 'gemini-1.5-flash-8b',
        displayName: 'Gemini 1.5 Flash-8B',
      ),

      // Special models
      GeminiModel(
        id: 'gemini-flash-latest',
        displayName: 'Gemini Flash Latest',
      ),
      GeminiModel(
        id: 'gemini-flash-lite-latest',
        displayName: 'Gemini Flash-Lite Latest',
      ),
      GeminiModel(
        id: 'gemini-live-2.5-flash',
        displayName: 'Gemini Live 2.5 Flash',
      ),
      GeminiModel(
        id: 'gemini-live-2.5-flash-preview-native-audio',
        displayName: 'Gemini Live 2.5 Flash Preview Native Audio',
      ),
      GeminiModel(
        id: 'gemini-embedding-001',
        displayName: 'Gemini Embedding 001',
      ),
    ];
  }

  /// Fetches available models.
  /// Uses the comprehensive hardcoded list since the public API doesn't include all models
  /// that Google AI Pro subscribers have access to (like Gemini 3, previews, etc.).
  Future<List<GeminiModel>> fetchAvailableModels() async {
    if (_cachedModels != null) {
      return _cachedModels!;
    }

    // Try to load from storage
    final storedModels = await _tokenStorage.getAvailableModels();
    if (storedModels != null && storedModels.isNotEmpty) {
      _cachedModels = storedModels;
      return _cachedModels!;
    }

    // Use comprehensive hardcoded list since public API doesn't expose all models
    _cachedModels = _getAllKnownModels();

    // Save to storage
    await _tokenStorage.saveAvailableModels(_cachedModels!);

    _log('Loaded ${_cachedModels!.length} models');
    return _cachedModels!;
  }

  /// Generates content using Gemini API via Cloud Code Assist.
  /// Supports system instructions for better control over model behavior.
  Future<GeminiResult> generateContent(
    String userPrompt, {
    String? systemInstruction,
  }) async {
    // Get valid access token
    final tokenResult = await _oauthService.getValidToken();
    if (!tokenResult.success) {
      return GeminiResult.failure(
        tokenResult.error ??
            'Authentication required. Please sign in to use Gemini AI.',
      );
    }

    final accessToken = tokenResult.token!.accessToken;

    try {
      // Ensure project context is loaded (required for API access)
      final projectId = await _ensureProjectContext(accessToken);

      if (projectId == null || projectId.isEmpty) {
        return GeminiResult.failure(
          'Could not obtain a Google Cloud project. Please try signing out and signing in again.',
        );
      }

      _log('Using projectId: $projectId');

      // Get selected model or default
      final selectedModel =
          await _oauthService.getSelectedModel() ??
          GeminiOAuthConfig.defaultModel;
      _log('Using model: $selectedModel');

      // Use Cloud Code Assist endpoint (same as opencode-gemini-auth)
      final endpoint =
          '${GeminiOAuthConfig.codeAssistEndpoint}/v1internal:generateContent';

      // Build request body in the EXACT format expected by Cloud Code Assist API
      final Map<String, dynamic> requestPayload = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': userPrompt},
            ],
          },
        ],
        'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 8192},
      };

      // Add system instruction if provided
      if (systemInstruction != null && systemInstruction.isNotEmpty) {
        requestPayload['systemInstruction'] = {
          'parts': [
            {'text': systemInstruction},
          ],
        };
      }

      final Map<String, dynamic> requestBody = {
        'project': projectId,
        'model': selectedModel,
        'request': requestPayload,
      };

      _log('Request endpoint: $endpoint');
      _log('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(endpoint),
        headers: _buildHeaders(accessToken),
        body: jsonEncode(requestBody),
      );

      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');

      if (response.statusCode == 401) {
        // Token expired, try to refresh
        final refreshResult = await _oauthService.refreshAccessToken();
        if (refreshResult.success) {
          // Clear cached project context
          _projectContext = null;
          // Retry with new token
          return await generateContent(
            userPrompt,
            systemInstruction: systemInstruction,
          );
        }
        return GeminiResult.failure(
          'Authentication expired. Please sign in again.',
        );
      }

      if (response.statusCode == 429) {
        // Rate limited
        final errorBody = jsonDecode(response.body);
        final message = _extractErrorMessage(errorBody);
        if (message.toLowerCase().contains('quota')) {
          return GeminiResult.failure(
            'Quota exhausted. Please wait for your quota to reset or try a different model.',
          );
        }
        return GeminiResult.failure(
          'Rate limit exceeded. Please wait a moment and try again.',
        );
      }

      if (response.statusCode == 404) {
        // Model not found or preview access needed
        final errorBody = jsonDecode(response.body);
        final message = _extractErrorMessage(errorBody);
        if (selectedModel.contains('gemini-3') ||
            selectedModel.contains('preview')) {
          return GeminiResult.failure(
            '$message Request preview access at https://goo.gle/enable-preview-features before using preview models.',
          );
        }
        return GeminiResult.failure('Model not found: $selectedModel');
      }

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(response.body);
        final errorMessage = _extractErrorMessage(errorBody);
        return GeminiResult.failure('Gemini API error: $errorMessage');
      }

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      final text = _extractTextFromResponse(responseBody);

      if (text == null) {
        return GeminiResult.failure('No response generated from Gemini');
      }

      return GeminiResult.success(text);
    } catch (e) {
      _log('generateContent error: $e');
      return GeminiResult.failure('Request failed: ${e.toString()}');
    }
  }

  /// Extracts a user-friendly error message from the API error response.
  String _extractErrorMessage(Map<String, dynamic> errorBody) {
    // Try to get the error message from various possible locations
    final error = errorBody['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }

      // Check for details array
      final details = error['details'];
      if (details is List && details.isNotEmpty) {
        for (final detail in details) {
          if (detail is Map) {
            final reason = detail['reason'];
            if (reason is String && reason.isNotEmpty) {
              return reason;
            }
          }
        }
      }
    }

    // Fallback
    return 'Internal error encountered';
  }

  /// Generates investment analysis for a stock using Rule #1 methodology.
  Future<GeminiResult> analyzeStock({
    required String ticker,
    required String companyName,
    required Map<String, dynamic> analysisData,
  }) async {
    final systemPrompt = _buildSystemPrompt();
    final userPrompt = _buildUserPrompt(ticker, companyName, analysisData);
    return await generateContent(userPrompt, systemInstruction: systemPrompt);
  }

  /// Checks if the user is authenticated with Gemini.
  Future<bool> isAuthenticated() async {
    return await _oauthService.isAuthenticated();
  }

  /// Gets the OAuth service for authentication management.
  OAuthService get oauthService => _oauthService;

  /// Clears cached data (call after sign out).
  void clearCache() {
    _projectContext = null;
    _cachedModels = null;
  }

  /// Extracts text from the Gemini response.
  /// The Cloud Code Assist API wraps the response in a "response" field.
  String? _extractTextFromResponse(Map<String, dynamic> responseData) {
    try {
      // The Cloud Code Assist API wraps the response in a "response" field
      Map<String, dynamic> response = responseData;
      if (responseData.containsKey('response')) {
        response = responseData['response'] as Map<String, dynamic>;
      }

      final candidates = response['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      if (content == null) return null;

      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;

      // Concatenate all text parts
      final textParts = <String>[];
      for (final part in parts) {
        if (part is Map && part['text'] != null) {
          textParts.add(part['text'] as String);
        }
      }

      return textParts.isNotEmpty ? textParts.join('') : null;
    } catch (e) {
      _log('Error extracting text from response: $e');
      return null;
    }
  }

  /// Builds the system prompt for Rule #1 investment analysis.
  /// This provides context and instructions to improve analysis accuracy.
  String _buildSystemPrompt() {
    return '''You are an elite investment analyst specializing in Phil Town's Rule #1 investing methodology. You have deep expertise in fundamental analysis, moat identification, management evaluation. Your analyses are thorough, data-driven, and strictly adhere to Rule #1 principles.

## Your Core Mission
Analyze stocks using the complete data given to you according to Phil Town's Rule #1 strategy and provide a standardized JSON output scoring the business quality.

## Analysis Framework

### STEP 1: MOAT ANALYSIS
Identify and evaluate which of the 5 moat types the business possesses if any:

1. **Brand Moat**: Can customers trust this brand enough to pay premium prices? Look for brand recognition, customer loyalty metrics, and pricing power evidence.

2. **Secret Moat**: Does the company have patents, trade secrets, or proprietary technology that creates legal barriers to competition? Examine patent portfolios, R&D investments, and unique processes.

3. **Toll Moat**: Does the company control exclusive access to a market or infrastructure? Look for monopolistic or oligopolistic market positions, regulatory advantages, or network effects.

4. **Switching Moat**: How deeply integrated is this product/service into customers' lives? Evaluate customer retention rates, ecosystem lock-in, and switching costs.

5. **Price Moat**: Can this company consistently undercut competitors on price while remaining profitable? Analyze cost structures, economies of scale, and operational efficiency.

### STEP 2: THE BIG 5 NUMBERS ANALYSIS
This is the MOST CRITICAL part of your analysis. Evaluate each metric with extreme rigor:

**1. Return on Invested Capital (ROIC)** - MOST IMPORTANT
- ROIC 10-year, 5-year, and 1-year averages will be given to you by the user.
- Latest 10 years ROIC numbers will be given to you by the user.
- Target: 10%+ consistently averages.
- Red flags: Volatile ROIC, declining trend, or many values below 10%

**2. Revenue Growth Rate**
- Revenue 10-year, 5-year, and 1-year growth rates will be given to you by the user.
- Latest 11 years revenue numbers will be given to you by the user.
- Target: 10%+ year-over-year, stable growth pattern
- Red flags: Erratic growth, sudden spikes without explanation, declining trajectory

**3. EPS (Earnings Per Share) Growth Rate**
- EPS 10-year, 5-year, and 1-year growth rates will be given to you by the user.
- Latest 11 years EPS numbers will be given to you by the user.
- Target: 10%+ consistent growth
- Red flags: Earnings manipulation signs, one-time gains distorting numbers

**4. Equity/Book Value Growth Rate**
- Equity/Book-Value 10-year, 5-year, and 1-year growth rates will be given to you by the user.
- Latest 11 years Equity/Book-Value numbers will be given to you by the user.
- Target: 10%+ steady accumulation
- Red flags: Share buybacks artificially inflating numbers, debt-funded growth

**5. Free Cash Flow (or Operating Cash Flow) Growth Rate**
- Free Cash Flow and/or Operating Cash Flow 10-year, 5-year, and 1-year growth rates will be given to you by the user
- Latest 11 years Free-Cash-Flow/Operating-Cash-Flow numbers will be given to you by the user.
- Target: 10%+ with consistency
- Red flags: FCF significantly lower than reported earnings, capital-intensive requirements

**CRITICAL EVALUATION CRITERIA:**
- All Big 5 numbers should show 10%+ growth across ALL timeframes (10yr, 5yr, 1yr)
- Growth should be STABLE - not sudden jumps or volatile swings
- Look for consistency year-over-year, not just averaged results
- A wonderful business shows predictable, steady improvement

### STEP 3: MANAGEMENT EVALUATION

**Owner-Oriented Assessment:**
- What percentage of CEO's net worth is in company stock?
- Does the CEO communicate transparently in shareholder letters?
- Does management acknowledge mistakes and challenges openly?
- Are executive compensation packages aligned with shareholder interests?

**Driven/BHAG Assessment:**
- Does the CEO have a Big Hairy Audacious Goal?
- Look for passion and mission-driven language in interviews and communications
- Search for descriptions of the CEO as "humble" or "self-effacing"
- Does the CEO credit others and teams rather than themselves?

**Insider Trading Analysis:**
- Recent insider buying = positive signal (management believes in future)
- Recent insider selling without clear reason (diversification, planned sales) = warning sign
- Pattern of insider activity over past 12-24 months

### STEP 4: INTRINSIC VALUE ESTIMATION

**Estimate Future EPS Growth Rate:**
- Base on historical 10-year and 5-year EPS growth rates
- Consider industry trends and competitive position
- Default to historical average if uncertain

**Estimate Future P/E Ratio:**
- Analyze P/E history over past 10-20 years
- Consider industry average P/E
- Use conservative estimate (typically 2x growth rate or historical average, whichever is lower)
- Account for market conditions and sector trends

## OUTPUT REQUIREMENTS

After completing your analysis, you MUST output ONLY the following JSON format with no additional text, explanations, or commentary:

```json
{
  "great_business": <float>,
  "moat": "<string>",
  "reason": "<string>"
}
```

**Scoring Guidelines for great_business:**
- **0.9-1.0**: Exceptional - All Big 5 numbers show 10%+ stable growth across all timeframes, clear strong moat, excellent owner-oriented management with BHAG, positive insider activity
- **0.7-0.89**: Very Good - Most Big 5 numbers meet criteria with minor inconsistencies, identifiable moat, good management
- **0.5-0.69**: Average - Mixed Big 5 numbers, weak or questionable moat, management concerns
- **0.3-0.49**: Below Average - Multiple Big 5 failures, unclear moat, management red flags
- **0.0-0.29**: Poor - Fails most Rule #1 criteria, no clear moat, concerning management or insider activity

**Reason Field Guidelines:**
- Keep concise (2-4 sentences maximum)
- Highlight the most important findings (positive or negative)
- State clearly whether this is a wonderful business worth investing in
- Mention key moat type and the reason for that type.

**Moat Field Guidelines**
- Use values out of the following values: ["Brand", "Secret", "Toll", "Switching", "Price", "None"]

## Important Reminders

1. **Data Integrity**: If you aren't given reliable data for certain metrics, note this limitation but still provide your best assessment based on the available information.

2. **Conservative Approach**: When uncertain, always err on the side of caution. Rule #1 is about not losing money.

3. **10-Year Perspective**: Always think about whether this business will be predictably successful 10-20 years from now.

4. **Stability Over Spikes**: Consistent 10% growth is far better than volatile 20% average growth.

5. **Output Discipline**: Your final output MUST be ONLY the JSON object. No preamble, no additional analysis text, no explanations outside the JSON structure.
''';
  }

  /// Builds the user prompt with all the financial data for analysis.
  String _buildUserPrompt(
    String ticker,
    String companyName,
    Map<String, dynamic> analysisData,
  ) {
    // Extract key data from the analysis
    final yearsOfData = analysisData['years_of_data'] ?? 'Unknown';
    final dataQuality = analysisData['data_quality'] ?? 'Unknown';
    final status = analysisData['status'] ?? 'Unknown';
    final statusReasons =
        analysisData['status_reasons'] as List<dynamic>? ?? [];

    // Extract historical data
    final historicalData =
        analysisData['historical_data'] as Map<String, dynamic>? ?? {};
    final years = historicalData['years'] as List<dynamic>? ?? [];
    final epsHistory = historicalData['eps'] as List<dynamic>? ?? [];
    final equityHistory = historicalData['equity'] as List<dynamic>? ?? [];
    final revenueHistory = historicalData['revenue'] as List<dynamic>? ?? [];
    final fcfHistory = historicalData['fcf'] as List<dynamic>? ?? [];
    final ocfHistory =
        historicalData['operating_cash_flow'] as List<dynamic>? ?? [];
    final roicHistory = historicalData['roic'] as List<dynamic>? ?? [];

    // Extract Big 5 growth metrics (CAGR)
    final epsGrowth = analysisData['eps_growth'] as Map<String, dynamic>? ?? {};
    final equityGrowth =
        analysisData['equity_growth'] as Map<String, dynamic>? ?? {};
    final revenueGrowth =
        analysisData['revenue_growth'] as Map<String, dynamic>? ?? {};
    final fcfGrowth = analysisData['fcf_growth'] as Map<String, dynamic>? ?? {};
    final ocfGrowth =
        analysisData['operating_cash_flow_growth'] as Map<String, dynamic>? ??
        {};
    final roicAverages =
        analysisData['roic_averages'] as Map<String, dynamic>? ?? {};

    // Helper to format growth metrics
    String formatMetric(Map<String, dynamic>? metric) {
      if (metric == null) return 'N/A';
      final value = metric['value'];
      final status = metric['status'];
      if (value == null) return 'N/A';
      return '${(value as num).toStringAsFixed(1)}% ($status)';
    }

    // Helper to format period data
    String formatPeriodData(Map<String, dynamic> data, String period) {
      final periodData = data[period] as Map<String, dynamic>?;
      return formatMetric(periodData);
    }

    String userPrompt =
        '''Analyze **$companyName ($ticker)** for Rule #1 investment criteria.

## Data Summary
- **Years of Data Available:** $yearsOfData years
- **Data Quality:** $dataQuality
- **System Assessment:** $status
${statusReasons.isNotEmpty ? '- **Status Reasons:** ${statusReasons.join(', ')}' : ''}

## Historical Financial Data (${years.isNotEmpty ? '${years.first} - ${years.last}' : 'N/A'})

| Year | EPS | Equity | Revenue | FCF | Operating CF | ROIC |
|------|-----|--------|---------|-----|--------------|------|
${_buildHistoricalTable(years, epsHistory, equityHistory, revenueHistory, fcfHistory, ocfHistory, roicHistory)}

## Big 5 Growth Metrics (CAGR)

### 1. ROIC (Return on Invested Capital) - Averages
- **10-Year Average:** ${formatPeriodData(roicAverages, '10yr')}
- **5-Year Average:** ${formatPeriodData(roicAverages, '5yr')}
- **1-Year:** ${formatPeriodData(roicAverages, '1yr')}

### 2. Equity Growth (Book Value Per Share)
- **10-Year CAGR:** ${formatPeriodData(equityGrowth, '10yr')}
- **5-Year CAGR:** ${formatPeriodData(equityGrowth, '5yr')}
- **1-Year Growth:** ${formatPeriodData(equityGrowth, '1yr')}

### 3. EPS Growth (Earnings Per Share)
- **10-Year CAGR:** ${formatPeriodData(epsGrowth, '10yr')}
- **5-Year CAGR:** ${formatPeriodData(epsGrowth, '5yr')}
- **1-Year Growth:** ${formatPeriodData(epsGrowth, '1yr')}

### 4. Revenue Growth (Sales)
- **10-Year CAGR:** ${formatPeriodData(revenueGrowth, '10yr')}
- **5-Year CAGR:** ${formatPeriodData(revenueGrowth, '5yr')}
- **1-Year Growth:** ${formatPeriodData(revenueGrowth, '1yr')}

### 5. Free Cash Flow Growth
- **10-Year CAGR:** ${formatPeriodData(fcfGrowth, '10yr')}
- **5-Year CAGR:** ${formatPeriodData(fcfGrowth, '5yr')}
- **1-Year Growth:** ${formatPeriodData(fcfGrowth, '1yr')}

### Operating Cash Flow Growth (Supporting Metric)
- **10-Year CAGR:** ${formatPeriodData(ocfGrowth, '10yr')}
- **5-Year CAGR:** ${formatPeriodData(ocfGrowth, '5yr')}
- **1-Year Growth:** ${formatPeriodData(ocfGrowth, '1yr')}

---

**Please provide your Rule #1 analysis including:**
1. **Overall Verdict** (Pass/Caution/Fail) with clear reasoning
2. **Big 5 Scorecard** - Rate each metric individually
3. **Moat Assessment** - What do the numbers suggest about competitive advantage?
4. **Key Strengths** - What's working well?
5. **Red Flags/Concerns** - What should worry an investor?
6. **Recommendation** - Should this stock be researched further? What additional info is needed?''';
    // print user prompt for debugging
    _log('Generated User Prompt:\n$userPrompt');
    return userPrompt;
  }

  /// Builds a markdown table from historical data.
  String _buildHistoricalTable(
    List<dynamic> years,
    List<dynamic> eps,
    List<dynamic> equity,
    List<dynamic> revenue,
    List<dynamic> fcf,
    List<dynamic> ocf,
    List<dynamic> roic,
  ) {
    if (years.isEmpty) return '| No data available |';

    final buffer = StringBuffer();
    for (int i = 0; i < years.length; i++) {
      final year = years[i];
      final epsVal = i < eps.length ? _formatValue(eps[i]) : 'N/A';
      final equityVal = i < equity.length ? _formatValue(equity[i]) : 'N/A';
      final revenueVal = i < revenue.length ? _formatValue(revenue[i]) : 'N/A';
      final fcfVal = i < fcf.length ? _formatValue(fcf[i]) : 'N/A';
      final ocfVal = i < ocf.length ? _formatValue(ocf[i]) : 'N/A';
      final roicVal = i < roic.length ? _formatPercent(roic[i]) : 'N/A';

      buffer.writeln(
        '| $year | $epsVal | $equityVal | $revenueVal | $fcfVal | $ocfVal | $roicVal |',
      );
    }
    return buffer.toString().trim();
  }

  /// Formats a numeric value for display.
  String _formatValue(dynamic value) {
    if (value == null) return 'N/A';
    if (value is num) {
      if (value.abs() >= 1e9) {
        return '\$${(value / 1e9).toStringAsFixed(1)}B';
      } else if (value.abs() >= 1e6) {
        return '\$${(value / 1e6).toStringAsFixed(1)}M';
      } else if (value.abs() >= 1e3) {
        return '\$${(value / 1e3).toStringAsFixed(1)}K';
      } else {
        return '\$${value.toStringAsFixed(2)}';
      }
    }
    return value.toString();
  }

  /// Formats a percentage value for display.
  String _formatPercent(dynamic value) {
    if (value == null) return 'N/A';
    if (value is num) {
      return '${(value * 100).toStringAsFixed(1)}%';
    }
    return value.toString();
  }
}
