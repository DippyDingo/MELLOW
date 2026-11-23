/// A file belonging to a [Message].
///
/// Only metadata is stored in the database; bytes live in the app cache and are
/// tracked by [localPath]. The cache is disposable — a missing file triggers a
/// re-download rather than data loss.
class Attachment {
  const Attachment({
    required this.id,
    required this.messageId,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
    this.localPath,
    this.providerAttachmentId,
    this.isDownloaded = false,
  });

  final String id;
  final String messageId;

  /// Original file name as sent, used for display and extension detection.
  final String fileName;

  final int sizeBytes;

  /// Declared MIME type, e.g. `application/pdf`. May be wrong or empty.
  final String mimeType;

  /// Absolute path inside the app cache once downloaded.
  final String? localPath;

  /// Provider handle used to fetch the bytes later.
  final String? providerAttachmentId;

  final bool isDownloaded;

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot <= 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  /// Human readable size: `1.4 MB`.
  String get readableSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    const units = <String>['KB', 'MB', 'GB'];
    var value = sizeBytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  Attachment copyWith({String? localPath, bool? isDownloaded}) {
    return Attachment(
      id: id,
      messageId: messageId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      localPath: localPath ?? this.localPath,
      providerAttachmentId: providerAttachmentId,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  @override
  String toString() => 'Attachment($fileName, $readableSize)';
}
