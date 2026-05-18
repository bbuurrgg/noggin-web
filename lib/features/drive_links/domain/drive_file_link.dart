class DriveFileLink {
  const DriveFileLink({
    required this.id,
    required this.boardId,
    required this.fileId,
    required this.fileType,
    required this.title,
    required this.url,
    required this.createdAt,
    this.taskId,
    this.messageId,
    this.mimeType,
    this.createdBy,
  });

  final String id;
  final String boardId;
  final String? taskId;
  final String? messageId;
  final String fileId;
  final String fileType;
  final String title;
  final String url;
  final String? mimeType;
  final String? createdBy;
  final DateTime createdAt;
}

class DriveFileLinkDraft {
  const DriveFileLinkDraft({
    required this.fileId,
    required this.fileType,
    required this.title,
    required this.url,
    this.mimeType,
  });

  final String fileId;
  final String fileType;
  final String title;
  final String url;
  final String? mimeType;

  DriveFileLinkDraft copyWith({
    String? fileType,
    String? title,
    String? url,
    String? mimeType,
  }) {
    return DriveFileLinkDraft(
      fileId: fileId,
      fileType: fileType ?? this.fileType,
      title: title ?? this.title,
      url: url ?? this.url,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}
