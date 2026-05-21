import 'package:crane_task/features/ai_control/data/ai_command_json_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiCommandJsonParser', () {
    test('extracts the first complete JSON object from surrounding text', () {
      final json = AiCommandJsonParser.extractJsonObject(
        'Here is the command: {"action":"move","title":"Fix } brace"} thanks',
      );

      expect(json, '{"action":"move","title":"Fix } brace"}');
    });

    test('extracts JSON with escaped quotes inside strings', () {
      final json = AiCommandJsonParser.extractJsonObject(
        'prefix {"title":"Say \\"hello\\"","action":"create"} suffix',
      );

      expect(json, '{"title":"Say \\"hello\\"","action":"create"}');
    });

    test('normalizes common command field aliases', () {
      final normalized = AiCommandJsonParser.normalizeCommandJson({
        'action': 'move-task',
        'boardId': 'board-1',
        'taskId': 'task-1',
        'stageName': 'Done',
        'name': 'Fix upload',
        'stage': 'In Progress',
      });

      expect(normalized['action'], 'move');
      expect(normalized['board_id'], 'board-1');
      expect(normalized['task_id'], 'task-1');
      expect(normalized['stage_name'], 'Done');
      expect(normalized['title'], 'Fix upload');
      expect(normalized['status'], 'In Progress');
      expect(normalized['message'], 'Done.');
    });

    test('normalizes nested batch commands', () {
      final normalized = AiCommandJsonParser.normalizeCommandJson({
        'action': 'batch',
        'commands': [
          {'action': 'new task', 'name': 'One'},
          {'action': 'delete_task', 'taskId': 'task-2'},
          'ignored',
        ],
      });

      final commands = normalized['commands'] as List<Object?>;
      expect(commands, hasLength(2));
      expect((commands[0] as Map<String, Object?>)['action'], 'create');
      expect((commands[0] as Map<String, Object?>)['title'], 'One');
      expect((commands[1] as Map<String, Object?>)['action'], 'delete');
      expect((commands[1] as Map<String, Object?>)['task_id'], 'task-2');
    });

    test('decodes fenced JSON responses', () {
      final decoded = AiCommandJsonParser.decodeCommandJson('''
```json
{"action":"create_task","tasks":["One","Two"]}
```
''');

      expect(decoded['action'], 'create');
      expect(decoded['titles'], ['One', 'Two']);
    });
  });
}
