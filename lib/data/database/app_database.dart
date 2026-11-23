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
const int mellowSchemaVersion = 1;

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
          // Future migrations go here, e.g.:
          // if (from < 2) await m.addColumn(messages, messages.snippet);
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
