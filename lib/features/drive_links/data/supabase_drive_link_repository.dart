import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'google_drive_metadata_service.dart';
import '../domain/drive_file_link.dart';

class SupabaseDriveLinkRepository {
  SupabaseDriveLinkRepository(
    this._client, {
    GoogleDriveMetadataService? metadataService,
  }) : _metadataService = metadataService ?? GoogleDriveMetadataService();

  final SupabaseClient _client;
  final GoogleDriveMetadataService _metadataService;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in before linking Drive files.');
    }
    return id;
  }

  Stream<List<DriveFileLink>> watchTaskLinks(String taskId) {
    return _client
        .from('drive_file_links')
        .stream(primaryKey: ['id'])
        .eq('task_id', taskId)
        .order('created_at')
        .map((rows) => rows.map(_mapLink).toList());
  }

  Stream<List<DriveFileLink>> watchMessageLinks(String messageId) {
    return _client
        .from('drive_file_links')
        .stream(primaryKey: ['id'])
        .eq('message_id', messageId)
        .order('created_at')
        .map((rows) => rows.map(_mapLink).toList());
  }

  Future<void> replaceTaskLinks({
    required String boardId,
    required String taskId,
    required List<DriveFileLinkDraft> links,
  }) async {
    await _client.from('drive_file_links').delete().eq('task_id', taskId);
    if (links.isEmpty) {
      return;
    }
    final enrichedLinks = await _metadataService.enrichLinks(links);
    await _client
        .from('drive_file_links')
        .insert(
          enrichedLinks.map((link) {
            return _insertPayload(boardId: boardId, taskId: taskId, link: link);
          }).toList(),
        );
  }

  Future<void> replaceMessageLinks({
    required String boardId,
    required String messageId,
    required List<DriveFileLinkDraft> links,
  }) async {
    await _client.from('drive_file_links').delete().eq('message_id', messageId);
    if (links.isEmpty) {
      return;
    }
    final enrichedLinks = await _metadataService.enrichLinks(links);
    await _client
        .from('drive_file_links')
        .insert(
          enrichedLinks.map((link) {
            return _insertPayload(
              boardId: boardId,
              messageId: messageId,
              link: link,
            );
          }).toList(),
        );
  }

  Map<String, dynamic> _insertPayload({
    required String boardId,
    required DriveFileLinkDraft link,
    String? taskId,
    String? messageId,
  }) {
    return {
      'id': const Uuid().v4(),
      'board_id': boardId,
      'task_id': taskId,
      'message_id': messageId,
      'file_id': link.fileId,
      'file_type': link.fileType,
      'title': link.title,
      'url': link.url,
      'mime_type': link.mimeType,
      'created_by': _userId,
    };
  }

  DriveFileLink _mapLink(Map<String, dynamic> row) {
    return DriveFileLink(
      id: row['id'] as String,
      boardId: row['board_id'] as String,
      taskId: row['task_id'] as String?,
      messageId: row['message_id'] as String?,
      fileId: row['file_id'] as String,
      fileType: row['file_type'] as String? ?? 'file',
      title: row['title'] as String? ?? 'Google Drive file',
      url: row['url'] as String,
      mimeType: row['mime_type'] as String?,
      createdBy: row['created_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
