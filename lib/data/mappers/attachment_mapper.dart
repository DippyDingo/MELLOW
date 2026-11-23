import 'package:drift/drift.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/domain/entities/attachment.dart';

/// Translates between the `attachments` table and [Attachment].
abstract final class AttachmentMapper {
  static Attachment toEntity(AttachmentRow row) {
    return Attachment(
      id: row.id,
      messageId: row.messageId,
      fileName: row.fileName,
      sizeBytes: row.sizeBytes,
      mimeType: row.mimeType,
      localPath: row.localPath,
      providerAttachmentId: row.providerAttachmentId,
      isDownloaded: row.isDownloaded,
    );
  }

  static AttachmentsCompanion toCompanion(Attachment attachment) {
    return AttachmentsCompanion.insert(
      id: attachment.id,
      messageId: attachment.messageId,
      fileName: attachment.fileName,
      mimeType: Value(attachment.mimeType),
      sizeBytes: Value(attachment.sizeBytes),
      localPath: Value(attachment.localPath),
      providerAttachmentId: Value(attachment.providerAttachmentId),
      isDownloaded: Value(attachment.isDownloaded),
    );
  }
}
