import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/features/sync/application/sync_controller.dart';

/// «Синхронизация» — manual sync, live stage text and per-account status.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncControllerProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final tokens = MellowColors.of(context);

    return MellowScaffold(
      title: 'Синхронизация',
      actions: <Widget>[
        IconButton(
          tooltip: 'Полная сверка',
          icon: const Icon(Icons.restart_alt),
          onPressed: state.isRunning
              ? null
              : () => ref
                  .read(syncControllerProvider.notifier)
                  .syncNow(fullSync: true),
        ),
      ],
      body: ListView(
        children: <Widget>[
          Text(
            'Mellow забирает письма из подключённых ящиков и раскладывает их '
            'по диалогам. Первая синхронизация может занять несколько секунд.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: MellowSpacing.lg),
          if (state.isRunning) ...<Widget>[
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: MellowSpacing.md),
                Expanded(
                  child: Text(
                    state.stage ?? 'Синхронизация…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MellowSpacing.lg),
          ],
          if (state.error != null)
            _Banner(
              icon: Icons.error_outline,
              color: tokens.danger,
              text: state.error!,
            ),
          if (state.result != null) _ResultCard(state: state),
          const SizedBox(height: MellowSpacing.lg),
          FilledButton.icon(
            onPressed: state.isRunning
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Синхронизировать сейчас'),
          ),
          const MellowSectionHeader('Аккаунты'),
          for (final account in accounts) _AccountSyncTile(account: account),
          const SizedBox(height: MellowSpacing.xl),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.addAccount),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Подключить ещё аккаунт'),
          ),
          const SizedBox(height: MellowSpacing.lg),
          Text(
            'Фоновая синхронизация управляется операционной системой: точное '
            'время следующего обновления не гарантируется.',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: tokens.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.state});

  final SyncScreenState state;

  @override
  Widget build(BuildContext context) {
    final result = state.result!;
    final tokens = MellowColors.of(context);
    final theme = Theme.of(context).textTheme;

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
              Icon(Icons.check_circle_outline, size: 18, color: tokens.success),
              const SizedBox(width: MellowSpacing.sm),
              Text(
                result.accounts == 0
                    ? 'Синхронизировать нечего'
                    : 'Синхронизировано аккаунтов: ${result.accounts}',
                style: theme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: MellowSpacing.sm),
          Text('Получено писем: ${result.fetched}', style: theme.bodySmall),
          Text('Новых: ${result.created}', style: theme.bodySmall),
          Text('Диалогов затронуто: ${result.threads}', style: theme.bodySmall),
          if (result.fullSync)
            Padding(
              padding: const EdgeInsets.only(top: MellowSpacing.xs),
              child: Text(
                'Выполнена полная сверка',
                style: theme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
              ),
            ),
          for (final skipped in result.skipped)
            Padding(
              padding: const EdgeInsets.only(top: MellowSpacing.sm),
              child: Text(
                skipped,
                style: theme.labelSmall?.copyWith(color: tokens.warning),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountSyncTile extends StatelessWidget {
  const _AccountSyncTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final theme = Theme.of(context).textTheme;
    final last = account.lastSyncAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: MellowSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(
            account.status.isUsable ? Icons.check_circle : Icons.error_outline,
            size: 16,
            color: account.status.isUsable ? tokens.success : tokens.danger,
          ),
          const SizedBox(width: MellowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(account.email, style: theme.bodyMedium),
                Text(
                  last == null
                      ? 'Ещё не синхронизирован'
                      : 'Последняя синхронизация: ${_time(last)}',
                  style: theme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
                ),
                if (account.lastError != null)
                  Text(
                    account.lastError!,
                    style: theme.labelSmall?.copyWith(color: tokens.danger),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: MellowSpacing.md),
      padding: const EdgeInsets.all(MellowSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(MellowRadius.md),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: MellowSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
