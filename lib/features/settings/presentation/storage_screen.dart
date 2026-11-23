import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/features/settings/application/storage_controller.dart';

/// «Хранилище»: how much mail is kept on the device and how to free it.
///
/// Every action here is local. Deleting data on the phone never deletes mail
/// from the mailbox — the screen says so where the user can read it.
class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(storageControllerProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final tokens = MellowColors.of(context);
    final theme = Theme.of(context).textTheme;

    return MellowScaffold(
      title: 'Хранилище',
      actions: <Widget>[
        IconButton(
          tooltip: 'Пересчитать',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(storageControllerProvider.notifier).refresh(),
        ),
      ],
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _ErrorBody(message: '$error'),
        data: (data) => ListView(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(MellowSpacing.lg),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(MellowRadius.lg),
                border: Border.all(color: tokens.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Занято на устройстве: ${StorageSummary.formatBytes(data.fileBytes)}',
                    style: theme.titleSmall,
                  ),
                  const SizedBox(height: MellowSpacing.xs),
                  Text(
                    'База данных: ${StorageSummary.formatBytes(data.databaseBytes)}',
                    style: theme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
                  ),
                  const SizedBox(height: MellowSpacing.md),
                  _Metric(label: 'Писем', value: '${data.messages}'),
                  _Metric(label: 'Диалогов', value: '${data.threads}'),
                  _Metric(label: 'Людей', value: '${data.contacts}'),
                  _Metric(label: 'Аккаунтов', value: '${data.accounts}'),
                ],
              ),
            ),
            const SizedBox(height: MellowSpacing.lg),
            Text(
              'Письма хранятся только на этом устройстве. Удаление здесь не '
              'удаляет ничего из почтового ящика; после удаления письма можно '
              'скачать заново синхронизацией.',
              style: theme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const MellowSectionHeader('По аккаунтам'),
            if (accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MellowSpacing.md),
                child: Text(
                  'Аккаунтов нет — хранить нечего.',
                  style: theme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
                ),
              ),
            for (final account in accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mail_outline),
                title: Text(account.email),
                subtitle: Text(
                  account.lastSyncAt == null
                      ? 'Ещё не синхронизирован'
                      : 'Синхронизирован: ${_date(account.lastSyncAt!)}',
                  style: theme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
                ),
                trailing: IconButton(
                  tooltip: 'Удалить письма этого аккаунта с устройства',
                  icon: Icon(Icons.delete_outline, color: tokens.danger),
                  onPressed: () => _clearAccount(context, ref, account),
                ),
              ),
            const SizedBox(height: MellowSpacing.xl),
            OutlinedButton.icon(
              onPressed: data.isEmpty ? null : () => _clearAll(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.danger,
                side: BorderSide(color: tokens.danger.withOpacity(0.5)),
              ),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Удалить все письма с устройства'),
            ),
            const SizedBox(height: MellowSpacing.sm),
            Text(
              'Аккаунты и настройки останутся; токены в защищённом хранилище '
              'не затрагиваются.',
              style: theme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: MellowSpacing.xl),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _clearAccount(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Удалить письма аккаунта?',
      body: 'Все загруженные письма ${account.email} исчезнут с устройства. '
          'В почтовом ящике они останутся.',
      action: 'Удалить с устройства',
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(storageControllerProvider.notifier).clearAccount(account);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Письма ${account.email} удалены с устройства')),
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Удалить все письма?',
      body: 'Все загруженные письма всех аккаунтов исчезнут с устройства. '
          'В почтовых ящиках они останутся.',
      action: 'Удалить всё',
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(storageControllerProvider.notifier).clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Локальные письма удалены')),
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final tokens = MellowColors.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: tokens.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: MellowSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.onSurfaceMuted),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MellowSpacing.lg),
        child: Text(
          'Не удалось посчитать хранилище.\n$message',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: tokens.danger),
        ),
      ),
    );
  }
}
