import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/providers/provider_factory.dart';
import 'package:uuid/uuid.dart';

/// What the user filled in and is about to send.
class OutgoingDraft {
  const OutgoingDraft({
    required this.accountId,
    required this.from,
    required this.to,
    required this.subject,
    required this.bodyText,
    this.cc = const <String>[],
    this.threadId,
    this.inReplyTo,
    this.references = const <String>[],
    this.replyToProviderMessageId,
  });

  final String accountId;

  /// Address shown in the "from" row — the mailbox being sent from.
  final String from;

  final List<String> to;
  final List<String> cc;
  final String subject;
  final String bodyText;

  /// Existing conversation to file the new message into, if any.
  final String? threadId;

  /// `In-Reply-To` of the message being answered.
  final String? inReplyTo;

  /// Full `References` chain, oldest first.
  final List<String> references;

  /// Provider id of the answered message, needed by adapters that link the
  /// reply inside their own thread (Gmail `threadId`).
  final String? replyToProviderMessageId;

  bool get isReply => inReplyTo != null || threadId != null;
}

/// Where a send stands right now, rendered on the composer.
class SendState {
  const SendState({
    this.isSending = false,
    this.error,
    this.sentMessageId,
    this.failedMessageId,
  });

  final bool isSending;

  /// User-facing failure text; `null` when the last attempt succeeded or no
  /// attempt was made yet.
  final String? error;

  /// Local id of the stored copy once the server accepted the message.
  final String? sentMessageId;

  /// Local id of a copy that is stored but was refused by the server. A retry
  /// overwrites this row, so one message never becomes two.
  final String? failedMessageId;

  bool get isSent => sentMessageId != null;

  SendState copyWith({
    bool? isSending,
    String? error,
    String? sentMessageId,
    String? failedMessageId,
    bool clearError = false,
    bool clearFailed = false,
  }) {
    return SendState(
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
      sentMessageId: sentMessageId ?? this.sentMessageId,
      failedMessageId:
          clearFailed ? null : (failedMessageId ?? this.failedMessageId),
    );
  }
}

/// Sends a message through the account's adapter and stores the result.
///
/// Rules that the UI depends on:
/// * the stored copy appears in the thread *before* the network call, marked
///   `sending`, so the user sees their message and nothing is lost on failure;
/// * `sent` is written only after the server accepted it (spec §6.5);
/// * a failure keeps the message with `failed`, so the text is never lost and
///   the user can retry.
class SendController extends StateNotifier<SendState> {
  SendController(this._ref) : super(const SendState());

  final Ref _ref;
  final Uuid _uuid = const Uuid();

  /// Addresses of the account's own mailboxes, used to never send to itself.
  Future<void> send(OutgoingDraft draft) async {
    if (state.isSending) return;

    final accounts = _ref.read(accountsProvider).valueOrNull ?? const <Account>[];
    final account = accounts.where((a) => a.id == draft.accountId).firstOrNull;
    if (account == null) {
      state = const SendState(error: 'Аккаунт не найден. Подключите ящик заново.');
      return;
    }
    if (account.provider != MailProviderKind.gmail) {
      state = const SendState(
        error: 'Отправка из этого ящика появится в спринте 06. Сейчас поддержан Gmail.',
      );
      return;
    }

    // A retry reuses the id of the failed copy, so the second attempt cannot
    // leave two rows for one message.
    final retrying = state.failedMessageId;
    final localId = retrying ?? _uuid.v4();

    state = SendState(isSending: true, failedMessageId: retrying);

    final now = DateTime.now();
    final repositories = _ref.read(threadRepositoryProvider);
    final accountId = account.id;

    // A retry must overwrite the failed row in the conversation that already
    // holds it, not open a second one.
    final retryThread = retrying == null
        ? null
        : (await repositories.getMessage(retrying))?.threadId;

    // 1. Show the message immediately, as `sending`.
    final pending = Message(
      id: localId,
      threadId: draft.threadId ?? retryThread ?? _pendingThreadId(localId),
      accountId: accountId,
      from: EmailAddress(address: draft.from),
      to: draft.to.map((address) => EmailAddress(address: address)).toList(),
      cc: draft.cc.map((address) => EmailAddress(address: address)).toList(),
      subject: draft.subject,
      bodyText: draft.bodyText,
      inReplyTo: draft.inReplyTo,
      references: draft.references,
      sentAt: now,
      isRead: true,
      isOutgoing: true,
      deliveryStatus: DeliveryStatus.sending,
    );

    String threadId = pending.threadId;
    try {
      threadId = await _storePending(
        pending,
        draft,
        isRetry: retrying != null,
        existingThreadId: retryThread,
      );
    } catch (error) {
      // Storage failed, so nothing can be lost: report and stop.
      state = SendState(error: _describe(error));
      return;
    }

    // 2. Hand it to the server.
    try {
      final provider = _ref.read(mailProviderFactoryProvider).create(account);
      await provider.connect(account);

      final outgoing = OutgoingMessage(
        from: draft.from,
        to: draft.to,
        cc: draft.cc,
        subject: draft.subject,
        bodyText: draft.bodyText,
        inReplyTo: draft.inReplyTo,
        references: draft.references,
      );
      if (draft.replyToProviderMessageId != null) {
        await provider.replyToMessage(draft.replyToProviderMessageId!, outgoing);
      } else {
        await provider.sendMessage(outgoing);
      }

      // 3. Server accepted: flip to `sent` and refresh the list.
      await repositories.setDeliveryStatus(
        localId,
        DeliveryStatus.sent,
        threadId: threadId,
      );
      _ref.invalidate(accountsProvider);
      state = SendState(sentMessageId: localId);
    } catch (error) {
      await repositories.setDeliveryStatus(
        localId,
        DeliveryStatus.failed,
        threadId: threadId,
      );
      state = SendState(error: _describe(error), failedMessageId: localId);
    }
  }

  /// Stores the outgoing message, creating a conversation when it is new.
  ///
  /// Returns the conversation the message ended up in. A reply keeps the
  /// original thread so `In-Reply-To` and the UI agree with each other.
  Future<String> _storePending(
    Message pending,
    OutgoingDraft draft, {
    required bool isRetry,
    String? existingThreadId,
  }) async {
    final threads = _ref.read(threadRepositoryProvider);

    if (isRetry) {
      await threads.updateOutgoingMessage(pending);
      return existingThreadId ?? pending.threadId;
    }

    if (draft.threadId != null) {
      await threads.upsertMessage(pending);
      return draft.threadId!;
    }

    // A brand-new conversation: it has to exist before the message does.
    final created = await threads.createThreadForOutgoing(
      message: pending,
      subject: draft.subject,
    );
    await threads.upsertMessage(pending.copyWith(threadId: created.id));
    return created.id;
  }

  /// Stand-in thread id for a message whose conversation is created later.
  String _pendingThreadId(String messageId) => 'pending-$messageId';


  void reset() => state = const SendState();

  String _describe(Object error) {
    // Adapters only throw AppException subtypes, so the message is already
    // user-facing and safe to show.
    if (error is AppException) return error.message;
    return 'Не удалось отправить: $error';
  }
}

/// The adapter factory, overridable so tests never reach the network.
final mailProviderFactoryProvider = Provider<MailProviderFactory>((ref) {
  return MailProviderFactory(
    config: AppConfig.fromEnvironment,
    tokenStorage: ref.watch(secureTokenStorageProvider),
  );
});

final sendControllerProvider =
    StateNotifierProvider<SendController, SendState>(SendController.new);
