import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';

/// Security & privacy controls (spec 4.1).
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final tokens = MellowColors.of(context);

    return MellowScaffold(
      title: 'Безопасность',
      body: ListView(
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Блокировка приложения'),
            subtitle: const Text(
              'Требовать разблокировку устройства при открытии Mellow',
            ),
            value: settings.appLockEnabled,
            onChanged: controller.setAppLockEnabled,
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.image_not_supported_outlined),
            title: const Text('Блокировать внешние изображения'),
            subtitle: const Text(
              'Защищает от трекинговых пикселей в письмах',
            ),
            value: settings.blockExternalImages,
            onChanged: controller.setBlockExternalImages,
          ),
          const Divider(),
          const SizedBox(height: MellowSpacing.lg),
          Text(
            'Как Mellow обращается с данными',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: MellowSpacing.sm),
          _bullet(
            context,
            tokens,
            'Токены доступа хранятся в защищённом хранилище ОС, а не в базе.',
          ),
          _bullet(
            context,
            tokens,
            'Обычные пароли никогда не сохраняются — только пароли приложений '
            'в зашифрованном виде.',
          ),
          _bullet(
            context,
            tokens,
            'Все сетевые соединения используют TLS.',
          ),
          _bullet(
            context,
            tokens,
            'HTML-письма отображаются без активного содержимого и без '
            'автоматической загрузки изображений.',
          ),
          _bullet(
            context,
            tokens,
            'Содержимое писем не передаётся третьим сторонам.',
          ),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, MellowColors tokens, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MellowSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.onSurfaceMuted),
            ),
          ),
        ],
      ),
    );
  }
}
