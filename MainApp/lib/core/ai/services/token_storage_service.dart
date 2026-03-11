import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../gemini_oauth_config.dart';
import 'gemini_service.dart';

/// Authentication token data.
class AuthToken {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? userEmail;

  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.userEmail,
  });

  /// Checks if the token is expired (with 1 minute buffer).
  /// Uses a shorter buffer to match opencode-gemini-auth (60s).
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(
      expiresAt!.subtract(const Duration(minutes: 1)),
    );
  }

  /// Checks if the token is valid (not expired).
  bool get isValid => !isExpired;
}

/// Service for securely storing and retrieving OAuth tokens.
class TokenStorageService {
  final FlutterSecureStorage _storage;

  TokenStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            wOptions: WindowsOptions(),
            lOptions: LinuxOptions(),
            mOptions: MacOsOptions(),
          );

  /// Saves authentication tokens securely.
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? userEmail,
  }) async {
    await _storage.write(
      key: GeminiOAuthConfig.accessTokenKey,
      value: accessToken,
    );

    if (refreshToken != null) {
      await _storage.write(
        key: GeminiOAuthConfig.refreshTokenKey,
        value: refreshToken,
      );
    }

    if (expiresAt != null) {
      await _storage.write(
        key: GeminiOAuthConfig.tokenExpiryKey,
        value: expiresAt.toIso8601String(),
      );
    }

    if (userEmail != null) {
      await _storage.write(
        key: GeminiOAuthConfig.userEmailKey,
        value: userEmail,
      );
    }
  }

  /// Retrieves stored authentication tokens.
  Future<AuthToken?> getTokens() async {
    final accessToken = await _storage.read(
      key: GeminiOAuthConfig.accessTokenKey,
    );
    if (accessToken == null) return null;

    final refreshToken = await _storage.read(
      key: GeminiOAuthConfig.refreshTokenKey,
    );
    final expiryString = await _storage.read(
      key: GeminiOAuthConfig.tokenExpiryKey,
    );
    final userEmail = await _storage.read(key: GeminiOAuthConfig.userEmailKey);

    DateTime? expiresAt;
    if (expiryString != null) {
      expiresAt = DateTime.tryParse(expiryString);
    }

    return AuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      userEmail: userEmail,
    );
  }

  /// Clears all stored tokens and related data (logout).
  Future<void> clearTokens() async {
    await _storage.delete(key: GeminiOAuthConfig.accessTokenKey);
    await _storage.delete(key: GeminiOAuthConfig.refreshTokenKey);
    await _storage.delete(key: GeminiOAuthConfig.tokenExpiryKey);
    await _storage.delete(key: GeminiOAuthConfig.userEmailKey);
    await _storage.delete(key: GeminiOAuthConfig.managedProjectIdKey);
    await _storage.delete(key: GeminiOAuthConfig.selectedModelKey);
    await _storage.delete(key: GeminiOAuthConfig.availableModelsKey);
  }

  /// Checks if tokens are stored.
  Future<bool> hasTokens() async {
    final accessToken = await _storage.read(
      key: GeminiOAuthConfig.accessTokenKey,
    );
    return accessToken != null;
  }

  /// Saves the selected Gemini model.
  Future<void> saveSelectedModel(String model) async {
    await _storage.write(key: GeminiOAuthConfig.selectedModelKey, value: model);
  }

  /// Retrieves the selected Gemini model.
  Future<String?> getSelectedModel() async {
    return await _storage.read(key: GeminiOAuthConfig.selectedModelKey);
  }

  /// Saves the managed Google Cloud project ID.
  Future<void> saveManagedProjectId(String projectId) async {
    await _storage.write(
      key: GeminiOAuthConfig.managedProjectIdKey,
      value: projectId,
    );
  }

  /// Retrieves the managed Google Cloud project ID.
  Future<String?> getManagedProjectId() async {
    return await _storage.read(key: GeminiOAuthConfig.managedProjectIdKey);
  }

  /// Saves the list of available models.
  Future<void> saveAvailableModels(List<GeminiModel> models) async {
    final jsonList = models.map((m) => m.toJson()).toList();
    await _storage.write(
      key: GeminiOAuthConfig.availableModelsKey,
      value: jsonEncode(jsonList),
    );
  }

  /// Retrieves the list of available models.
  Future<List<GeminiModel>?> getAvailableModels() async {
    final jsonString = await _storage.read(
      key: GeminiOAuthConfig.availableModelsKey,
    );
    if (jsonString == null) return null;

    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((json) => GeminiModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return null;
    }
  }

  /// Clears the cached models list.
  Future<void> clearAvailableModels() async {
    await _storage.delete(key: GeminiOAuthConfig.availableModelsKey);
  }
}
