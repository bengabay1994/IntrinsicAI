import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../gemini_oauth_config.dart';
import 'token_storage_service.dart';

/// Result of an OAuth operation.
class OAuthResult {
  final bool success;
  final String? error;
  final AuthToken? token;

  const OAuthResult._({required this.success, this.error, this.token});

  factory OAuthResult.success(AuthToken token) =>
      OAuthResult._(success: true, token: token);

  factory OAuthResult.failure(String error) =>
      OAuthResult._(success: false, error: error);
}

/// Service for handling OAuth authentication with Google.
class OAuthService {
  final TokenStorageService _tokenStorage;
  HttpServer? _callbackServer;
  String? _codeVerifier;

  OAuthService({TokenStorageService? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorageService();

  /// Starts the OAuth authorization flow.
  /// Opens browser for user consent and waits for callback.
  Future<OAuthResult> startAuthFlow() async {
    try {
      // Generate PKCE code verifier and challenge
      _codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(_codeVerifier!);

      // Build authorization URL
      final authUrl = _buildAuthorizationUrl(codeChallenge);

      // Start local server to receive callback
      final codeCompleter = Completer<String>();
      await _startCallbackServer(codeCompleter);

      // Open browser for authorization
      final uri = Uri.parse(authUrl);
      if (!await canLaunchUrl(uri)) {
        await _stopCallbackServer();
        return OAuthResult.failure(
          'Could not launch browser for authentication',
        );
      }

      await launchUrl(uri, mode: LaunchMode.externalApplication);

      // Wait for authorization code (with timeout)
      final code = await codeCompleter.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw TimeoutException('Authentication timed out');
        },
      );

      // Stop the callback server
      await _stopCallbackServer();

      // Exchange code for tokens
      return await _exchangeCodeForTokens(code);
    } catch (e) {
      await _stopCallbackServer();
      return OAuthResult.failure(e.toString());
    }
  }

  /// Refreshes the access token using the refresh token.
  Future<OAuthResult> refreshAccessToken() async {
    try {
      final currentToken = await _tokenStorage.getTokens();
      if (currentToken == null || currentToken.refreshToken == null) {
        return OAuthResult.failure('No refresh token available');
      }

      final response = await http.post(
        Uri.parse(GeminiOAuthConfig.tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': GeminiOAuthConfig.clientId,
          'client_secret': GeminiOAuthConfig.clientSecret,
          'refresh_token': currentToken.refreshToken!,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        return OAuthResult.failure(
          error['error_description'] ?? 'Token refresh failed',
        );
      }

      final tokenData = jsonDecode(response.body);
      final expiresIn = tokenData['expires_in'] as int? ?? 3600;
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));

      await _tokenStorage.saveTokens(
        accessToken: tokenData['access_token'],
        refreshToken: tokenData['refresh_token'] ?? currentToken.refreshToken,
        expiresAt: expiresAt,
        userEmail: currentToken.userEmail,
      );

      final newToken = await _tokenStorage.getTokens();
      return OAuthResult.success(newToken!);
    } catch (e) {
      return OAuthResult.failure(e.toString());
    }
  }

  /// Gets a valid access token, refreshing if necessary.
  Future<OAuthResult> getValidToken() async {
    final token = await _tokenStorage.getTokens();
    if (token == null) {
      return OAuthResult.failure('Not authenticated');
    }

    if (token.isExpired) {
      return await refreshAccessToken();
    }

    return OAuthResult.success(token);
  }

  /// Signs out and clears stored tokens.
  Future<void> signOut() async {
    await _tokenStorage.clearTokens();
  }

  /// Saves the selected Gemini model.
  Future<void> saveSelectedModel(String model) async {
    await _tokenStorage.saveSelectedModel(model);
  }

  /// Retrieves the selected Gemini model.
  Future<String?> getSelectedModel() async {
    return await _tokenStorage.getSelectedModel();
  }

  /// Saves the managed Google Cloud project ID.
  Future<void> saveManagedProjectId(String projectId) async {
    await _tokenStorage.saveManagedProjectId(projectId);
  }

  /// Retrieves the managed Google Cloud project ID.
  Future<String?> getManagedProjectId() async {
    return await _tokenStorage.getManagedProjectId();
  }

  // --- Helper Methods ---
  /// Checks if user is currently authenticated.
  Future<bool> isAuthenticated() async {
    return await _tokenStorage.hasTokens();
  }

  /// Gets the currently stored token (may be expired).
  Future<AuthToken?> getCurrentToken() async {
    return await _tokenStorage.getTokens();
  }

  // Private methods

  static const int _pkceVerifierEntropyBytes = 32;
  static const int _minPkceVerifierLength = 43;
  static const int _maxPkceVerifierLength = 128;
  static final RegExp _pkceVerifierAllowedChars = RegExp(
    r'^[A-Za-z0-9\-._~]+$',
  );

  String _generateCodeVerifier() {
    final secureRandom = Random.secure();
    final randomBytes = List<int>.generate(
      _pkceVerifierEntropyBytes,
      (_) => secureRandom.nextInt(256),
    );
    final verifier = base64UrlEncode(randomBytes).replaceAll('=', '');

    if (verifier.length < _minPkceVerifierLength ||
        verifier.length > _maxPkceVerifierLength) {
      throw StateError('Generated PKCE verifier has invalid length');
    }

    if (!_pkceVerifierAllowedChars.hasMatch(verifier)) {
      throw StateError('Generated PKCE verifier has invalid characters');
    }

    return verifier;
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _buildAuthorizationUrl(String codeChallenge) {
    final params = {
      'client_id': GeminiOAuthConfig.clientId,
      'redirect_uri': GeminiOAuthConfig.redirectUri,
      'response_type': 'code',
      'scope': GeminiOAuthConfig.scopes.join(' '),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
    };

    final queryString = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    return '${GeminiOAuthConfig.authorizationEndpoint}?$queryString';
  }

  Future<void> _startCallbackServer(Completer<String> codeCompleter) async {
    _callbackServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      GeminiOAuthConfig.callbackPort,
    );

    _callbackServer!.listen((request) async {
      if (request.uri.path == '/oauth2callback') {
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        if (error != null) {
          // Send error response to browser
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_buildErrorHtml(error))
            ..close();

          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(Exception('OAuth error: $error'));
          }
        } else if (code != null) {
          // Send success response to browser
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_buildSuccessHtml())
            ..close();

          if (!codeCompleter.isCompleted) {
            codeCompleter.complete(code);
          }
        } else {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('Missing authorization code')
            ..close();
        }
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
      }
    });
  }

  Future<void> _stopCallbackServer() async {
    await _callbackServer?.close(force: true);
    _callbackServer = null;
  }

  Future<OAuthResult> _exchangeCodeForTokens(String code) async {
    final response = await http.post(
      Uri.parse(GeminiOAuthConfig.tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': GeminiOAuthConfig.clientId,
        'client_secret': GeminiOAuthConfig.clientSecret,
        'code': code,
        'code_verifier': _codeVerifier!,
        'grant_type': 'authorization_code',
        'redirect_uri': GeminiOAuthConfig.redirectUri,
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      return OAuthResult.failure(
        error['error_description'] ?? 'Token exchange failed',
      );
    }

    final tokenData = jsonDecode(response.body);
    final expiresIn = tokenData['expires_in'] as int? ?? 3600;
    final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));

    // Get user email from ID token
    String? userEmail;
    final idToken = tokenData['id_token'] as String?;
    if (idToken != null) {
      userEmail = _extractEmailFromIdToken(idToken);
    }

    await _tokenStorage.saveTokens(
      accessToken: tokenData['access_token'],
      refreshToken: tokenData['refresh_token'],
      expiresAt: expiresAt,
      userEmail: userEmail,
    );

    final token = await _tokenStorage.getTokens();
    return OAuthResult.success(token!);
  }

  String? _extractEmailFromIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length != 3) return null;

      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final claims = jsonDecode(decoded) as Map<String, dynamic>;

      return claims['email'] as String?;
    } catch (e) {
      return null;
    }
  }

  String _buildSuccessHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <title>Authentication Successful</title>
  <meta charset="utf-8">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: #1a1a2e;
      color: white;
    }
    .container {
      text-align: center;
      padding: 40px;
      background: rgba(255,255,255,0.1);
      border-radius: 16px;
      backdrop-filter: blur(10px);
      box-shadow: 0 4px 30px rgba(0, 0, 0, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.1);
      max-width: 400px;
    }
    .checkmark {
      font-size: 64px;
      margin-bottom: 20px;
      color: #4CAF50;
    }
    h1 { margin: 0 0 10px 0; font-size: 24px; font-weight: 600; }
    p { margin: 0; opacity: 0.8; line-height: 1.5; }
    .close-hint {
      margin-top: 24px;
      font-size: 14px;
      opacity: 0.6;
      padding-top: 20px;
      border-top: 1px solid rgba(255,255,255,0.1);
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="checkmark">✓</div>
    <h1>Connected Successfully!</h1>
    <p>You have successfully authenticated with Gemini AI.</p>
    <p class="close-hint">This window should close automatically.<br>If not, you can close it manually and return to the app.</p>
  </div>
  <script>
    // Attempt to close the window after a short delay
    setTimeout(function() {
      try {
        window.close();
      } catch (e) {
        console.log("Could not auto-close window");
      }
    }, 1500);
  </script>
</body>
</html>
''';
  }

  String _buildErrorHtml(String error) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <title>IntrinsicAI - Authentication Failed</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: white;
    }
    .container {
      text-align: center;
      padding: 40px;
      background: rgba(255,255,255,0.1);
      border-radius: 16px;
      backdrop-filter: blur(10px);
    }
    .error-icon {
      font-size: 64px;
      margin-bottom: 20px;
    }
    h1 { margin: 0 0 10px 0; font-size: 24px; color: #ff6b6b; }
    p { margin: 0; opacity: 0.8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="error-icon">✗</div>
    <h1>Authentication Failed</h1>
    <p>Error: $error</p>
    <p style="margin-top: 20px;">Please close this window and try again.</p>
  </div>
</body>
</html>
''';
  }
}
