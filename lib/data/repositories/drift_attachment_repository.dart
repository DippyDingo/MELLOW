import 'package:drift/drift.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/mappers/attachment_mapper.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/repositories/attachment_repository.dart';

/// Drift-backed [AttachmentRepository]. Bytes are not stored in SQLite.
class DriftAttachmentRepository implements AttachmentRepository {
  DriftAttachmentRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Attachment>> getAttachments(String messageId) async {
    final rows = await (_db.select(_db.attachments)
          ..where((t) => t.messageId.equals(messageId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    return rows.map(AttachmentMapper.toEntity).toList(growable: false);
  }

  @override
  Stream<List<Attachment>> watchAttachments(String messageId) {
    final query = _db.select(_db.attachments)
      ..where((t) => t.messageId.equals(messageId));
    return query.watch().map(
          (rows) => rows.map(AttachmentMapper.toEntity).toList(growable: false),
        );
  }

  @override
  Future<Attachment> saveAttachment(Attachment attachment) async {
    await _db.into(_db.attachments).insertOnConflictUpdate(
          AttachmentMapper.toCompanion(attachment),
        );
    return attachment;
  }

  @override
  Future<void> markDownloaded(String id, String localPath) async {
    await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
      AttachmentsCompanion(
        localPath: Value(localPath),
        isDownloaded: const Value(true),
      ),
    );
  }

  @override
  Future<void> clearCache(String id) async {
    await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
      const AttachmentsCompanion(
        localPath: Value(null),
        isDownloaded: Value(false),
      ),
    );
  }

  @override
  Future<void> clearAllCache() async {
    await _db.update(_db.attachments).write(
          const AttachmentsCompanion(
            localPath: Value(null),
            isDownloaded: Value(false),
          ),
        );
  }
}
