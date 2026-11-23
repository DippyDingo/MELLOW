import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/date_format.dart';
import 'package:mellow/core/widgets/mellow_avatar.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/features/conversations/application/thread_list_controller.dart';
import 'package:mellow/features/contacts/application/contacts_controller.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';
import 'package:mellow/core/widgets/account_switcher_button.dart';

/// Main "Диалоги" tab: search, Focus Mode toggle and the conversation list.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(threadListProvider);
    final settings = ref.watch(appSettingsProvider);

    return MellowScaffold(
      padding: false,
      appBar: AppBar(
        title: const Text('Диалоги'),
        titleSpacing: MellowSpacing.lg,
        actions: <Widget>[
          const AccountSwitcherButton(),
          const SizedBox(width: MellowSpacing.sm),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.compose),
        tooltip: 'Новое сообщение',
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MellowSpacing.lg,
              MellowSpacing.sm,
              MellowSpacing.lg,
              MellowSpacing.sm,
            ),
            child: const _SearchField(),
          ),
          const _FocusModeBar(),
          Expanded(
            child: threads.when(
              data: (items) {
                if (items.isEmpty) {
                  return MellowEmptyState(
                    title: settings.focusModeEnabled
                        ? 'В режиме фокуса пусто'
                        : 'Пока нет диалогов',
                    message: settings.focusModeEnabled
                        ? 'Ослабьте фильтры Focus Mode или подключите аккаунт.'
                        : 'Подключите почтовый аккаунт — переписка появится здесь.',
                    icon: Icons.forum_outlined,
                    action: settings.focusModeEnabled
                        ? null
                        : FilledButton.tonal(
                            onPressed: () =>
                                context.push(AppRoutes.addAccount),
                            child: const Text('Подключить аккаунт'),
                          ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(
                    indent: 76,
                    endIndent: MellowSpacing.lg,
                  ),
                  itemBuilder: (context, index) =>
                      _ThreadTile(thread: items[index]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => MellowEmptyState(
                title: 'Не удалось загрузить диалоги',
                message: error.toString(),
                icon: Icons.error_outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(threadSearchQueryProvider),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: (value) =>
          ref.read(threadSearchQueryProvider.notifier).state = value,
      decoration: InputDecoration(
        hintText: 'Поиск по имени, теме или тексту',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Очистить',
                onPressed: () {
                  _controller.clear();
                  ref.read(threadSearchQueryProvider.notifier).state = '';
                  setState(() {});
                },
              ),
      ),
    );
  }
}

/// Compact row of Focus Mode switches (spec 2.6).
class _FocusModeBar extends ConsumerWidget {
  const _FocusModeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final tokens = MellowColors.of(context);
    final controller = ref.read(settingsControllerProvider.notifier);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MellowSpacing.lg),
        children: <Widget>[
          FilterChip(
            selected: settings.focusModeEnabled,
            avatar: Icon(
              Icons.center_focus_strong_outlined,
              size: 16,
              color: settings.focusModeEnabled ? tokens.accent : tokens.onSurfaceMuted,
            ),
            label: const Text('Focus Mode'),
            onSelected: controller.setFocusModeEnabled,
          ),
          if (settings.focusModeEnabled) ...<Widget>[
            const SizedBox(width: MellowSpacing.sm),
            FilterChip(
              selected: settings.focusFavoritesOnly,
              label: const Text('Избранные'),
              onSelected: controller.setFocusFavoritesOnly,
            ),
            const SizedBox(width: MellowSpacing.sm),
            FilterChip(
              selected: settings.focusUnreadOnly,
              label: const Text('Непрочитанные'),
              onSelected: controller.setFocusUnreadOnly,
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.thread});

  final MessageThread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    // Resolve the contact name when participants map to a known person.
    final contact = thread.contactId == null
        ? null
        : ref.watch(contactByIdProvider(thread.contactId!)).valueOrNull;

    final title = contact?.displayName ??
        (thread.participants.isEmpty
            ? 'Без имени'
            : thread.participants.first.displayName ??
                thread.participants.first.address);
    final subtitle = thread.lastMessagePreview.isEmpty
        ? thread.subject
        : thread.lastMessagePreview;

    return ListTile(
      onTap: () => context.push(AppRoutes.thread(thread.id)),
      onLongPress: () => _showThreadActions(context, ref),
      leading: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          MellowAvatar(label: title, seed: thread.primaryParticipantAddress),
          if (thread.isPinned)
            Positioned(
              right: -2,
              bottom: -2,
              child: _BadgeDot(
                icon: Icons.push_pin,
                background: tokens.surface,
                foreground: tokens.accent,
              ),
            ),
        ],
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                color: tokens.onSurface,
                fontWeight:
                    thread.hasUnread ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: MellowSpacing.sm),
          Text(
            MellowDates.relativeShort(thread.updatedAt),
            style: textTheme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                thread.subject.isEmpty ? subtitle : '${thread.subject} · $subtitle',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: thread.hasUnread ? tokens.onSurface : tokens.onSurfaceMuted,
                ),
              ),
            ),
            if (thread.isMuted)
              Padding(
                padding: const EdgeInsets.only(left: MellowSpacing.sm),
                child: Icon(
                  Icons.notifications_off_outlined,
                  size: 16,
                  color: tokens.onSurfaceMuted,
                ),
              ),
            if (thread.hasUnread)
              Container(
                margin: const EdgeInsets.only(left: MellowSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.unreadBadge,
                  borderRadius: BorderRadius.circular(MellowRadius.pill),
                ),
                child: Text(
                  '${thread.unreadCount}',
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.onUnreadBadge,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showThreadActions(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(threadRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(thread.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(thread.isPinned ? 'Открепить' : 'Закрепить'),
              onTap: () {
                repository.setThreadPinned(thread.id, pinned: !thread.isPinned);
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: Text(
                thread.unreadCount > 0 ? 'Отметить прочитанным' : 'Отметить непрочитанным',
              ),
              onTap: () async {
                final messages = await repository.getMessages(thread.id);
                for (final message in messages) {
                  await repository.setRead(
                    message.id,
                    read: thread.unreadCount > 0,
                  );
                }
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: Icon(
                thread.isMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: Text(thread.isMuted ? 'Включить уведомления' : 'Отключить уведомления'),
              onTap: () {
                repository.setThreadMuted(thread.id, muted: !thread.isMuted);
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('В архив'),
              onTap: () {
                repository.setThreadArchived(thread.id, archived: true);
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Скрыть локально'),
              subtitle: const Text('На почтовом сервере письма останутся'),
              onTap: () {
                repository.hideThread(thread.id);
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 10, color: foreground),
    );
  }
}
