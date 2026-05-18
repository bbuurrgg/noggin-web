import '../domain/drive_file_link.dart';

class GoogleDriveUrlParser {
  const GoogleDriveUrlParser._();

  static final _urlPattern = RegExp(r'https?:\/\/[^\s<>"\)]+');

  static List<DriveFileLinkDraft> extractLinks(String text) {
    final links = <String, DriveFileLinkDraft>{};
    for (final match in _urlPattern.allMatches(text)) {
      final rawUrl = match.group(0);
      if (rawUrl == null) {
        continue;
      }
      final parsed = _parseUrl(_trimTrailingPunctuation(rawUrl));
      if (parsed != null) {
        links[parsed.fileId] = parsed;
      }
    }
    return links.values.toList();
  }

  static String removeDriveUrls(String text) {
    return text
        .replaceAllMapped(_urlPattern, (match) {
          final rawUrl = match.group(0);
          if (rawUrl == null) {
            return '';
          }
          return _parseUrl(_trimTrailingPunctuation(rawUrl)) == null
              ? rawUrl
              : '';
        })
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static DriveFileLinkDraft? _parseUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host == 'docs.google.com') {
      return _parseDocsUrl(uri, rawUrl);
    }
    if (host == 'drive.google.com') {
      return _parseDriveUrl(uri, rawUrl);
    }
    return null;
  }

  static DriveFileLinkDraft? _parseDocsUrl(Uri uri, String rawUrl) {
    final segments = uri.pathSegments;
    final documentIdIndex = segments.indexOf('d') + 1;
    if (segments.isEmpty ||
        documentIdIndex <= 0 ||
        documentIdIndex >= segments.length) {
      return null;
    }

    final fileType = switch (segments.first) {
      'document' => 'document',
      'spreadsheets' => 'spreadsheet',
      'presentation' => 'presentation',
      'drawings' => 'drawing',
      'forms' => 'form',
      _ => 'file',
    };

    return DriveFileLinkDraft(
      fileId: segments[documentIdIndex],
      fileType: fileType,
      title: _defaultTitle(fileType),
      url: rawUrl,
      mimeType: _mimeType(fileType),
    );
  }

  static DriveFileLinkDraft? _parseDriveUrl(Uri uri, String rawUrl) {
    final segments = uri.pathSegments;
    final documentIdIndex = segments.indexOf('d') + 1;
    if (segments.isNotEmpty &&
        segments.first == 'file' &&
        documentIdIndex > 0 &&
        documentIdIndex < segments.length) {
      return DriveFileLinkDraft(
        fileId: segments[documentIdIndex],
        fileType: 'file',
        title: _defaultTitle('file'),
        url: rawUrl,
      );
    }

    final folderIndex = segments.indexOf('folders');
    if (folderIndex >= 0) {
      final folderId =
          folderIndex + 1 < segments.length ? segments[folderIndex + 1] : '';
      if (folderId.isEmpty) {
        return null;
      }

      return DriveFileLinkDraft(
        fileId: folderId,
        fileType: 'folder',
        title: _defaultTitle('folder'),
        url: rawUrl,
        mimeType: 'application/vnd.google-apps.folder',
      );
    }

    final id = uri.queryParameters['id'];
    if (id == null || id.isEmpty) {
      return null;
    }

    return DriveFileLinkDraft(
      fileId: id,
      fileType: 'file',
      title: _defaultTitle('file'),
      url: rawUrl,
    );
  }

  static String _trimTrailingPunctuation(String value) {
    return value.replaceFirst(RegExp(r'[.,;:]+$'), '');
  }

  static String _defaultTitle(String fileType) {
    return switch (fileType) {
      'document' => 'Google Doc',
      'spreadsheet' => 'Google Sheet',
      'presentation' => 'Google Slides',
      'drawing' => 'Google Drawing',
      'form' => 'Google Form',
      'folder' => 'Google Drive folder',
      _ => 'Google Drive file',
    };
  }

  static String? _mimeType(String fileType) {
    return switch (fileType) {
      'document' => 'application/vnd.google-apps.document',
      'spreadsheet' => 'application/vnd.google-apps.spreadsheet',
      'presentation' => 'application/vnd.google-apps.presentation',
      'drawing' => 'application/vnd.google-apps.drawing',
      'form' => 'application/vnd.google-apps.form',
      _ => null,
    };
  }
}
