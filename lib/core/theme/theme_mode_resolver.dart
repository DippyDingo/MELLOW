import 'package:flutter/material.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';

/// Translates stored preferences into the value `MaterialApp.router` needs.
///
/// The mapping lives here, not in the domain enum, so `domain/` stays free of
/// Flutter UI types.
ThemeMode resolveThemeMode(AppSettings settings) {
  switch (settings.themePreference) {
    case ThemePreference.system:
      return ThemeMode.system;
    case ThemePreference.light:
      return ThemeMode.light;
    case ThemePreference.dark:
      return ThemeMode.dark;
  }
}
