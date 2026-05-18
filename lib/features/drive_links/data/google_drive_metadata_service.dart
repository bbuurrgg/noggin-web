import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/google_drive_config.dart';
import '../domain/drive_file_link.dart';

class GoogleDriveMetadataService {
  GoogleDriveMetadataService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<DriveFileLinkDraft>> enrichLinks(
    List<DriveFileLinkDraft> links,
  ) async {
    if (!GoogleDriveConfig.hasApiKey || links.isEmpty) {
      return links;
    }

    final enriched = <DriveFileLinkDraft>[];
    for (final link in links) {
      enriched.add(await _enrichLink(link));
    }
    return enriched;
  }

  Future<DriveFileLinkDraft> _enrichLink(DriveFileLinkDraft link) async {
    try {
      final metadata = await _fetchMetadata(link.fileId);
      if (metadata == null) {
        return link;
      }

      final name = (metadata['name'] as String?)?.trim();
      final mimeType = (metadata['mimeType'] as String?)?.trim();
      final webViewLink = (metadata['webViewLink'] as String?)?.trim();
      return link.copyWith(
        title: name == null || name.isEmpty ? null : name,
        fileType: _fileTypeFromMimeType(mimeType) ?? link.fileType,
        mimeType: mimeType == null || mimeType.isEmpty ? null : mimeType,
        url: webViewLink == null || webViewLink.isEmpty ? null : webViewLink,
      );
    } catch (_) {
      return link;
    }
  }

  Future<Map<String, dynamic>?> _fetchMetadata(String fileId) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'fields': 'id,name,mimeType,webViewLink',
      'supportsAllDrives': 'true',
      'key': GoogleDriveConfig.apiKey,
    });

    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return decoded;
  }

  String? _fileTypeFromMimeType(String? mimeType) {
    return switch (mimeType) {
      'application/vnd.google-apps.document' => 'document',
      'application/vnd.google-apps.spreadsheet' => 'spreadsheet',
      'application/vnd.google-apps.presentation' => 'presentation',
      'application/vnd.google-apps.drawing' => 'drawing',
      'application/vnd.google-apps.form' => 'form',
      'application/vnd.google-apps.folder' => 'folder',
      null || '' => null,
      _ => 'file',
    };
  }
}
