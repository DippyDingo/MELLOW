import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Version history of the local schema.
///
/// Every schema change bumps [mellowSchemaVersion] and adds a `fromNToM` step below.
/// Migrations never drop user data silently.
const int mellowSchemaVersion = 2;

@DriftDatabase(
  tables: <Type>[
    Accounts,
    ProviderSettings,
    SyncStates,
    Contacts,
    ContactEmails,
    Conversations,
    ConversationParticipants,
    Messages,
    Attachments,
    AppSettingsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor executor) : super(executor);

  /// In-memory database for unit tests.
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => mellowSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // 2: a draft is visible in the conversation list without loading
          // every message of every thread.
          if (from < 2) {
            await m.addColumn(conversations, conversations.hasDraft);
          }
        },
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndexes() async {
    // Message-ID lookups happen on every sync and every reply.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_message_id '
      'ON messages(message_id_header)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_conversation '
      'ON messages(conversation_id, sent_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_conversations_account_updated '
      'ON conversations(account_id, updated_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_contact_emails_contact '
      'ON contact_emails(contact_id)',
    );
  }

  /// Number of messages stored inside one conversation.
  ///
  /// Used by the storage screen; keeps `COUNT(*)` where it belongs — in `data/`.
  Future<int> countMessages(String threadId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM messages WHERE conversation_id = ?',
      variables: <Variable<Object>>[Variable<String>(threadId)],
      readsFrom: <ResultSetImplementation<dynamic, dynamic>>{messages},
    ).getSingle();
    return row.read<int>('c');
  }

  /// On-disk footprint of the database and of the app-support directory.
  ///
  /// Returns nulls where the platform cannot report a size (in-memory tests):
  /// the UI renders «—» instead of inventing a number.
  Future<({int? databaseBytes, int? fileBytes})> usage() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File(p.join(directory.path, 'mellow.sqlite'));
      final databaseBytes = await file.exists() ? await file.length() : null;

      var total = 0;
      var seen = false;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File) continue;
        seen = true;
        total += await entity.length();
      }
      return (databaseBytes: databaseBytes, fileBytes: seen ? total : null);
    } catch (_) {
      return (databaseBytes: null, fileBytes: null);
    }
  }

  /// Opens the on-disk database in the application support directory.
  static Future<AppDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'mellow.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  /// Opens a throwaway database on disk (used by tooling and integration tests).
  static AppDatabase openAt(String path) => AppDatabase(NativeDatabase(File(path)));
}
