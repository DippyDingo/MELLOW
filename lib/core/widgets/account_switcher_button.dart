import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_avatar.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/features/conversations/application/thread_list_controller.dart';

/// App bar action that switches the account filter and opens account settings.
class AccountSwitcherButton extends ConsumerWidget {
  const AccountSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final selectedId = ref.watch(selectedAccountIdProvider);
    final tokens = MellowColors.of(context);

    if (accounts.isEmpty) {
      return IconButton(
        tooltip: 'Подключить аккаунт',
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => context.push(AppRoutes.addAccount),
      );
    }

    final current = accounts.firstWhere(
      (account) => account.id == selectedId,
      orElse: () => accounts.firstWhere(
        (account) => account.isPrimary,
        orElse: () => accounts.first,
      ),
    );

    return PopupMenuButton<String>(
      tooltip: 'Аккаунты',
      offset: const Offset(0, 48),
      onSelected: (String value) {
        if (value == '__all__') {
          ref.read(selectedAccountIdProvider.notifier).state = null;
        } else if (value == '__add__') {
          context.push(AppRoutes.addAccount);
        } else if (value == '__manage__') {
          context.push(AppRoutes.accounts);
        } else {
          ref.read(selectedAccountIdProvider.notifier).state = value;
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        if (accounts.length > 1)
          PopupMenuItem<String>(
            value: '__all__',
            child: Row(
              children: <Widget>[
                Icon(Icons.all_inbox_outlined, size: 18, color: tokens.onSurfaceMuted),
                const SizedBox(width: MellowSpacing.sm),
                const Text('Все аккаунты'),
              ],
            ),
          ),
        for (final account in accounts)
          PopupMenuItem<String>(
            value: account.id,
            child: Row(
              children: <Widget>[
                MellowAvatar(label: account.label, seed: account.email, size: 24),
                const SizedBox(width: MellowSpacing.sm),
                Expanded(
                  child: Text(account.email, overflow: TextOverflow.ellipsis),
                ),
                if (account.id == current.id)
                  Icon(Icons.check, size: 18, color: tokens.accent),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__add__',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add),
            title: Text('Добавить аккаунт'),
          ),
        ),
        const PopupMenuItem<String>(
          value: '__manage__',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined),
            title: Text('Управление аккаунтами'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MellowSpacing.sm),
        child: MellowAvatar(
          label: current.label,
          seed: current.email,
          size: 32,
        ),
      ),
    );
  }
}
