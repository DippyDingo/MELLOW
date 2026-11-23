import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/theme/theme_mode_resolver.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';

void main() {
  group('MellowTheme', () {
    test('light theme exposes the light tokens', () {
      final theme = MellowTheme.light();
      final tokens = theme.extension<MellowColors>();
      expect(tokens, isNotNull);
      expect(tokens!.isDark, isFalse);
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, MellowColors.light.background);
    });

    test('dark theme exposes the dark tokens', () {
      final theme = MellowTheme.dark();
      final tokens = theme.extension<MellowColors>();
      expect(tokens!.isDark, isTrue);
      expect(theme.brightness, Brightness.dark);
    });

    test('colour scheme follows the tokens', () {
      final theme = MellowTheme.dark();
      expect(theme.colorScheme.primary, MellowColors.dark.accent);
      expect(theme.colorScheme.surface, MellowColors.dark.surface);
    });

    test('text styles stay readable against the surface', () {
      // Contrast guard: the token pairs must differ enough for body text.
      final light = MellowColors.light;
      final dark = MellowColors.dark;
      expect(_contrast(light.onSurface, light.surface), greaterThan(7));
      expect(_contrast(dark.onSurface, dark.surface), greaterThan(7));
      expect(
        _contrast(light.bubbleOutgoingText, light.bubbleOutgoing),
        greaterThan(4.5),
      );
      expect(
        _contrast(dark.bubbleOutgoingText, dark.bubbleOutgoing),
        greaterThan(4.5),
      );
    });

    test('lerp produces a blended palette', () {
      final blended = MellowColors.light.lerp(MellowColors.dark, 0.5);
      expect(blended.isDark, MellowColors.light.isDark);
      expect(blended.accent, isNot(MellowColors.light.accent));
    });
  });

  test('resolveThemeMode maps preferences to ThemeMode', () {
    expect(
      resolveThemeMode(const AppSettings()),
      ThemeMode.system,
    );
    expect(
      resolveThemeMode(
        const AppSettings(themePreference: ThemePreference.light),
      ),
      ThemeMode.light,
    );
    expect(
      resolveThemeMode(
        const AppSettings(themePreference: ThemePreference.dark),
      ),
      ThemeMode.dark,
    );
  });
}

/// WCAG relative-luminance contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
