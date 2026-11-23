import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/date_format.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/features/messages/application/thread_detail_controller.dart';

/// Message list of one thread, grouped by day (spec 5.4).
class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(threadByIdProvider(threadId));
    final messages = ref.watch(threadMessagesProvider(threadId));

    return thread.when(
      data: (value) {
        final title = value?.subject.isNotEmpty == true
            ? value!.subject
            : (value == null ? 'Переписка' : 'Без темы');
        return MellowScaffold(
          padding: false,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (value != null && value.participants.isNotEmpty)
                  Text(
                    value.participants.map((p) => p.address).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: MellowColors.of(context).onSurfaceMuted,
                        ),
                  ),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: value?.isMuted == true
                    ? 'Включить уведомления'
                    : 'Отключить уведомления',
                icon: Icon(
                  value?.isMuted == true
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                onPressed: () => ref
                    .read(threadRepositoryProvider)
                    .setThreadMuted(threadId, muted: !(value?.isMuted ?? false)),
              ),
              PopupMenuButton<String>(
                onSelected: (String action) async {
                  final repository = ref.read(threadRepositoryProvider);
                  switch (action) {
                    case 'pin':
                      await repository.setThreadPinned(
                        threadId,
                        pinned: !(value?.isPinned ?? false),
                      );
                      break;
                    case 'archive':
                      await repository.setThreadArchived(threadId, archived: true);
                      if (context.mounted) context.pop();
                      break;
                    case 'hide':
                      await repository.hideThread(threadId);
                      if (context.mounted) context.pop();
                      break;
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: Text(value?.isPinned == true ? 'Открепить' : 'Закрепить'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'archive',
                    child: Text('В архив'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'hide',
                    child: Text('Скрыть локально'),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: messages.when(
                  data: (items) => items.isEmpty
                      ? const MellowEmptyState(
                          title: 'В переписке пока нет сообщений',
                          icon: Icons.chat_bubble_outline,
                        )
                      : _MessageList(messages: items),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => MellowEmptyState(
                    title: 'Не удалось открыть переписку',
                    message: error.toString(),
                    icon: Icons.error_outline,
                  ),
                ),
              ),
              const _ReplyBar(),
            ],
          ),
        );
      },
      loading: () => const MellowScaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => MellowScaffold(
        title: 'Ошибка',
        body: MellowEmptyState(
          title: 'Не удалось открыть переписку',
          message: error.toString(),
          icon: Icons.error_outline,
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages});

  final List<Message> messages;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    DateTime? previousDay;

    // The user's own addresses are exactly the senders of outgoing messages;
    // this keeps the bubble side correct without extra queries.
    final ownAddresses = <String>{
      for (final message in messages)
        if (message.isOutgoing) message.from.address,
    };

    for (final message in messages) {
      final day = DateTime(
        message.sentAt.toLocal().year,
        message.sentAt.toLocal().month,
        message.sentAt.toLocal().day,
      );
      if (previousDay == null || day != previousDay) {
        rows.add(_DaySeparator(date: message.sentAt));
        previousDay = day;
      }
      rows.add(
        _MessageBubble(
          message: message,
          isOwn: ownAddresses.isEmpty ||
              ownAddresses.contains(message.from.address),
        ),
      );
    }

    return ListView(
      // Newest message is the important one; start the user at the bottom.
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        MellowSpacing.lg,
        MellowSpacing.sm,
        MellowSpacing.lg,
        MellowSpacing.lg,
      ),
      children: rows.reversed.toList(growable: false),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MellowSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(MellowRadius.pill),
          ),
          child: Text(
            MellowDates.daySeparator(date),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: tokens.onSurfaceMuted),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isOwn});

  final Message message;

  /// True when the message was sent by the user's own account address.
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    // Sender decides the side; `isOwn` guards against an alias of the user's
    // own address being mistaken for a reply.
    final outgoing = message.isOutgoing && isOwn;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: MellowSpacing.sm),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: outgoing ? tokens.bubbleOutgoing : tokens.bubbleIncoming,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(MellowRadius.lg),
            topRight: const Radius.circular(MellowRadius.lg),
            bottomLeft: Radius.circular(outgoing ? MellowRadius.lg : 4),
            bottomRight: Radius.circular(outgoing ? 4 : MellowRadius.lg),
          ),
          border: outgoing ? null : Border.all(color: tokens.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message.bodyText.isEmpty ? '(пустое сообщение)' : message.bodyText,
              style: textTheme.bodyMedium?.copyWith(
                color: outgoing ? tokens.bubbleOutgoingText : tokens.bubbleIncomingText,
              ),
            ),
            const SizedBox(height: MellowSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (message.hasAttachments)
                  Padding(
                    padding: const EdgeInsets.only(right: MellowSpacing.xs),
                    child: Icon(
                      Icons.attach_file,
                      size: 13,
                      color: (outgoing ? tokens.bubbleOutgoingText : tokens.bubbleIncomingText)
                          .withOpacity(0.7),
                    ),
                  ),
                Text(
                  message.isDraft
                      ? 'черновик'
                      : MellowDates.time(message.sentAt),
                  style: textTheme.labelSmall?.copyWith(
                    color: (outgoing
                            ? tokens.bubbleOutgoingText
                            : tokens.bubbleIncomingText)
                        .withOpacity(0.65),
                  ),
                ),
                if (outgoing) ...<Widget>[
                  const SizedBox(width: 4),
                  _StatusIcon(status: message.deliveryStatus),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final DeliveryStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final color = tokens.bubbleOutgoingText.withOpacity(0.65);
    switch (status) {
      case DeliveryStatus.draft:
      case DeliveryStatus.queued:
        return Icon(Icons.schedule, size: 13, color: color);
      case DeliveryStatus.sending:
        return Icon(Icons.arrow_upward, size: 13, color: color);
      case DeliveryStatus.sent:
        return Icon(Icons.check, size: 13, color: color);
      case DeliveryStatus.failed:
        return Icon(Icons.error_outline, size: 13, color: tokens.danger);
      case DeliveryStatus.received:
        return const SizedBox.shrink();
    }
  }
}

/// Bottom composer entry point. Sending itself arrives in sprint 05.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar();

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: MellowSpacing.lg,
        vertical: MellowSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              readOnly: true,
              onTap: () => context.push(AppRoutes.compose),
              decoration: const InputDecoration(hintText: 'Ответить…'),
            ),
          ),
          const SizedBox(width: MellowSpacing.sm),
          IconButton.filled(
            tooltip: 'Ответить',
            onPressed: () => context.push(AppRoutes.compose),
            icon: const Icon(Icons.send_outlined),
          ),
        ],
      ),
    );
  }
}
