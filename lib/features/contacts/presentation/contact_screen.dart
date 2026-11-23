import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/date_format.dart';
import 'package:mellow/core/widgets/mellow_avatar.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/features/contacts/application/contacts_controller.dart';

/// Person profile (spec 5.3): identity, addresses, and full conversation list.
class ContactScreen extends ConsumerWidget {
  const ContactScreen({required this.contactId, super.key});

  final String contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactByIdProvider(contactId));

    return contact.when(
      data: (value) {
        if (value == null) {
          return const MellowScaffold(
            title: 'Человек',
            body: MellowEmptyState(
              title: 'Контакт не найден',
              icon: Icons.person_off_outlined,
            ),
          );
        }
        return _ContactBody(contact: value);
      },
      loading: () => const MellowScaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => MellowScaffold(
        title: 'Человек',
        body: MellowEmptyState(
          title: 'Не удалось открыть контакт',
          message: error.toString(),
          icon: Icons.error_outline,
        ),
      ),
    );
  }
}

class _ContactBody extends ConsumerWidget {
  const _ContactBody({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final threads = ref.watch(contactThreadsProvider(contact.id));

    return MellowScaffold(
      padding: false,
      appBar: AppBar(
        actions: <Widget>[
          IconButton(
            tooltip: contact.isFavorite ? 'Убрать из избранного' : 'В избранное',
            icon: Icon(
              contact.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: contact.isFavorite ? tokens.warning : null,
            ),
            onPressed: () => ref
                .read(contactRepositoryProvider)
                .setFavorite(contact.id, isFavorite: !contact.isFavorite),
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'merge':
                  _showMergeHint(context);
                  break;
                case 'delete':
                  _confirmDelete(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'merge',
                child: Text('Объединить с другим контактом'),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('Удалить контакт'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: MellowSpacing.xxl),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MellowSpacing.lg,
              0,
              MellowSpacing.lg,
              MellowSpacing.lg,
            ),
            child: Column(
              children: <Widget>[
                MellowAvatar(
                  label: contact.displayName,
                  seed: contact.primaryAddress,
                  size: 72,
                ),
                const SizedBox(height: MellowSpacing.md),
                Text(
                  contact.displayName,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: MellowSpacing.xs),
                for (final address in contact.addresses)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      address.label == null
                          ? address.email
                          : '${address.email} · ${address.label}',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ),
                const SizedBox(height: MellowSpacing.lg),
                FilledButton.tonalIcon(
                  onPressed: () => context.push(
                    '${AppRoutes.compose}?to=${Uri.encodeQueryComponent(contact.primaryAddress)}',
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Написать'),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              MellowSpacing.lg,
              MellowSpacing.lg,
              MellowSpacing.lg,
              MellowSpacing.sm,
            ),
            child: MellowSectionHeader('Переписки'),
          ),
          threads.when(
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(MellowSpacing.lg),
                    child: Text('Переписок пока нет'),
                  )
                : Column(
                    children: <Widget>[
                      for (final thread in items) _ThreadRow(thread: thread),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(MellowSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(MellowSpacing.lg),
              child: Text('Ошибка: $error'),
            ),
          ),
        ],
      ),
    );
  }

  /// Explains the merge rule instead of guessing: two contacts are merged only
  /// by an explicit user decision (AGENTS.md §5).
  void _showMergeHint(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Объединение контактов'),
        content: const Text(
          'Адреса можно объединить только вручную: откройте второй контакт и '
          'выберите его как целевой. Автоматическое объединение по имени '
          'запрещено, потому что разные люди могут иметь одинаковые имена.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить ${contact.displayName}?'),
        content: const Text(
          'Контакт и его адреса будут удалены с устройства. Письма на почтовом '
          'сервере останутся нетронутыми.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(contactRepositoryProvider).deleteContact(contact.id);
    if (context.mounted) context.pop();
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final MessageThread thread;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return ListTile(
      onTap: () => context.push(AppRoutes.thread(thread.id)),
      leading: Icon(Icons.forum_outlined, color: tokens.onSurfaceMuted),
      title: Text(
        thread.subject.isEmpty ? 'Без темы' : thread.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        thread.lastMessagePreview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            MellowDates.relativeShort(thread.updatedAt),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: tokens.onSurfaceMuted),
          ),
          if (thread.hasUnread)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${thread.unreadCount}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
