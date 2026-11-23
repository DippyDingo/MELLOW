import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/repositories/drift_account_repository.dart';
import 'package:mellow/data/repositories/drift_attachment_repository.dart';
import 'package:mellow/data/repositories/drift_contact_repository.dart';
import 'package:mellow/data/repositories/drift_settings_repository.dart';
import 'package:mellow/data/repositories/drift_thread_repository.dart';
import 'package:mellow/domain/repositories/account_repository.dart';
import 'package:mellow/domain/repositories/attachment_repository.dart';
import 'package:mellow/domain/repositories/contact_repository.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';

/// The one database instance of the running app.
///
/// Overridden in `bootstrap.dart` (real file) and in tests (in-memory), so no
/// feature ever constructs an [AppDatabase] itself.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden at startup');
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return DriftAccountRepository(ref.watch(appDatabaseProvider));
});

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  return DriftContactRepository(ref.watch(appDatabaseProvider));
});

final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return DriftThreadRepository(ref.watch(appDatabaseProvider));
});

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return DriftAttachmentRepository(ref.watch(appDatabaseProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return DriftSettingsRepository(ref.watch(appDatabaseProvider));
});
