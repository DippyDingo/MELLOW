/// Parsed representation of an RFC 5322 style address: `Name <user@host>`.
class EmailAddress {
  const EmailAddress({required this.address, this.displayName});

  /// Lower-cased, trimmed address. This is the identity used everywhere.
  final String address;

  /// Optional human readable name exactly as it arrived (not normalised).
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      other is EmailAddress &&
      other.address == address &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(address, displayName);

  @override
  String toString() =>
      displayName == null ? address : '$displayName <$address>';
}

final RegExp _emailPattern = RegExp(
  r'^[a-z0-9.!#$%&*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?'
  r'(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
);

final RegExp _angleAddress = RegExp(r'<([^<>]+)>');

/// Normalises a raw address for storage and comparison.
///
/// `"  Ivan.Petrov@Example.COM "` -> `ivan.petrov@example.com`.
/// Accepts `Name <addr>` input by extracting the bracket part.
String normalizeEmail(String raw) {
  var value = raw.trim();
  final bracketed = _angleAddress.firstMatch(value);
  if (bracketed != null) {
    value = bracketed.group(1) ?? value;
  }
  value = value.trim().replaceAll(RegExp(r'^["\x27]+|["\x27]+$'), '');
  return value.toLowerCase();
}

/// Parses `Name <user@host>` or a bare address.
///
/// Returns `null` when the input cannot be a valid address.
EmailAddress? parseEmailAddress(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final bracketed = _angleAddress.firstMatch(trimmed);
  final String addressPart;
  var name = bracketed == null ? null : trimmed.substring(0, bracketed.start);
  if (bracketed != null) {
    addressPart = bracketed.group(1) ?? '';
  } else {
    addressPart = trimmed;
  }

  final normalized = normalizeEmail(addressPart);
  if (!isValidEmail(normalized)) return null;

  if (name != null) {
    name = name
        .trim()
        .replaceAll(RegExp(r'^["\x27]+|["\x27]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) name = null;
  }

  return EmailAddress(address: normalized, displayName: name);
}

/// Splits a header value such as `a@x.com, "Doe, John" <b@y.com>` into parts.
///
/// Commas inside quotes or angle brackets never split an address.
List<String> splitAddressList(String raw) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  var inAngle = false;

  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];
    final isEscaped = i > 0 && raw[i - 1] == '\\';
    if (char == '"' && !isEscaped) {
      inQuotes = !inQuotes;
    } else if (char == '<' && !inQuotes) {
      inAngle = true;
    } else if (char == '>' && !inQuotes) {
      inAngle = false;
    }

    if (char == ',' && !inQuotes && !inAngle) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }

  final tail = buffer.toString();
  if (tail.trim().isNotEmpty) parts.add(tail);

  return parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

/// Parses a full header value into distinct, valid addresses (order kept).
List<EmailAddress> parseAddressList(String raw) {
  final seen = <String>{};
  final result = <EmailAddress>[];
  for (final part in splitAddressList(raw)) {
    final parsed = parseEmailAddress(part);
    if (parsed == null) continue;
    if (seen.add(parsed.address)) result.add(parsed);
  }
  return List.unmodifiable(result);
}

/// True when [email] is a syntactically valid address.
bool isValidEmail(String email) {
  final value = email.trim().toLowerCase();
  if (value.length > 254) return false;
  final at = value.indexOf('@');
  if (at <= 0 || at != value.lastIndexOf('@')) return false;
  if (value.substring(0, at).length > 64) return false;
  return _emailPattern.hasMatch(value);
}

/// Returns the domain part of an address (`user@mail.ru` -> `mail.ru`).
String emailDomain(String email) {
  final normalized = normalizeEmail(email);
  final at = normalized.lastIndexOf('@');
  return at < 0 ? '' : normalized.substring(at + 1);
}

/// Best-effort human name from an address: `ivan.petrov@x.com` -> `Ivan Petrov`.
///
/// Used only as a *fallback* for display when no real name is known. It never
/// participates in contact matching (see CONTACT identity rule in AGENTS.md).
String nameFromAddress(String email) {
  final normalized = normalizeEmail(email);
  final local = normalized.split('@').first;
  final words = local
      .split(RegExp(r'[._+-]+'))
      .where((w) => w.isNotEmpty && !RegExp(r'^\d+$').hasMatch(w))
      .map(_capitalize)
      .toList();
  return words.isEmpty ? local : words.join(' ');
}

String _capitalize(String word) =>
    word[0].toUpperCase() + word.substring(1).toLowerCase();
