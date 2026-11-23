import 'package:flutter/material.dart';
import 'package:mellow/core/theme/mellow_theme.dart';

/// Avatar placeholder for a contact or account.
///
/// Deterministic colour per [seed] so the same person always looks the same,
/// with a calm palette derived from the accent token (never random per build).
class MellowAvatar extends StatelessWidget {
  const MellowAvatar({
    required this.label,
    super.key,
    this.seed,
    this.size = 44,
    this.image,
  });

  /// Text used to derive the initial. Usually a person's display name.
  final String label;

  /// Stable string (email or id) used to pick a hue.
  final String? seed;

  final double size;

  /// Optional local avatar image.
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final initial = _initialOf(label);
    final color = _colorFor(seed ?? label, tokens);

    return Semantics(
      label: label,
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          image: image == null
              ? null
              : DecorationImage(image: image!, fit: BoxFit.cover),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? null
            : Text(
                initial,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.isDark ? tokens.onAccent : Colors.white,
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.w600,
                    ),
              ),
      ),
    );
  }

  static String _initialOf(String label) {
    final trimmed = label.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  /// Picks one of a small set of soothing hues, stable for a given seed.
  static Color _colorFor(String seed, MellowColors tokens) {
    if (seed.isEmpty) return tokens.accent;
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7fffffff;
    }
    final hue = (hash % 12) * 30.0;
    final lightness = tokens.isDark ? 0.34 : 0.42;
    return HSLColor.fromAHSL(1, hue, 0.22, lightness).toColor();
  }
}
