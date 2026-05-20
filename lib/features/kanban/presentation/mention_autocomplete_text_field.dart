import 'package:flutter/material.dart';

import '../../../core/utils/avatar_image_cache.dart';
import '../domain/kanban_task.dart';

class MentionAutocompleteTextField extends StatefulWidget {
  const MentionAutocompleteTextField({
    super.key,
    required this.controller,
    required this.members,
    required this.decoration,
    this.focusNode,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final List<KanbanBoardMember> members;
  final InputDecoration decoration;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<MentionAutocompleteTextField> createState() =>
      _MentionAutocompleteTextFieldState();
}

class _MentionAutocompleteTextFieldState
    extends State<MentionAutocompleteTextField> {
  late final FocusNode _fallbackFocusNode;
  int? _mentionStart;
  int? _mentionEnd;
  String? _mentionSourceText;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _fallbackFocusNode;

  @override
  void initState() {
    super.initState();
    _fallbackFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<KanbanBoardMember>(
      textEditingController: widget.controller,
      focusNode: _effectiveFocusNode,
      displayStringForOption: (member) => member.handle,
      optionsBuilder: _optionsForText,
      onSelected: _insertMention,
      optionsViewBuilder: (context, onSelected, options) {
        final optionList = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360, maxHeight: 240),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionList.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final member = optionList[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundImage: AvatarImageCache.provider(
                        member.avatarUrl,
                      ),
                      child:
                          member.avatarUrl == null || member.avatarUrl!.isEmpty
                              ? Text(_initial(member.displayLabel))
                              : null,
                    ),
                    title: Text(member.displayLabel),
                    subtitle: Text(member.handle),
                    onTap: () => onSelected(member),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          textInputAction: widget.textInputAction,
          decoration: widget.decoration,
          onSubmitted: widget.onSubmitted,
        );
      },
    );
  }

  Iterable<KanbanBoardMember> _optionsForText(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _clearActiveMention();
      return const Iterable<KanbanBoardMember>.empty();
    }

    final cursor = selection.baseOffset;
    final textBeforeCursor = value.text.substring(0, cursor);
    final atIndex = textBeforeCursor.lastIndexOf('@');
    if (atIndex < 0) {
      _clearActiveMention();
      return const Iterable<KanbanBoardMember>.empty();
    }

    final prefix =
        atIndex == 0 ? '' : textBeforeCursor.substring(atIndex - 1, atIndex);
    if (prefix.isNotEmpty && !RegExp(r'\s').hasMatch(prefix)) {
      _clearActiveMention();
      return const Iterable<KanbanBoardMember>.empty();
    }

    final query = textBeforeCursor.substring(atIndex + 1);
    if (query.contains(RegExp(r'\s'))) {
      _clearActiveMention();
      return const Iterable<KanbanBoardMember>.empty();
    }

    _mentionStart = atIndex;
    _mentionEnd = cursor;
    _mentionSourceText = value.text;

    final normalizedQuery = query.toLowerCase();
    final matches =
        widget.members.where((member) {
            final username = member.username?.toLowerCase() ?? '';
            if (username.isEmpty) {
              return false;
            }
            return username.contains(normalizedQuery) ||
                member.displayLabel.toLowerCase().contains(normalizedQuery) ||
                member.email.toLowerCase().contains(normalizedQuery);
          }).toList()
          ..sort(
            (a, b) => a.displayLabel.toLowerCase().compareTo(
              b.displayLabel.toLowerCase(),
            ),
          );

    return matches.take(6);
  }

  void _insertMention(KanbanBoardMember member) {
    final start = _mentionStart;
    final end = _mentionEnd;
    final username = member.username;
    if (start == null || end == null || username == null || username.isEmpty) {
      return;
    }

    final text = _mentionSourceText ?? widget.controller.text;
    if (end > text.length) {
      return;
    }

    final nextText =
        '${text.substring(0, start)}@$username '
        '${text.substring(end)}';
    final nextOffset = start + username.length + 2;
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _clearActiveMention();
    _effectiveFocusNode.requestFocus();
  }

  void _clearActiveMention() {
    _mentionStart = null;
    _mentionEnd = null;
    _mentionSourceText = null;
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }
}
