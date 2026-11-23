import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/providers/oauth/pkce.dart';

void main() {
  group('PkcePair', () {
    test('verifier stays within the RFC 7636 length limits', () {
      final pair = Pkce.generate();
      expect(pair.verifier.length, greaterThanOrEqualTo(43));
      expect(pair.verifier.length, lessThanOrEqualTo(128));
    });

    test('verifier uses only unreserved characters', () {
      final pair = Pkce.generate();
      expect(pair.verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
    });

    test('challenge is base64url without padding', () {
      final pair = Pkce.generate();
      expect(pair.challenge, isNot(contains('=')));
      expect(pair.challenge, matches(RegExp(r'^[A-Za-z0-9\-_]+$')));
    });

    test('challenge matches the known S256 vector', () {
      // RFC 7636 Appendix B test vector.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expected = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
      expect(Pkce.challengeFor(verifier), expected);
    });

    test('is deterministic for a seeded Random', () {
      final a = Pkce.generate(random: Random(42));
      final b = Pkce.generate(random: Random(42));
      expect(a.verifier, b.verifier);
      expect(a.challenge, b.challenge);
    });

    test('two real pairs never collide', () {
      expect(Pkce.generate().verifier, isNot(Pkce.generate().verifier));
    });

    test('challengeFor is the same function used by generate', () {
      final pair = Pkce.generate();
      expect(Pkce.challengeFor(pair.verifier), pair.challenge);
    });
  });

  group('state', () {
    test('is opaque and unique', () {
      final first = Pkce.state();
      final second = Pkce.state();
      expect(first, isNot(second));
      expect(first, matches(RegExp(r'^[A-Za-z0-9\-_]+$')));
    });
  });

  test('method constant is S256', () {
    expect(PkcePair.method, 'S256');
  });
}
