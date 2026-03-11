import 'package:flutter_test/flutter_test.dart';
import 'package:intrinsic_ai/core/ai/services/oauth_security_utils.dart';

void main() {
  group('OAuthSecurityUtils PKCE', () {
    test('generated verifier is RFC 7636 length and charset compliant', () {
      final verifier = OAuthSecurityUtils.generatePkceCodeVerifier();

      expect(
        verifier.length,
        inInclusiveRange(
          OAuthSecurityUtils.minPkceVerifierLength,
          OAuthSecurityUtils.maxPkceVerifierLength,
        ),
      );
      expect(OAuthSecurityUtils.isValidPkceCodeVerifier(verifier), isTrue);
    });

    test('verifier validation enforces allowed characters', () {
      expect(OAuthSecurityUtils.isValidPkceCodeVerifier('a' * 42), isFalse);
      expect(OAuthSecurityUtils.isValidPkceCodeVerifier('a' * 43), isTrue);
      expect(OAuthSecurityUtils.isValidPkceCodeVerifier('a' * 128), isTrue);
      expect(OAuthSecurityUtils.isValidPkceCodeVerifier('a' * 129), isFalse);
      expect(
        OAuthSecurityUtils.isValidPkceCodeVerifier('${''.padLeft(42, 'a')}!'),
        isFalse,
      );
    });

    test('challenge generation is deterministic for known verifier', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final challenge = OAuthSecurityUtils.generatePkceCodeChallenge(verifier);

      expect(challenge, equals('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'));
    });
  });
}
