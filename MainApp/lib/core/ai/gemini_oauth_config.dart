/// OAuth configuration for Gemini API access.
/// Uses the same OAuth flow as Gemini CLI (cloudcode-pa.googleapis.com).
/// Based on opencode-gemini-auth plugin: https://github.com/jenslys/opencode-gemini-auth
class GeminiOAuthConfig {
  GeminiOAuthConfig._();

  /// OAuth client ID (set via --dart-define GEMINI_OAUTH_CLIENT_ID).
  static const String clientId = String.fromEnvironment('GEMINI_OAUTH_CLIENT_ID');

  /// OAuth client secret (set via --dart-define GEMINI_OAUTH_CLIENT_SECRET).
  static const String clientSecret = String.fromEnvironment('GEMINI_OAUTH_CLIENT_SECRET');

  /// OAuth scopes required for Gemini API access.
  /// Must match exactly what opencode-gemini-auth uses.
  static const List<String> scopes = [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  /// Google OAuth authorization endpoint.
  static const String authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';

  /// Google OAuth token endpoint.
  static const String tokenEndpoint = 'https://oauth2.googleapis.com/token';

  /// Local redirect URI for OAuth callback.
  static const String redirectUri = 'http://localhost:8085/oauth2callback';

  /// Local server port for OAuth callback.
  static const int callbackPort = 8085;

  /// Cloud Code Assist API endpoint (works with OAuth, same as Gemini CLI).
  static const String codeAssistEndpoint =
      'https://cloudcode-pa.googleapis.com';

  /// Headers required for Cloud Code Assist API.
  /// Must match exactly what opencode-gemini-auth uses.
  static const Map<String, String> codeAssistHeaders = {
    'User-Agent': 'google-api-nodejs-client/9.15.1',
    'X-Goog-Api-Client': 'gl-node/22.17.0',
    'Client-Metadata':
        'ideType=IDE_UNSPECIFIED,platform=PLATFORM_UNSPECIFIED,pluginType=GEMINI',
  };

  /// Code Assist metadata for API requests.
  static const Map<String, String> codeAssistMetadata = {
    'ideType': 'IDE_UNSPECIFIED',
    'platform': 'PLATFORM_UNSPECIFIED',
    'pluginType': 'GEMINI',
  };

  /// Free tier ID for onboarding.
  static const String freeTierId = 'free-tier';

  /// Legacy tier ID (fallback).
  static const String legacyTierId = 'legacy-tier';

  /// Default model if none selected.
  /// Note: Model names should NOT have 'models/' prefix when sent to API.
  static const String defaultModel = 'gemini-2.5-flash';

  /// Storage keys for secure token storage.
  static const String accessTokenKey = 'gemini_access_token';
  static const String refreshTokenKey = 'gemini_refresh_token';
  static const String tokenExpiryKey = 'gemini_token_expiry';
  static const String userEmailKey = 'gemini_user_email';
  static const String selectedModelKey = 'gemini_selected_model';
  static const String managedProjectIdKey = 'gemini_managed_project_id';
  static const String availableModelsKey = 'gemini_available_models';
}
