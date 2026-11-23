import 'package:drift/drift.dart';

/// `accounts` — connected mailboxes.
///
/// `id` is a Mellow UUID. `provider_account_id` is the provider-side identifier
/// and is never used as a primary key (spec 3.4).
@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();

  /// Normalised address, unique per user.
  TextColumn get email => text()();

  /// `MailProviderKind.name`.
  TextColumn get provider => text()();

  /// `AccountStatus.name`.
  TextColumn get status => text()();

  TextColumn get displayName => text().nullable()();
  TextColumn get providerAccountId => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  /// Safe, user-facing error text. Never contains credentials.
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  /// One address can only be connected once. `(provider, provider_account_id)`
  /// is deliberately not unique: SQLite treats NULLs as distinct, and the email
  /// address is the real identity of a mailbox.
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {email},
      ];
}

/// `provider_settings` — non-secret connection parameters (hosts, ports, flags).
///
/// Credentials deliberately do **not** live here; they belong in the secure
/// storage adapter (spec 4.1) keyed by `account_id`.
@DataClassName('ProviderSettingsRow')
class ProviderSettings extends Table {
  TextColumn get accountId => text()();

  TextColumn get imapHost => text().nullable()();
  IntColumn get imapPort => integer().nullable()();
  TextColumn get smtpHost => text().nullable()();
  IntColumn get smtpPort => integer().nullable()();

  /// JSON map for provider-specific, non-secret switches.
  TextColumn get optionsJson => text().withDefault(const Constant('{}'))();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {accountId};
}

/// `sync_state` — per-account synchronisation cursor and health.
@DataClassName('SyncStateRow')
class SyncStates extends Table {
  TextColumn get accountId => text()();

  /// Opaque provider cursor (Gmail historyId, IMAP UIDVALIDITY:UID).
  TextColumn get cursor => text().nullable()();

  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get lastFullSyncAt => dateTime().nullable()();
  IntColumn get consecutiveFailures =>
      integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {accountId};
}

/// `contacts` — a person, independent of any single address.
@DataClassName('ContactRow')
class Contacts extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();

  /// Local avatar path once the user picks one.
  TextColumn get avatarPath => text().nullable()();

  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `contact_emails` — addresses of a contact. An address belongs to at most one
/// contact, which is enforced by the unique index on `email`.
@DataClassName('ContactEmailRow')
class ContactEmails extends Table {
  TextColumn get id => text()();
  TextColumn get contactId => text().references(Contacts, #id)();

  /// Normalised (lower-case) address.
  TextColumn get email => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get label => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {email},
      ];
}

/// `conversations` — thematic threads, always scoped to one account.
@DataClassName('ConversationRow')
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(Accounts, #id)();

  /// Set only when every participant resolves to one contact.
  TextColumn get contactId => text().nullable().references(Contacts, #id)();

  TextColumn get subject => text().withDefault(const Constant(''))();

  /// Provider thread id when the service exposes one.
  TextColumn get providerThreadId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get lastMessagePreview => text().withDefault(const Constant(''))();

  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isMuted => boolean().withDefault(const Constant(false))();

  /// Soft delete: hidden from the local view, never deleted on the server.
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {accountId, providerThreadId},
      ];
}

/// `conversation_participants` — addresses taking part in a thread.
@DataClassName('ParticipantRow')
class ConversationParticipants extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().references(Conversations, #id)();

  /// Normalised address.
  TextColumn get email => text()();
  TextColumn get contactId => text().nullable().references(Contacts, #id)();

  /// True for the user's own account address(es) in this thread.
  BoolColumn get isOwnAddress => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {conversationId, email},
      ];
}

/// `messages` — a single email.
///
/// Deduplication: `provider_message_id` is unique per account, and the RFC
/// `Message-ID` header is unique globally when present (it is indexed, and a
/// partial uniqueness check is enforced in the repository layer).
@DataClassName('MessageRow')
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().references(Conversations, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();

  /// Provider-side id (Gmail id, IMAP UID, Graph id).
  TextColumn get providerMessageId => text().nullable()();

  /// RFC 5322 `Message-ID`. Indexed (see table index below).
  TextColumn get messageIdHeader => text().nullable()();

  TextColumn get subject => text().withDefault(const Constant(''))();
  TextColumn get fromAddress => text()();
  TextColumn get fromName => text().nullable()();

  /// Comma separated, normalised recipient lists.
  TextColumn get toAddresses => text().withDefault(const Constant(''))();
  TextColumn get ccAddresses => text().withDefault(const Constant(''))();
  TextColumn get bccAddresses => text().withDefault(const Constant(''))();

  TextColumn get bodyText => text().withDefault(const Constant(''))();
  TextColumn get bodyHtml => text().nullable()();

  TextColumn get inReplyTo => text().nullable()();
  TextColumn get references => text().withDefault(const Constant(''))();

  DateTimeColumn get sentAt => dateTime()();
  DateTimeColumn get receivedAt => dateTime().withDefault(currentDateAndTime)();

  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isOutgoing => boolean().withDefault(const Constant(false))();
  BoolColumn get isDraft => boolean().withDefault(const Constant(false))();
  BoolColumn get hasAttachments => boolean().withDefault(const Constant(false))();

  /// `DeliveryStatus.name`.
  TextColumn get deliveryStatus => text().withDefault(const Constant('received'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {accountId, providerMessageId},
      ];
}

/// `attachments` — attachment metadata plus disposable cache location.
@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text().references(Messages, #id)();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get localPath => text().nullable()();
  TextColumn get providerAttachmentId => text().nullable()();
  BoolColumn get isDownloaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `app_settings` — key/value preferences.
@DataClassName('AppSettingRow')
class AppSettingsTable extends Table {
  @override
  String get tableName => 'app_settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
