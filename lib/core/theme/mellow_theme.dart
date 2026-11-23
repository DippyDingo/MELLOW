import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand palette and semantic colour tokens for Mellow.
///
/// Rules:
/// * widgets never hardcode a `Color` — they read tokens via `Theme.of(context)`;
/// * every token has a light and a dark value with verified contrast;
/// * tokens are semantic (`surfaceMuted`, `bubbleIncoming`) not visual
///   (`lightGrey`), so the palette can be re-skinned without touching screens.
@immutable
class MellowColors extends ThemeExtension<MellowColors> {
  const MellowColors({
    required this.accent,
    required this.accentContainer,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.divider,
    required this.bubbleIncoming,
    required this.bubbleIncomingText,
    required this.bubbleOutgoing,
    required this.bubbleOutgoingText,
    required this.unreadBadge,
    required this.onUnreadBadge,
    required this.danger,
    required this.warning,
    required this.success,
    required this.isDark,
  });

  final Color accent;
  final Color accentContainer;
  final Color onAccent;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color divider;
  final Color bubbleIncoming;
  final Color bubbleIncomingText;
  final Color bubbleOutgoing;
  final Color bubbleOutgoingText;
  final Color unreadBadge;
  final Color onUnreadBadge;
  final Color danger;
  final Color warning;
  final Color success;
  final bool isDark;

  /// Soft sage accent, warm paper background — calm by default.
  static const MellowColors light = MellowColors(
    accent: Color(0xFF3F6F5A),
    accentContainer: Color(0xFFDDEBE2),
    onAccent: Color(0xFFFFFFFF),
    background: Color(0xFFF7F5F1),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFECE6),
    onSurface: Color(0xFF1C1D1A),
    onSurfaceMuted: Color(0xFF6B6E68),
    divider: Color(0xFFE2DED7),
    bubbleIncoming: Color(0xFFFFFFFF),
    bubbleIncomingText: Color(0xFF1C1D1A),
    bubbleOutgoing: Color(0xFF3F6F5A),
    bubbleOutgoingText: Color(0xFFFFFFFF),
    unreadBadge: Color(0xFF3F6F5A),
    onUnreadBadge: Color(0xFFFFFFFF),
    danger: Color(0xFFA6362B),
    warning: Color(0xFF8A6100),
    success: Color(0xFF2F6B4A),
    isDark: false,
  );

  static const MellowColors dark = MellowColors(
    accent: Color(0xFF8FC3A8),
    accentContainer: Color(0xFF23362C),
    onAccent: Color(0xFF10201A),
    background: Color(0xFF121412),
    surface: Color(0xFF1A1D1A),
    surfaceMuted: Color(0xFF242823),
    onSurface: Color(0xFFECEAE4),
    onSurfaceMuted: Color(0xFFA2A69E),
    divider: Color(0xFF2F342E),
    bubbleIncoming: Color(0xFF232722),
    bubbleIncomingText: Color(0xFFECEAE4),
    bubbleOutgoing: Color(0xFF3B6653),
    bubbleOutgoingText: Color(0xFFF2F7F3),
    unreadBadge: Color(0xFF8FC3A8),
    onUnreadBadge: Color(0xFF10201A),
    danger: Color(0xFFE8918A),
    warning: Color(0xFFE0B464),
    success: Color(0xFF8FC3A8),
    isDark: true,
  );

  /// Tokens of the nearest theme, or the light palette outside a theme.
  static MellowColors of(BuildContext context) =>
      Theme.of(context).extension<MellowColors>() ?? light;

  @override
  MellowColors copyWith({Color? accent, Color? background, Color? surface}) {
    return MellowColors(
      accent: accent ?? this.accent,
      accentContainer: accentContainer,
      onAccent: onAccent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted,
      onSurface: onSurface,
      onSurfaceMuted: onSurfaceMuted,
      divider: divider,
      bubbleIncoming: bubbleIncoming,
      bubbleIncomingText: bubbleIncomingText,
      bubbleOutgoing: bubbleOutgoing,
      bubbleOutgoingText: bubbleOutgoingText,
      unreadBadge: unreadBadge,
      onUnreadBadge: onUnreadBadge,
      danger: danger,
      warning: warning,
      success: success,
      isDark: isDark,
    );
  }

  @override
  MellowColors lerp(ThemeExtension<MellowColors>? other, double t) {
    if (other is! MellowColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return MellowColors(
      accent: mix(accent, other.accent),
      accentContainer: mix(accentContainer, other.accentContainer),
      onAccent: mix(onAccent, other.onAccent),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      onSurface: mix(onSurface, other.onSurface),
      onSurfaceMuted: mix(onSurfaceMuted, other.onSurfaceMuted),
      divider: mix(divider, other.divider),
      bubbleIncoming: mix(bubbleIncoming, other.bubbleIncoming),
      bubbleIncomingText: mix(bubbleIncomingText, other.bubbleIncomingText),
      bubbleOutgoing: mix(bubbleOutgoing, other.bubbleOutgoing),
      bubbleOutgoingText: mix(bubbleOutgoingText, other.bubbleOutgoingText),
      unreadBadge: mix(unreadBadge, other.unreadBadge),
      onUnreadBadge: mix(onUnreadBadge, other.onUnreadBadge),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      // On the exact midpoint the source palette wins, so `lerp(…, 0.5)`
      // never claims the opposite brightness of the palette it started from.
      isDark: t <= 0.5 ? isDark : other.isDark,
    );
  }
}

/// Spacing scale (4-point grid). Using a scale keeps rhythm consistent.
abstract final class MellowSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii tokens.
abstract final class MellowRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 18;
  static const double pill = 999;
}

/// Builds the two product themes from the token set.
///
/// Text sizes are intentionally expressed through `ThemeData.textTheme` with
/// `MediaQuery` text scaling honoured everywhere (see [MellowTheme.scaledText]).
abstract final class MellowTheme {
  static ThemeData light() => _build(MellowColors.light, Brightness.light);

  static ThemeData dark() => _build(MellowColors.dark, Brightness.dark);

  static ThemeData _build(MellowColors tokens, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      primaryContainer: tokens.accentContainer,
      onPrimaryContainer: tokens.onSurface,
      secondary: tokens.accent,
      onSecondary: tokens.onAccent,
      error: tokens.danger,
      onError: tokens.surface,
      surface: tokens.surface,
      onSurface: tokens.onSurface,
      surfaceContainerHighest: tokens.surfaceMuted,
      onSurfaceVariant: tokens.onSurfaceMuted,
      outline: tokens.divider,
      outlineVariant: tokens.divider,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
      labelSmall: base.textTheme.labelSmall?.copyWith(letterSpacing: 0.2),
    );

    return base.copyWith(
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      dividerTheme: DividerThemeData(color: tokens.divider, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.background,
        foregroundColor: tokens.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: tokens.onSurface),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: tokens.surface,
        selectedItemColor: tokens.accent,
        unselectedItemColor: tokens.onSurfaceMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface,
        indicatorColor: tokens.accentContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
          textTheme.labelSmall?.copyWith(color: tokens.onSurface),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.onSurfaceMuted,
        textColor: tokens.onSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MellowSpacing.lg,
          vertical: MellowSpacing.xs,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceMuted,
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.onSurfaceMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MellowSpacing.lg,
          vertical: MellowSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MellowRadius.pill),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MellowRadius.pill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MellowRadius.pill),
          borderSide: BorderSide(color: tokens.accent, width: 1.5),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MellowRadius.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.isDark ? tokens.surfaceMuted : tokens.onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.isDark ? tokens.onSurface : tokens.surface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MellowRadius.md),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.onAccent
              : tokens.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.surfaceMuted,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.surfaceMuted,
        selectedColor: tokens.accentContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MellowRadius.pill),
        ),
      ),
    );
  }
}
