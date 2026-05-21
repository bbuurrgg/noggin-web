import 'dart:convert';

class AiCommandJsonParser {
  const AiCommandJsonParser._();

  static Map<String, Object?> decodeCommandJson(String text) {
    final cleaned = extractJsonObject(stripCodeFence(text));

    final decoded = jsonDecode(cleaned) as Map<String, Object?>;
    return normalizeCommandJson(decoded);
  }

  static String stripCodeFence(String text) {
    return text
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s*```$', multiLine: true), '')
        .trim();
  }

  static String extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start == -1) {
      return text;
    }

    var depth = 0;
    var inString = false;
    var isEscaped = false;

    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (isEscaped) {
          isEscaped = false;
        } else if (char == '\\') {
          isEscaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }

    return text.substring(start);
  }

  static Map<String, Object?> normalizeCommandJson(Map<String, Object?> json) {
    final normalized = Map<String, Object?>.from(json);

    normalized['action'] = _normalizeAction(normalized['action'] as String?);
    normalized['board_id'] ??= normalized['boardId'];
    normalized['task_id'] ??= normalized['taskId'];
    normalized['stage_name'] ??= normalized['stageName'];

    normalized['title'] ??= normalized['name'];
    normalized['titles'] ??= normalized['tasks'];
    normalized['status'] ??= normalized['stage'];
    normalized['message'] ??= 'Done.';

    final commands = normalized['commands'];
    if (commands is List<Object?>) {
      normalized['commands'] =
          commands
              .whereType<Map<String, Object?>>()
              .map(normalizeCommandJson)
              .toList();
    }

    return normalized;
  }

  static String _normalizeAction(String? action) {
    final normalized = (action ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return switch (normalized) {
      'create_board' || 'new_board' || 'add_board' => 'create_board',
      'rename_board' || 'edit_board' || 'update_board' => 'rename_board',
      'create' ||
      'add' ||
      'new_task' ||
      'create_task' ||
      'add_task' => 'create',
      'create_many' ||
      'add_many' ||
      'create_tasks' ||
      'add_tasks' => 'create_many',
      'move' ||
      'move_task' ||
      'put' ||
      'put_task' ||
      'set_status' ||
      'update_status' => 'move',
      'edit' ||
      'update' ||
      'update_task' ||
      'rename' ||
      'rename_task' => 'edit',
      'clear_description' || 'remove_description' => 'clear_description',
      'delete' || 'delete_task' || 'remove' || 'remove_task' => 'delete',
      'add_stage' || 'create_stage' || 'new_stage' => 'add_stage',
      'open' || 'open_task' || 'show_task' => 'open_task',
      'open_board' || 'show_board' || 'switch_board' => 'open_board',
      'batch' => 'batch',
      _ => normalized,
    };
  }
}
