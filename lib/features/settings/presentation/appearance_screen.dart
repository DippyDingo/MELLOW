import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';

/// Theme selector with live previews of every palette (spec 2.9).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return MellowScaffold(
      title: 'Тема',
      body: ListView(
        children: <Widget>[
          for (final preference in ThemePreference.values)
            Padding(
              padding: const EdgeInsets.only(bottom: MellowSpacing.md),
              child: _ThemeOption(
                preference: preference,
                selected: settings.themePreference == preference,
                onTap: () => controller.setThemePreference(preference),
              ),
            ),
          const SizedBox(height: MellowSpacing.lg),
          Text(
            'Размер текста берётся из системных настроек устройства.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: MellowColors.of(context).onSurfaceMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.preference,
    required this.selected,
    required this.onTap,
  });

  final ThemePreference preference;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MellowRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(MellowSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(MellowRadius.lg),
          border: Border.all(
            color: selected ? tokens.accent : tokens.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            _PalettePreview(preference: preference),
            const SizedBox(width: MellowSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _label(preference),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _description(preference),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: tokens.accent),
          ],
        ),
      ),
    );
  }

  static String _label(ThemePreference preference) {
    switch (preference) {
      case ThemePreference.system:
        return 'Как в системе';
      case ThemePreference.light:
        return 'Светлая';
      case ThemePreference.dark:
        return 'Тёмная';
    }
  }

  static String _description(ThemePreference preference) {
    switch (preference) {
      case ThemePreference.system:
        return 'Переключается вместе с устройством';
      case ThemePreference.light:
        return 'Тёплая бумага и приглушённый зелёный';
      case ThemePreference.dark:
        return 'Мягкий тёмный фон для вечера';
    }
  }
}

class _PalettePreview extends StatelessWidget {
  const _PalettePreview({required this.preference});

  final ThemePreference preference;

  @override
  Widget build(BuildContext context) {
    final isDark = preference == ThemePreference.dark ||
        (preference == ThemePreference.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final palette = isDark ? MellowColors.dark : MellowColors.light;

    return Container(
      width: 52,
      height: 40,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(MellowRadius.sm),
        border: Border.all(color: palette.divider),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 8,
            width: 24,
            decoration: BoxDecoration(
              color: palette.bubbleOutgoing,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 8,
            width: 32,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
