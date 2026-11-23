import 'package:mellow/domain/entities/attachment.dart';

/// Persistence contract for attachment metadata and cache state.
abstract interface class AttachmentRepository {
  Future<List<Attachment>> getAttachments(String messageId);

  Stream<List<Attachment>> watchAttachments(String messageId);

  Future<Attachment> saveAttachment(Attachment attachment);

  Future<void> markDownloaded(String id, String localPath);

  /// Removes cached bytes and clears `local_path`; metadata is kept.
  Future<void> clearCache(String id);

  /// Deletes every cached file reference (storage screen "free space").
  Future<void> clearAllCache();
}
