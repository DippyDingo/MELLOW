import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// One PKCE (RFC 7636) verifier/challenge pair.
class PkcePair {
  const PkcePair({required this.verifier, required this.challenge});

  /// High-entropy secret kept on the device until the code is exchanged.
  final String verifier;

  /// `BASE64URL(SHA256(verifier))`, sent in the authorisation request.
  final String challenge;

  static const String method = 'S256';
}

/// Generates PKCE pairs and OAuth state values.
///
/// Pure functions with an injectable [Random] so tests are deterministic.
abstract final class Pkce {
  static const String _allowed =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// RFC 7636 requires 43–128 characters from the unreserved set.
  static PkcePair generate({Random? random, int length = 64}) {
    assert(length >= 43 && length <= 128, 'PKCE verifier length out of range');
    final rng = random ?? Random.secure();
    final verifier = List<String>.generate(
      length,
      (_) => _allowed[rng.nextInt(_allowed.length)],
    ).join();

    return PkcePair(verifier: verifier, challenge: challengeFor(verifier));
  }

  /// Computes the `S256` challenge for an existing verifier.
  ///
  /// Needed when the verifier was persisted across a process restart.
  static String challengeFor(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Opaque `state` value used to reject CSRF-style redirects.
  static String state({Random? random}) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
