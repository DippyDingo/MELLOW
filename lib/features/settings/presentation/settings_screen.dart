import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';

/// Settings hub (spec 5.5).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    return MellowScaffold(
      padding: false,
      appBar: AppBar(
        title: const Text('Настройки'),
        titleSpacing: MellowSpacing.lg,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MellowSpacing.lg,
          0,
          MellowSpacing.lg,
          MellowSpacing.xxl,
        ),
        children: <Widget>[
          const MellowSectionHeader('Аккаунты'),
          _Group(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('Почтовые аккаунты'),
                subtitle: Text(
                  accounts.isEmpty
                      ? 'Ни один аккаунт не подключён'
                      : '${accounts.length} подключено',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.accounts),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Добавить аккаунт'),
                onTap: () => context.push(AppRoutes.addAccount),
              ),
            ],
          ),
          const MellowSectionHeader('Данные'),
          _Group(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Хранилище'),
                subtitle: const Text('Что хранится на устройстве и как освободить место'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.storage),
              ),
            ],
          ),
          const MellowSectionHeader('Внешний вид'),
          _Group(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Тема'),
                subtitle: Text(_themeLabel(settings.themePreference)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.appearance),
              ),
            ],
          ),
          const MellowSectionHeader('Синхронизация'),
          _Group(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Синхронизация'),
                subtitle: Text(
                  accounts.isEmpty
                      ? 'Подключите аккаунт, чтобы получать письма'
                      : _lastSyncLabel(accounts),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.sync),
              ),
            ],
          ),
          const MellowSectionHeader('Уведомления и фокус'),
          _Group(
            children: <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Уведомления'),
                subtitle: const Text('Локальные уведомления после синхронизации'),
                value: settings.notificationsEnabled,
                onChanged: ref
                    .read(settingsControllerProvider.notifier)
                    .setNotificationsEnabled,
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                secondary: const Icon(Icons.star_outline),
                title: const Text('Только избранные контакты'),
                value: settings.notificationsFavoritesOnly,
                onChanged: settings.notificationsEnabled
                    ? ref
                        .read(settingsControllerProvider.notifier)
                        .setNotificationsFavoritesOnly
                    : null,
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                secondary: const Icon(Icons.center_focus_strong_outlined),
                title: const Text('Focus Mode'),
                subtitle: const Text('Скрывать рассылки и лишние письма'),
                value: settings.focusModeEnabled,
                onChanged: ref
                    .read(settingsControllerProvider.notifier)
                    .setFocusModeEnabled,
              ),
            ],
          ),
          const MellowSectionHeader('Конфиденциальность'),
          _Group(
            children: <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.image_not_supported_outlined),
                title: const Text('Блокировать внешние изображения'),
                subtitle: const Text('Письма не смогут сообщать о прочтении'),
                value: settings.blockExternalImages,
                onChanged: ref
                    .read(settingsControllerProvider.notifier)
                    .setBlockExternalImages,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Безопасность'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.privacy),
              ),
            ],
          ),
          const MellowSectionHeader('Обновления'),
          _Group(
            children: <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.system_update_alt),
                title: const Text('Проверять обновления'),
                subtitle: const Text(
                  'Mellow сам узнаёт о новой сборке на GitHub',
                ),
                value: settings.updateCheckEnabled,
                onChanged: ref
                    .read(settingsControllerProvider.notifier)
                    .setUpdateCheckEnabled,
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                secondary: const Icon(Icons.wifi),
                title: const Text('Скачивать по мобильной сети'),
                subtitle: const Text(
                  'Выключено — обновления качаются только через Wi-Fi',
                ),
                value: settings.updateOnMobileData,
                onChanged: settings.updateCheckEnabled
                    ? ref
                        .read(settingsControllerProvider.notifier)
                        .setUpdateOnMobileData
                    : null,
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Уведомлять о новой сборке'),
                value: settings.updateNotificationsEnabled,
                onChanged: settings.updateCheckEnabled
                    ? ref
                        .read(settingsControllerProvider.notifier)
                        .setUpdateNotificationsEnabled
                    : null,
              ),
            ],
          ),
          const MellowSectionHeader('О приложении'),
          _Group(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Mellow 0.1.0'),
                subtitle: const Text('Email, который ощущается как мессенджер'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.about),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// «Обновлено 5 минут назад» для самой свежей синхронизации.
  static String _lastSyncLabel(List<Account> accounts) {
    final stamps = accounts
        .map((account) => account.lastSyncAt)
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (stamps.isEmpty) return 'Ещё не синхронизировано';
    final last = stamps.last;
    final diff = DateTime.now().difference(last);
    if (diff.inMinutes < 1) return 'Обновлено только что';
    if (diff.inMinutes < 60) return 'Обновлено ${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return 'Обновлено ${diff.inHours} ч назад';
    return 'Обновлено ${diff.inDays} дн назад';
  }

  static String _themeLabel(ThemePreference preference) {
    switch (preference) {
      case ThemePreference.light:
        return 'Светлая';
      case ThemePreference.dark:
        return 'Тёмная';
      case ThemePreference.system:
        return 'Как в системе';
    }
  }
}

/// Token-driven card surface. Replaces `Card` so no Material default elevation
/// or tint leaks into the calm palette.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(MellowRadius.lg),
        border: Border.all(color: tokens.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
