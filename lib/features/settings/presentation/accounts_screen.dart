import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_avatar.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/providers/discovery/provider_discovery.dart';

/// Connected accounts: status, primary selection, re-auth and disconnect.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);

    return MellowScaffold(
      title: 'Аккаунты',
      actions: <Widget>[
        IconButton(
          tooltip: 'Добавить',
          icon: const Icon(Icons.add),
          onPressed: () => context.push(AppRoutes.addAccount),
        ),
      ],
      body: accounts.when(
        data: (items) => items.isEmpty
            ? MellowEmptyState(
                title: 'Нет подключённых аккаунтов',
                message: 'Добавьте Gmail, Яндекс Почту, Mail.ru, Outlook '
                    'или любой IMAP/SMTP ящик.',
                icon: Icons.alternate_email,
                action: FilledButton(
                  onPressed: () => context.push(AppRoutes.addAccount),
                  child: const Text('Добавить аккаунт'),
                ),
              )
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: MellowSpacing.md),
                itemBuilder: (context, index) => _AccountCard(account: items[index]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MellowEmptyState(
          title: 'Не удалось загрузить аккаунты',
          message: error.toString(),
          icon: Icons.error_outline,
        ),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final repository = ref.read(accountRepositoryProvider);

    return Container(
      padding: const EdgeInsets.all(MellowSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(MellowRadius.lg),
        border: Border.all(color: tokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              MellowAvatar(label: account.label, seed: account.email, size: 40),
              const SizedBox(width: MellowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(account.email, style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      ProviderDiscovery.providerLabel(account.provider),
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (account.isPrimary)
                Chip(
                  label: const Text('Основной'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: tokens.accentContainer,
                ),
            ],
          ),
          const SizedBox(height: MellowSpacing.md),
          Row(
            children: <Widget>[
              Icon(
                account.status.isUsable ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: account.status.isUsable ? tokens.success : tokens.danger,
              ),
              const SizedBox(width: 6),
              Text(
                _statusLabel(account.status),
                style: textTheme.labelSmall?.copyWith(
                  color: account.status.isUsable ? tokens.success : tokens.danger,
                ),
              ),
            ],
          ),
          if (account.lastError != null) ...<Widget>[
            const SizedBox(height: MellowSpacing.sm),
            Text(
              account.lastError!,
              style: textTheme.bodySmall?.copyWith(color: tokens.danger),
            ),
          ],
          const SizedBox(height: MellowSpacing.md),
          Wrap(
            spacing: MellowSpacing.sm,
            runSpacing: MellowSpacing.sm,
            children: <Widget>[
              if (!account.isPrimary)
                OutlinedButton(
                  onPressed: () => repository.setPrimary(account.id),
                  child: const Text('Сделать основным'),
                ),
              if (account.status == AccountStatus.needsReauth ||
                  account.status == AccountStatus.error)
                FilledButton.tonal(
                  onPressed: () => context.push(AppRoutes.addAccount),
                  child: const Text('Войти заново'),
                ),
              TextButton(
                onPressed: () => _confirmDisconnect(context, ref),
                child: Text(
                  'Отключить',
                  style: TextStyle(color: tokens.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(AccountStatus status) {
    switch (status) {
      case AccountStatus.connected:
        return 'Подключён';
      case AccountStatus.pending:
        return 'Ожидает авторизации';
      case AccountStatus.needsReauth:
        return 'Требуется повторный вход';
      case AccountStatus.error:
        return 'Ошибка подключения';
      case AccountStatus.disabled:
        return 'Отключён';
    }
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Отключить ${account.email}?'),
        content: const Text(
          'Локальные письма этого аккаунта будут удалены с устройства. '
          'На почтовом сервере ничего не изменится.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(accountRepositoryProvider).deleteAccount(account.id);
  }
}
