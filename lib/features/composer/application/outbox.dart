import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/repositories/account_repository.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/providers/provider_factory.dart';

/// What a queued attempt produced.
enum OutboxResult {
  /// The server accepted the message; the stored copy is now `sent`.
  sent,

  /// Looks like the network: keep the message queued and try again later.
  waiting,

  /// The server answered and said no. Retrying the same thing cannot help, so
  /// the message becomes `failed` and the user decides what to do.
  refused,
}

/// Sends what could not be sent earlier, without the user doing anything.
///
/// Rules chosen so a normal person never thinks about this:
/// * the message already sits in its conversation as `queued`, so closing the
///   app, losing the network or killing the process loses nothing;
/// * only a transient failure stays queued. A refusal (wrong address, revoked
///   access) becomes `failed`, because retrying forever would be a lie;
/// * attempts back off (1, 2, 4, 8, then every 15 minutes) so a phone in a
///   tunnel does not hammer the network or drain the battery.
class Outbox {
  Outbox({
    required MailProviderFactory factory,
    required ThreadRepository threads,
    required AccountRepository accounts,
    DateTime Function()? clock,
  })  : _factory = factory,
        _threads = threads,
        _accounts = accounts,
        _clock = clock ?? DateTime.now;

  final MailProviderFactory _factory;
  final ThreadRepository _threads;
  final AccountRepository _accounts;
  final DateTime Function() _clock;

  /// Attempts already made per message id.
  final Map<String, int> _attempts = <String, int>{};

  /// Earliest time a message may be attempted again.
  final Map<String, DateTime> _nextAttempt = <String, DateTime>{};

  static const List<Duration> _backoff = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 4),
    Duration(minutes: 8),
    Duration(minutes: 15),
  ];

  /// Sends every queued message that is due. Returns how many were accepted.
  ///
  /// Never throws: the caller is usually a background tick.
  Future<int> flush() async {
    final List<Message> pending;
    try {
      pending = await _threads.queuedOutgoing();
    } catch (_) {
      return 0;
    }

    var sent = 0;
    for (final message in pending) {
      final due = _nextAttempt[message.id];
      if (due != null && _clock().isBefore(due)) continue;
      if (await _attempt(message) == OutboxResult.sent) {
        sent++;
        _attempts.remove(message.id);
        _nextAttempt.remove(message.id);
      }
    }
    return sent;
  }

  /// True when something is waiting for the network.
  Future<bool> hasPending() async {
    try {
      return (await _threads.queuedOutgoing()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<OutboxResult> _attempt(Message message) async {
    final account = await _accounts.getAccount(message.accountId);
    if (account == null) {
      // The account was removed while the message waited: there is nothing to
      // send it from, and keeping it queued forever would be a lie.
      await _mark(message, DeliveryStatus.failed);
      return OutboxResult.refused;
    }

    final provider = _factory.create(account);
    try {
      await provider.connect(account);
      await (message.inReplyTo != null && message.providerId != null
          ? provider.replyToMessage(
              message.providerId!,
              _outgoing(account, message),
            )
          : provider.sendMessage(_outgoing(account, message)));
      await _mark(message, DeliveryStatus.sent);
      return OutboxResult.sent;
    } on MailProviderException catch (error) {
      // 429 and 5xx are the server saying «later»; everything else with a
      // status, and every auth error, needs the user.
      if (error.isTransient || error.statusCode == null) {
        _scheduleRetry(message.id);
        return OutboxResult.waiting;
      }
      await _mark(message, DeliveryStatus.failed);
      return OutboxResult.refused;
    } on AccountAuthException {
      await _mark(message, DeliveryStatus.failed);
      return OutboxResult.refused;
    } on AppException {
      // Could not even connect: most often the network is back but the token
      // refresh failed. Not the user's problem to fix — keep it queued.
      _scheduleRetry(message.id);
      return OutboxResult.waiting;
    } finally {
      await provider.disconnect();
    }
  }

  OutgoingMessage _outgoing(Account account, Message message) {
    return OutgoingMessage(
      from: account.email,
      to: message.to.map((address) => address.address).toList(),
      cc: message.cc.map((address) => address.address).toList(),
      subject: message.subject,
      bodyText: message.bodyText,
      inReplyTo: message.inReplyTo,
      references: message.references,
    );
  }

  Future<void> _mark(Message message, DeliveryStatus status) =>
      _threads.setDeliveryStatus(message.id, status, threadId: message.threadId);

  void _scheduleRetry(String messageId) {
    final attempts = (_attempts[messageId] ?? 0) + 1;
    _attempts[messageId] = attempts;
    final index = attempts >= _backoff.length ? _backoff.length - 1 : attempts - 1;
    _nextAttempt[messageId] = _clock().add(_backoff[index]);
  }
}

final outboxProvider = Provider<Outbox>((ref) {
  return Outbox(
    factory: ref.watch(mailProviderFactoryProvider),
    threads: ref.watch(threadRepositoryProvider),
    accounts: ref.watch(accountRepositoryProvider),
  );
});
