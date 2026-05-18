import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/google_drive_url_parser.dart';
import '../domain/drive_file_link.dart';

class DriveLinkPreviewBlock extends StatelessWidget {
  const DriveLinkPreviewBlock({
    required this.text,
    required this.linksValue,
    this.emptyText,
    this.alignEnd = false,
    super.key,
  });

  final String? text;
  final AsyncValue<List<DriveFileLink>> linksValue;
  final String? emptyText;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final rawText = text?.trim() ?? '';
    final visibleText = GoogleDriveUrlParser.removeDriveUrls(rawText);
    final savedLinks = linksValue.valueOrNull ?? const <DriveFileLink>[];
    final links =
        savedLinks.isNotEmpty
            ? savedLinks
            : GoogleDriveUrlParser.extractLinks(rawText)
                .map(
                  (draft) => DriveFileLink(
                    id: draft.fileId,
                    boardId: '',
                    fileId: draft.fileId,
                    fileType: draft.fileType,
                    title: draft.title,
                    url: draft.url,
                    mimeType: draft.mimeType,
                    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                  ),
                )
                .toList();
    final showEmpty = visibleText.isEmpty && links.isEmpty && emptyText != null;

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (visibleText.isNotEmpty || showEmpty)
          LinkifiedText(
            text: visibleText.isEmpty ? emptyText! : visibleText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color:
                  visibleText.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
              height: 1.45,
            ),
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          ),
        if (links.isNotEmpty) ...[
          if (visibleText.isNotEmpty) const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
            children:
                links.map((link) => DriveFileLinkChip(link: link)).toList(),
          ),
        ],
        if (linksValue.isLoading && links.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: SizedBox(
              width: 96,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ),
      ],
    );
  }
}

class LinkifiedText extends StatelessWidget {
  const LinkifiedText({
    required this.text,
    required this.style,
    required this.textAlign,
    super.key,
  });

  static final _urlPattern = RegExp(r'https?:\/\/[^\s<>"\)]+');

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );

    return RichText(
      textAlign: textAlign,
      text: TextSpan(style: style, children: _spans(linkStyle)),
    );
  }

  List<InlineSpan> _spans(TextStyle? linkStyle) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _urlPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }

      final rawUrl = match.group(0) ?? '';
      final url = _trimTrailingPunctuation(rawUrl);
      final trailing = rawUrl.substring(url.length);
      spans.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer:
              TapGestureRecognizer()
                ..onTap = () async {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    await launchUrl(uri, webOnlyWindowName: '_blank');
                  }
                },
        ),
      );
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return spans;
  }

  String _trimTrailingPunctuation(String value) {
    return value.replaceFirst(RegExp(r'[.,;:]+$'), '');
  }
}

class DriveFileLinkChip extends StatelessWidget {
  const DriveFileLinkChip({required this.link, super.key});

  final DriveFileLink link;

  @override
  Widget build(BuildContext context) {
    final color = _color(context, link.fileType);
    return ActionChip(
      avatar: Icon(_icon(link.fileType), size: 18, color: color),
      label: Text(link.title, overflow: TextOverflow.ellipsis),
      tooltip: 'Open ${link.title}',
      side: BorderSide(color: color.withValues(alpha: 0.28)),
      backgroundColor: color.withValues(alpha: 0.08),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      onPressed: () => _open(link.url),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  IconData _icon(String fileType) {
    return switch (fileType) {
      'document' => Icons.description_rounded,
      'spreadsheet' => Icons.table_chart_rounded,
      'presentation' => Icons.slideshow_rounded,
      'drawing' => Icons.brush_rounded,
      'form' => Icons.assignment_rounded,
      'folder' => Icons.folder_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  Color _color(BuildContext context, String fileType) {
    return switch (fileType) {
      'document' => const Color(0xFF1A73E8),
      'spreadsheet' => const Color(0xFF188038),
      'presentation' => const Color(0xFFFBBC04),
      'drawing' => const Color(0xFFE8710A),
      'form' => const Color(0xFF673AB7),
      'folder' => const Color(0xFFF9AB00),
      _ => Theme.of(context).colorScheme.primary,
    };
  }
}
