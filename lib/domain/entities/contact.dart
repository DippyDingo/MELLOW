import 'package:mellow/core/utils/email_address.dart';

/// A person Mellow talks to.
///
/// A contact deliberately holds **no** email address in its own identity:
/// addresses live in [ContactEmail], because one person can have several.
/// Merging two addresses into one contact is an explicit user decision —
/// see `docs/ARCHITECTURE.md` (contact identity rules).
class Contact {
  const Contact({
    required this.id,
    required this.displayName,
    required this.addresses,
    this.isFavorite = false,
    this.updatedAt,
  });

  final String id;

  /// Never empty: falls back to a name derived from the primary address.
  final String displayName;

  /// All addresses belonging to this person, primary first.
  final List<ContactEmail> addresses;

  final bool isFavorite;

  final DateTime? updatedAt;

  /// Address used for new messages and as the list subtitle.
  String get primaryAddress => addresses.isEmpty ? '' : addresses.first.email;

  /// First letter for the avatar placeholder.
  String get initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  Contact copyWith({
    String? displayName,
    List<ContactEmail>? addresses,
    bool? isFavorite,
    DateTime? updatedAt,
  }) {
    return Contact(
      id: id,
      displayName: displayName ?? this.displayName,
      addresses: addresses ?? this.addresses,
      isFavorite: isFavorite ?? this.isFavorite,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Contact($id, $displayName, $primaryAddress)';
}

/// One email address attached to a [Contact].
class ContactEmail {
  const ContactEmail({
    required this.email,
    this.label,
    this.displayName,
    this.isPrimary = false,
  });

  /// Normalised address.
  final String email;

  /// User label such as "work" or "personal".
  final String? label;

  /// Name as seen in headers for this address.
  final String? displayName;

  final bool isPrimary;

  ContactEmail copyWith({String? label, String? displayName, bool? isPrimary}) {
    return ContactEmail(
      email: email,
      label: label ?? this.label,
      displayName: displayName ?? this.displayName,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  @override
  String toString() => 'ContactEmail($email)';
}

/// Builds a contact display name without touching the database.
String contactNameFromAddresses(List<ContactEmail> addresses) {
  for (final address in addresses) {
    final name = address.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  if (addresses.isEmpty) return 'Unknown';
  final candidate = nameFromAddress(addresses.first.email);
  return candidate.isEmpty ? addresses.first.email : candidate;
}
