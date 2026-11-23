import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';

/// One conversation, resolved by id.
final threadByIdProvider =
    FutureProvider.family<MessageThread?, String>((ref, id) async {
  return ref.watch(threadRepositoryProvider).getThread(id);
});

/// Messages of one conversation, oldest first, live.
final threadMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, threadId) {
  return ref.watch(threadRepositoryProvider).watchMessages(threadId);
});
