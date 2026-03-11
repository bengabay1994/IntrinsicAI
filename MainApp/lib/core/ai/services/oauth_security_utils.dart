import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Shared OAuth security helpers (PKCE + state).
class OAuthSecurityUtils {
  OAuthSecurityUtils._();

  static const int pkceVerifierEntropyBytes = 32;
  static const int minPkceVerifierLength = 43;
  static const int maxPkceVerifierLength = 128;
  static const int oauthStateEntropyBytes = 32;

  static final RegExp _pkceVerifierAllowedChars = RegExp(
    r'^[A-Za-z0-9\-._~]+$',
  );

  /// Generates an RFC 7636-compliant PKCE code verifier.
  static String generatePkceCodeVerifier() {
    final secureRandom = Random.secure();
    final randomBytes = List<int>.generate(
      pkceVerifierEntropyBytes,
      (_) => secureRandom.nextInt(256),
    );
    final verifier = base64UrlEncode(randomBytes).replaceAll('=', '');

    if (!isValidPkceCodeVerifier(verifier)) {
      throw StateError('Generated PKCE verifier is invalid');
    }

    return verifier;
  }

  /// Checks verifier length and allowed character set from RFC 7636.
  static bool isValidPkceCodeVerifier(String verifier) {
    return verifier.length >= minPkceVerifierLength &&
        verifier.length <= maxPkceVerifierLength &&
        _pkceVerifierAllowedChars.hasMatch(verifier);
  }

  /// Generates S256 PKCE code challenge.
  static String generatePkceCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// Generates random OAuth state for CSRF protection.
  static String generateOAuthState() {
    final secureRandom = Random.secure();
    final randomBytes = List<int>.generate(
      oauthStateEntropyBytes,
      (_) => secureRandom.nextInt(256),
    );
    return base64UrlEncode(randomBytes).replaceAll('=', '');
  }
}
