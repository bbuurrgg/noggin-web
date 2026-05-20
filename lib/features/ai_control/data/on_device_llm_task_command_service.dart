import 'dart:convert';

import '../../../core/config/feature_flags.dart';
import '../../kanban/domain/kanban_task.dart';
import '../domain/ai_task_command.dart';
import '../domain/offline_model_type.dart';
import 'gemma_runtime.dart';

class OnDeviceLlmTaskCommandService {
  const OnDeviceLlmTaskCommandService({
    this.sentenceCaseFormattingEnabled = true,
  });

  final bool sentenceCaseFormattingEnabled;

  bool get hasActiveModel =>
      FeatureFlags.offlineAiEnabled && GemmaRuntime.hasActiveModel();

  Future<List<String>> listInstalledModels() {
    return GemmaRuntime.listInstalledModels();
  }

  Future<void> installModelFromFile({
    required String path,
    required OfflineModelType modelType,
  }) async {
    if (!FeatureFlags.offlineAiEnabled) {
      throw const AiNotConfiguredException();
    }
    await GemmaRuntime.installModelFromFile(path: path, modelType: modelType);
  }

  Future<String> analyzeBoard({
    required String instruction,
    required List<KanbanTask> tasks,
    required List<String> stages,
  }) async {
    final text = await _generateText(
      prompt: _buildAnalysisPrompt(instruction, tasks, stages),
      maxTokens: 1024,
    );
    final cleaned = _cleanConversationalResponse(text);

    if (cleaned.isEmpty) {
      throw const AiCommandException('On-device AI returned no analysis.');
    }

    if (_looksLikeFunctionCall(cleaned)) {
      return _buildLocalAnalysis(tasks: tasks, stages: stages);
    }

    return cleaned;
  }

  Future<String> chatWithBoard({
    required String message,
    required List<KanbanTask> tasks,
    required List<String> stages,
  }) async {
    final text = await _generateText(
      prompt: _buildChatPrompt(message, tasks, stages),
      maxTokens: 1024,
    );
    final cleaned = _cleanConversationalResponse(text);

    if (cleaned.isEmpty) {
      throw const AiCommandException('On-device AI returned no chat response.');
    }

    if (_looksLikeFunctionCall(cleaned)) {
      return _buildLocalChatAnswer(
        message: message,
        tasks: tasks,
        stages: stages,
      );
    }

    return cleaned;
  }

  Future<AiTaskCommand> planCommand({
    required String boardId,
    required String instruction,
    required List<KanbanTask> tasks,
    required List<String> stages,
  }) async {
    final normalizedInstruction = _normalizeSlashCommandInstruction(
      instruction,
    );
    final fallback = _planCommandLocally(
      boardId: boardId,
      instruction: normalizedInstruction,
      tasks: tasks,
      stages: stages,
    );
    if (fallback != null) {
      return normalizeCommandStages(fallback, stages);
    }
    if (_isSlashCommand(instruction)) {
      throw const AiCommandException(
        'I could not understand that slash command. Try /create Task name or /move Task name to Done.',
      );
    }

    final text = await _generateText(
      prompt: _buildPrompt(boardId, normalizedInstruction, tasks, stages),
      maxTokens: 768,
    );

    final json = _decodeCommandJson(text);
    return normalizeCommandStages(AiTaskCommand.fromJson(json), stages);
  }

  Future<AiTaskCommand> planSingleTaskCommand({
    required String instruction,
    required KanbanTask task,
    required List<String> stages,
  }) async {
    final normalizedInstruction = _normalizeSlashCommandInstruction(
      instruction,
      singleTask: true,
    );
    final fallback = _planSingleTaskCommandLocally(
      instruction: normalizedInstruction,
      task: task,
      stages: stages,
    );
    if (fallback != null) {
      return normalizeCommandStages(fallback, stages);
    }
    if (_isSlashCommand(instruction)) {
      throw const AiCommandException(
        'I could not understand that slash command. Try /addDescription Details, /move Done, or /delete.',
      );
    }

    final text = await _generateText(
      prompt: _buildSingleTaskPrompt(
        instruction: normalizedInstruction,
        task: task,
        stages: stages,
      ),
      maxTokens: 512,
    );

    final json = _decodeCommandJson(text);
    return normalizeCommandStages(AiTaskCommand.fromJson(json), stages);
  }

  Future<String> _generateText({
    required String prompt,
    required int maxTokens,
  }) async {
    if (!FeatureFlags.offlineAiEnabled || !GemmaRuntime.hasActiveModel()) {
      throw const AiNotConfiguredException();
    }

    return GemmaRuntime.generateText(prompt: prompt, maxTokens: maxTokens);
  }

  String _cleanConversationalResponse(String text) {
    return text
        .replaceAll(RegExp(r'^```[a-zA-Z]*\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s*```$', multiLine: true), '')
        .replaceAll(RegExp(r'<\/?start_of_turn>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<\/?end_of_turn>', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'^(model|assistant)\s*:\s*', caseSensitive: false),
          '',
        )
        .trim();
  }

  bool _looksLikeFunctionCall(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('<start_function_call>') ||
        normalized.contains('<start_funciton_call>') ||
        normalized.contains('<end_function_call>') ||
        normalized.contains('<end_funciton_call>') ||
        normalized.startsWith('{') ||
        normalized.startsWith('[');
  }

  String _buildLocalAnalysis({
    required List<KanbanTask> tasks,
    required List<String> stages,
  }) {
    if (tasks.isEmpty) {
      return 'Summary\nThis board has no tasks yet.\n\nSuggested next step\nCreate the first task in ${stages.isEmpty ? 'your first stage' : stages.first}.';
    }

    final counts = {
      for (final stage in stages)
        stage: tasks.where((task) => task.status == stage).length,
    };
    final inProgressTasks =
        tasks
            .where((task) => _normalize(task.status).contains('progress'))
            .map((task) => task.title)
            .toList();
    final todoTasks =
        tasks
            .where((task) => _normalize(task.status) == 'to do')
            .map((task) => task.title)
            .toList();
    final staleDescriptionCount =
        tasks
            .where(
              (task) =>
                  task.description == null || task.description!.trim().isEmpty,
            )
            .length;

    final buffer =
        StringBuffer()
          ..writeln('Summary')
          ..writeln(
            'This board has ${tasks.length} task${tasks.length == 1 ? '' : 's'}.',
          );

    if (counts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Stage counts');
      for (final entry in counts.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
    }

    buffer
      ..writeln()
      ..writeln('Risks');
    if (inProgressTasks.length > 2) {
      buffer.writeln('- There may be too much work in progress.');
    }
    if (staleDescriptionCount > 0) {
      buffer.writeln(
        '- $staleDescriptionCount task${staleDescriptionCount == 1 ? '' : 's'} need clearer descriptions.',
      );
    }
    if (inProgressTasks.length <= 2 && staleDescriptionCount == 0) {
      buffer.writeln(
        '- No obvious board hygiene risks from the current task data.',
      );
    }

    buffer
      ..writeln()
      ..writeln('Suggested next step');
    if (inProgressTasks.isNotEmpty) {
      buffer.writeln(
        'Finish or unblock "${inProgressTasks.first}" before pulling in more work.',
      );
    } else if (todoTasks.isNotEmpty) {
      buffer.writeln('Start with "${todoTasks.first}".');
    } else {
      buffer.writeln('Review completed work and add the next actionable task.');
    }

    return buffer.toString().trim();
  }

  String _buildLocalChatAnswer({
    required String message,
    required List<KanbanTask> tasks,
    required List<String> stages,
  }) {
    final normalizedMessage = _normalize(message);
    if (normalizedMessage.contains('next') ||
        normalizedMessage.contains('work')) {
      final inProgressTasks =
          tasks
              .where((task) => _normalize(task.status).contains('progress'))
              .toList();
      final todoTasks =
          tasks.where((task) => _normalize(task.status) == 'to do').toList();
      final inProgressTask =
          inProgressTasks.isEmpty ? null : inProgressTasks.first;
      final todoTask = todoTasks.isEmpty ? null : todoTasks.first;
      final task = inProgressTask ?? todoTask;
      if (task != null) {
        return 'I would focus on "${task.title}" next.';
      }
    }

    return 'I can see ${tasks.length} task${tasks.length == 1 ? '' : 's'} across ${stages.length} stage${stages.length == 1 ? '' : 's'}. Try asking what to work on next, or switch to Command mode for task changes.';
  }

  Map<String, Object?> _decodeCommandJson(String text) {
    final cleaned = _extractJsonObject(
      text
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
          .replaceAll(RegExp(r'\s*```$', multiLine: true), '')
          .trim(),
    );

    try {
      final decoded = jsonDecode(cleaned) as Map<String, Object?>;
      return _normalizeCommandJson(decoded);
    } on FormatException {
      throw AiCommandException(
        'On-device AI returned invalid JSON. Try a simpler command like: move "Task name" to Done. Raw response: $text',
      );
    }
  }

  String _extractJsonObject(String text) {
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

  Map<String, Object?> _normalizeCommandJson(Map<String, Object?> json) {
    final normalized = Map<String, Object?>.from(json);

    normalized['action'] = _normalizeAction(normalized['action'] as String?);
    normalized['board_id'] ??= normalized['boardId'];
    normalized['task_id'] ??= normalized['taskId'];
    normalized['stage_name'] ??= normalized['stageName'];

    if (normalized['title'] == null) {
      normalized['title'] = normalized['name'];
    }
    if (normalized['titles'] == null) {
      normalized['titles'] = normalized['tasks'];
    }
    if (normalized['status'] == null) {
      normalized['status'] = normalized['stage'];
    }
    if (normalized['message'] == null) {
      normalized['message'] = 'Done.';
    }
    final commands = normalized['commands'];
    if (commands is List<Object?>) {
      normalized['commands'] =
          commands
              .whereType<Map<String, Object?>>()
              .map(_normalizeCommandJson)
              .toList();
    }

    return normalized;
  }

  AiTaskCommand normalizeCommandStages(
    AiTaskCommand command,
    List<String> stages,
  ) {
    final status = command.status;
    final stageName = command.stageName;
    return AiTaskCommand(
      type: command.type,
      boardId: command.boardId,
      taskId: command.taskId,
      status: status == null ? null : _resolveStageName(status, stages),
      title: command.title,
      description: command.description,
      message: command.message,
      stageName: stageName == null ? null : _formatNewStageName(stageName),
      titles: command.titles,
      commands:
          command.commands
              .map(
                (childCommand) => normalizeCommandStages(childCommand, stages),
              )
              .toList(),
    );
  }

  String? _normalizeAction(String? action) {
    final normalized = _normalize(action ?? '').replaceAll(' ', '_');
    return switch (normalized) {
      'create_board' || 'new_board' || 'add_board' => 'create_board',
      'rename_board' || 'edit_board' || 'update_board' => 'rename_board',
      'create' || 'create_task' || 'new_task' || 'add_task' => 'create',
      'create_many' || 'create_tasks' || 'add_tasks' => 'create_many',
      'move' || 'move_task' || 'put' || 'put_task' => 'move',
      'edit' || 'update' || 'update_task' || 'rename_task' => 'edit',
      'clear_description' || 'remove_description' => 'clear_description',
      'delete' || 'delete_task' || 'remove_task' => 'delete',
      'add_stage' || 'create_stage' || 'new_stage' => 'add_stage',
      'open' || 'open_task' || 'show_task' => 'open_task',
      'open_board' || 'show_board' || 'switch_board' => 'open_board',
      _ => action,
    };
  }

  AiTaskCommand? _planCommandLocally({
    required String boardId,
    required String instruction,
    required List<KanbanTask> tasks,
    required List<String> stages,
    bool allowBatch = true,
  }) {
    final normalized = _normalize(instruction);
    if (allowBatch) {
      final batch = _planBatchCommandLocally(
        boardId: boardId,
        instruction: instruction,
        tasks: tasks,
        stages: stages,
      );
      if (batch != null) {
        return batch;
      }
    }

    if (normalized.startsWith('create board ') ||
        normalized.startsWith('new board ') ||
        normalized.startsWith('add board ')) {
      final title = _afterAny(instruction, [
        'create board',
        'new board',
        'add board',
      ]);
      if (title.isNotEmpty) {
        return AiTaskCommand(
          type: AiTaskCommandType.createBoard,
          boardId: '',
          taskId: '',
          title: _cleanQuoted(title),
          message: 'Created board "${_cleanQuoted(title)}".',
        );
      }
    }

    if (normalized.startsWith('rename board ') ||
        normalized.startsWith('rename board to ') ||
        normalized.startsWith('rename this board ') ||
        normalized.startsWith('rename this board to ') ||
        normalized.startsWith('call this board ')) {
      final title = _afterAny(instruction, [
        'rename this board to',
        'rename board to',
        'rename board',
        'call this board',
      ]);
      if (title.isNotEmpty) {
        return AiTaskCommand(
          type: AiTaskCommandType.renameBoard,
          boardId: boardId,
          taskId: '',
          title: _cleanQuoted(title),
          message: 'Renamed board to "${_cleanQuoted(title)}".',
        );
      }
    }

    if (normalized.startsWith('add stage ') ||
        normalized.startsWith('create stage ') ||
        normalized.startsWith('new stage ')) {
      final stage = _afterAny(instruction, [
        'add stage',
        'create stage',
        'new stage',
      ]);
      if (stage.isNotEmpty) {
        final name = _formatNewStageName(_cleanQuoted(stage));
        return AiTaskCommand(
          type: AiTaskCommandType.addStage,
          boardId: boardId,
          taskId: '',
          stageName: name,
          message: 'Added stage "$name".',
        );
      }
    }

    if (normalized.startsWith('open board ') ||
        normalized.startsWith('show board ') ||
        normalized.startsWith('switch to board ')) {
      final title = _afterAny(instruction, [
        'switch to board',
        'open board',
        'show board',
      ]);
      if (title.isNotEmpty) {
        final boardName = _cleanQuoted(title);
        return AiTaskCommand(
          type: AiTaskCommandType.openBoard,
          boardId: '',
          taskId: '',
          title: boardName,
          message: 'Opened board "$boardName".',
        );
      }
    }

    if (normalized.startsWith('open task ') ||
        normalized.startsWith('show task ')) {
      final task = _findTask(instruction, tasks);
      if (task != null) {
        return AiTaskCommand(
          type: AiTaskCommandType.openTask,
          boardId: task.boardId,
          taskId: task.id,
          title: task.title,
          message: 'Opened "${task.title}".',
        );
      }

      final title = _afterAny(instruction, ['open task', 'show task']);
      if (title.isNotEmpty) {
        final taskTitle = _cleanQuoted(title);
        return AiTaskCommand(
          type: AiTaskCommandType.openTask,
          boardId: boardId,
          taskId: '',
          title: taskTitle,
          message: 'I could not find "$taskTitle".',
        );
      }
    }

    if (normalized.startsWith('create tasks ') ||
        normalized.startsWith('add tasks ') ||
        normalized.startsWith('new tasks ')) {
      final rawTitles = _afterAny(instruction, [
        'create tasks',
        'add tasks',
        'new tasks',
      ]);
      final titles = _splitTaskTitles(rawTitles);
      if (titles.isNotEmpty) {
        return AiTaskCommand(
          type: AiTaskCommandType.createMany,
          boardId: boardId,
          taskId: '',
          titles: titles,
          status: stages.isEmpty ? 'To Do' : stages.first,
          message: 'Created ${titles.length} tasks.',
        );
      }
    }

    if (normalized.startsWith('create task ') ||
        normalized.startsWith('add task ') ||
        normalized.startsWith('new task ')) {
      final title = _afterAny(instruction, [
        'create task',
        'add task',
        'new task',
      ]);
      if (title.isNotEmpty) {
        final titles = _splitRepeatedCreateTaskTitles(instruction);
        if (titles.length > 1) {
          return AiTaskCommand(
            type: AiTaskCommandType.createMany,
            boardId: boardId,
            taskId: '',
            titles: titles,
            status: stages.isEmpty ? 'To Do' : stages.first,
            message: 'Created ${titles.length} tasks.',
          );
        }

        return AiTaskCommand(
          type: AiTaskCommandType.create,
          boardId: boardId,
          taskId: '',
          title: _cleanQuoted(title),
          status: stages.isEmpty ? 'To Do' : stages.first,
          message: 'Created "${_cleanQuoted(title)}".',
        );
      }
    }

    final destination = _findStage(instruction, stages);
    if (_hasMoveIntent(normalized) && !_hasDescriptionIntent(normalized)) {
      final task = _findTask(instruction, tasks);
      if (task != null && destination != null) {
        return AiTaskCommand(
          type: AiTaskCommandType.move,
          boardId: '',
          taskId: task.id,
          status: destination,
          message: 'Moved "${task.title}" to $destination.',
        );
      }
      if (task != null) {
        final requestedStage = _requestedDestination(instruction);
        return AiTaskCommand(
          type: AiTaskCommandType.move,
          boardId: '',
          taskId: task.id,
          message:
              requestedStage.isEmpty
                  ? 'I could not find that destination stage.'
                  : 'I could not find a "$requestedStage" stage.',
        );
      }
    }

    final describedTask = _findTask(instruction, tasks);
    if (describedTask != null &&
        (normalized.contains('add description') ||
            normalized.contains('set description') ||
            normalized.contains('update description'))) {
      final description = _descriptionFromInstruction(
        instruction,
        taskTitle: describedTask.title,
      );
      if (description.isNotEmpty) {
        return AiTaskCommand(
          type: AiTaskCommandType.edit,
          boardId: '',
          taskId: describedTask.id,
          description: description,
          message: 'Updated "${describedTask.title}".',
        );
      }
    }

    final renamedTask = _findTask(instruction, tasks);
    if (renamedTask != null &&
        (normalized.contains('rename ') || normalized.contains('call '))) {
      final title = _titleAfterRenameInstruction(instruction);
      if (title.isNotEmpty) {
        return AiTaskCommand(
          type: AiTaskCommandType.edit,
          boardId: '',
          taskId: renamedTask.id,
          title: title,
          message: 'Renamed task to "$title".',
        );
      }
    }

    final deleteTask = _findTask(instruction, tasks);
    if (deleteTask != null &&
        (normalized.contains('delete ') || normalized.contains('remove '))) {
      return AiTaskCommand(
        type: AiTaskCommandType.delete,
        boardId: '',
        taskId: deleteTask.id,
        message: 'Deleted "${deleteTask.title}".',
      );
    }

    return null;
  }

  String _normalizeSlashCommandInstruction(
    String instruction, {
    bool singleTask = false,
  }) {
    if (!_isSlashCommand(instruction)) {
      return instruction;
    }

    final segments =
        instruction
            .split(RegExp(r'(?=\/[A-Za-z][A-Za-z0-9_-]*)'))
            .map(
              (segment) => _slashCommandSegmentToInstruction(
                segment,
                singleTask: singleTask,
              ),
            )
            .where((segment) => segment.isNotEmpty)
            .toList();

    if (segments.isEmpty) {
      return instruction;
    }

    return segments.join(' ');
  }

  bool _isSlashCommand(String instruction) {
    return instruction.trimLeft().startsWith('/');
  }

  String _slashCommandSegmentToInstruction(
    String segment, {
    required bool singleTask,
  }) {
    final trimmed = segment.trim();
    final match = RegExp(
      r'^\/([A-Za-z][A-Za-z0-9_-]*)(?:\s+(.*))?$',
    ).firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }

    final command = _normalizeSlashCommandName(match.group(1)!);
    final rest = (match.group(2) ?? '').trim();
    final normalizedRest = _normalize(rest);

    if (command == 'create' || command == 'new') {
      if (singleTask) {
        return 'rename this task to $rest'.trim();
      }
      return _startsWithAny(normalizedRest, ['board', 'stage', 'task', 'tasks'])
          ? 'create $rest'.trim()
          : 'create task $rest'.trim();
    }

    if (command == 'add') {
      return _slashAddInstruction(rest, normalizedRest, singleTask);
    }

    if (command == 'adddescription' ||
        command == 'description' ||
        command == 'setdescription' ||
        command == 'updatedescription') {
      if (rest.isEmpty) {
        return 'add description';
      }
      return singleTask ? 'add description: $rest' : 'add description $rest';
    }

    if (command == 'cleardescription' || command == 'removedescription') {
      return 'clear description';
    }

    if (command == 'move' ||
        command == 'put' ||
        command == 'set' ||
        command == 'mark') {
      return singleTask
          ? 'move this task to $rest'.trim()
          : 'move $rest'.trim();
    }

    if (command == 'rename') {
      return singleTask
          ? 'rename this task to $rest'.trim()
          : 'rename $rest'.trim();
    }

    if (command == 'delete' || command == 'remove') {
      return singleTask ? 'delete this task' : 'delete $rest'.trim();
    }

    if (command == 'stage' ||
        command == 'addstage' ||
        command == 'createstage') {
      return singleTask ? trimmed : 'add stage $rest'.trim();
    }

    if (command == 'board' ||
        command == 'createboard' ||
        command == 'newboard') {
      return singleTask ? trimmed : 'create board $rest'.trim();
    }

    if (command == 'renameboard') {
      return singleTask ? trimmed : 'rename board to $rest'.trim();
    }

    if (command == 'open') {
      return singleTask ? trimmed : 'open $rest'.trim();
    }

    if (command == 'opentask') {
      return singleTask ? trimmed : 'open task $rest'.trim();
    }

    if (command == 'openboard') {
      return singleTask ? trimmed : 'open board $rest'.trim();
    }

    return trimmed;
  }

  String _slashAddInstruction(
    String rest,
    String normalizedRest,
    bool singleTask,
  ) {
    if (_startsWithAny(normalizedRest, [
      'description',
      'board',
      'stage',
      'task',
      'tasks',
    ])) {
      return 'add $rest'.trim();
    }

    return singleTask
        ? 'add description: $rest'.trim()
        : 'add task $rest'.trim();
  }

  String _normalizeSlashCommandName(String command) {
    return command.replaceAll(RegExp(r'[-_]'), '').toLowerCase().trim();
  }

  bool _startsWithAny(String value, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (value == prefix || value.startsWith('$prefix ')) {
        return true;
      }
    }
    return false;
  }

  AiTaskCommand? _planBatchCommandLocally({
    required String boardId,
    required String instruction,
    required List<KanbanTask> tasks,
    required List<String> stages,
  }) {
    final parts = _splitCommandClauses(instruction);
    if (parts.length < 2) {
      return null;
    }

    final commands = <AiTaskCommand>[];
    for (final part in parts) {
      final command = _planSingleClauseCommandLocally(
        boardId: boardId,
        instruction: part,
        tasks: tasks,
        stages: stages,
      );
      if (command == null) {
        return null;
      }
      commands.add(command);
    }

    return AiTaskCommand(
      type: AiTaskCommandType.batch,
      boardId: boardId,
      taskId: '',
      commands: commands,
      message: 'Ran ${commands.length} commands.',
    );
  }

  AiTaskCommand? _planSingleClauseCommandLocally({
    required String boardId,
    required String instruction,
    required List<KanbanTask> tasks,
    required List<String> stages,
  }) {
    return _planCommandLocally(
      boardId: boardId,
      instruction: instruction,
      tasks: tasks,
      stages: stages,
      allowBatch: false,
    );
  }

  AiTaskCommand? _planSingleTaskCommandLocally({
    required String instruction,
    required KanbanTask task,
    required List<String> stages,
  }) {
    final normalized = _normalize(instruction);
    final destination = _findStage(instruction, stages);

    if (destination != null &&
        _hasMoveIntent(normalized) &&
        !_hasDescriptionIntent(normalized)) {
      return AiTaskCommand(
        type: AiTaskCommandType.move,
        boardId: '',
        taskId: task.id,
        status: destination,
        message: 'Moved "${task.title}" to $destination.',
      );
    }

    if (_hasMoveIntent(normalized) && !_hasDescriptionIntent(normalized)) {
      final requestedStage = _requestedDestination(instruction);
      return AiTaskCommand(
        type: AiTaskCommandType.move,
        boardId: '',
        taskId: task.id,
        message:
            requestedStage.isEmpty
                ? 'I could not find that destination stage.'
                : 'I could not find a "$requestedStage" stage.',
      );
    }

    if (normalized.contains('clear description') ||
        normalized.contains('remove description')) {
      return AiTaskCommand(
        type: AiTaskCommandType.clearDescription,
        boardId: '',
        taskId: task.id,
        message: 'Cleared task description.',
      );
    }

    if (normalized.contains('add description') ||
        normalized.contains('set description') ||
        normalized.contains('update description')) {
      final description = _descriptionFromInstruction(
        instruction,
        taskTitle: task.title,
      );
      if (description.isNotEmpty) {
        return AiTaskCommand(
          type: AiTaskCommandType.edit,
          boardId: '',
          taskId: task.id,
          description: description,
          message: 'Updated "${task.title}".',
        );
      }
    }

    if (normalized.contains('rename') || normalized.contains('call this')) {
      final title = _titleAfterRenameInstruction(instruction);
      if (title.isNotEmpty) {
        return AiTaskCommand(
          type: AiTaskCommandType.edit,
          boardId: '',
          taskId: task.id,
          title: title,
          message: 'Renamed task to "$title".',
        );
      }
    }

    if (normalized.contains('delete') || normalized.contains('remove')) {
      return AiTaskCommand(
        type: AiTaskCommandType.delete,
        boardId: '',
        taskId: task.id,
        message: 'Deleted "${task.title}".',
      );
    }

    return null;
  }

  KanbanTask? _findTask(String instruction, List<KanbanTask> tasks) {
    final normalizedInstruction = _normalize(instruction);
    KanbanTask? bestTask;
    var bestScore = 0;

    for (final task in tasks) {
      final title = _normalize(task.title);
      if (title.isEmpty) {
        continue;
      }
      var score = 0;
      if (normalizedInstruction.contains(title)) {
        score = title.length + 100;
      } else {
        for (final word in title.split(' ')) {
          if (word.length > 2 && normalizedInstruction.contains(word)) {
            score += word.length;
          }
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestTask = task;
      }
    }

    return bestScore == 0 ? null : bestTask;
  }

  String? _findStage(String instruction, List<String> stages) {
    return _resolveStageName(instruction, stages);
  }

  bool _hasMoveIntent(String normalizedInstruction) {
    return _containsNormalizedPhrase(normalizedInstruction, 'move') ||
        _containsNormalizedPhrase(normalizedInstruction, 'put') ||
        _containsNormalizedPhrase(normalizedInstruction, 'set') ||
        _containsNormalizedPhrase(normalizedInstruction, 'mark');
  }

  bool _hasDescriptionIntent(String normalizedInstruction) {
    return normalizedInstruction.contains('description');
  }

  String _requestedDestination(String instruction) {
    final lowerInstruction = instruction.toLowerCase();
    final markers = [' to ', ' into ', ' in '];
    for (final marker in markers) {
      final index = lowerInstruction.lastIndexOf(marker);
      if (index != -1 && index + marker.length < instruction.length) {
        return _cleanCommandPiece(instruction.substring(index + marker.length));
      }
    }
    return '';
  }

  String? _resolveStageName(String value, List<String> stages) {
    final normalizedInstruction = _normalize(value);
    for (final stage in stages) {
      if (_containsNormalizedPhrase(normalizedInstruction, _normalize(stage))) {
        return stage;
      }
    }
    if (_containsNormalizedPhrase(normalizedInstruction, 'done') ||
        _containsNormalizedPhrase(normalizedInstruction, 'complete') ||
        _containsNormalizedPhrase(normalizedInstruction, 'finished')) {
      return _stageByNormalizedName(stages, 'done');
    }
    if (_containsNormalizedPhrase(normalizedInstruction, 'progress') ||
        _containsNormalizedPhrase(normalizedInstruction, 'doing')) {
      return _stageByNormalizedName(stages, 'in progress');
    }
    if (_containsNormalizedPhrase(normalizedInstruction, 'todo') ||
        _containsNormalizedPhrase(normalizedInstruction, 'to do') ||
        _containsNormalizedPhrase(normalizedInstruction, 'backlog')) {
      return _stageByNormalizedName(stages, 'to do');
    }
    return null;
  }

  bool _containsNormalizedPhrase(
    String normalizedValue,
    String normalizedPhrase,
  ) {
    if (normalizedPhrase.isEmpty) {
      return false;
    }

    final pattern = RegExp(
      r'(^|\s)' + RegExp.escape(normalizedPhrase) + r'($|\s)',
    );
    return pattern.hasMatch(normalizedValue);
  }

  String? _stageByNormalizedName(List<String> stages, String target) {
    final normalizedTarget = _normalize(target);
    for (final stage in stages) {
      if (_normalize(stage) == normalizedTarget) {
        return stage;
      }
    }
    return null;
  }

  String _afterAny(String input, List<String> prefixes) {
    final lowerInput = input.toLowerCase();
    for (final prefix in prefixes) {
      final index = lowerInput.indexOf(prefix);
      if (index != -1) {
        return input.substring(index + prefix.length).trim();
      }
    }
    return '';
  }

  List<String> _splitTaskTitles(String value) {
    final normalized = value
        .replaceAll(RegExp(r'\s*,\s*'), '|')
        .replaceAll(RegExp(r'\s+and\s+'), '|');
    return normalized
        .split('|')
        .map(_cleanQuoted)
        .where((title) => title.isNotEmpty)
        .toList();
  }

  List<String> _splitRepeatedCreateTaskTitles(String instruction) {
    final titles = <String>[];
    final pattern = RegExp(
      r'\b(?:create|add|new)\s+task\s+',
      caseSensitive: false,
    );
    final matches = pattern.allMatches(instruction).toList();
    if (matches.length < 2) {
      return titles;
    }

    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].end;
      final end =
          i == matches.length - 1 ? instruction.length : matches[i + 1].start;
      final title = _cleanCommandPiece(instruction.substring(start, end));
      if (title.isNotEmpty) {
        titles.add(title);
      }
    }

    return titles;
  }

  List<String> _splitCommandClauses(String instruction) {
    final pattern = RegExp(
      r'\b(?:'
      r'create\s+board|new\s+board|add\s+board|'
      r'rename\s+board(?:\s+to)?|rename\s+this\s+board(?:\s+to)?|call\s+this\s+board|'
      r'open\s+board|show\s+board|switch\s+to\s+board|'
      r'open\s+task|show\s+task|'
      r'add\s+stage|create\s+stage|new\s+stage|'
      r'create\s+tasks|add\s+tasks|new\s+tasks|'
      r'create\s+task|add\s+task|new\s+task|'
      r'move|put|set|mark|'
      r'add\s+description|set\s+description|update\s+description|'
      r'clear\s+description|remove\s+description|'
      r'rename|call|delete|remove'
      r')\b',
      caseSensitive: false,
    );
    final matches = pattern.allMatches(instruction).toList();
    if (matches.length < 2) {
      return const [];
    }

    final parts = <String>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i == matches.length - 1 ? instruction.length : matches[i + 1].start;
      final part = _cleanCommandPiece(instruction.substring(start, end));
      if (part.isNotEmpty) {
        parts.add(part);
      }
    }

    return parts;
  }

  String _cleanCommandPiece(String value) {
    return _cleanQuoted(
      value
          .replaceAll(
            RegExp(r'^\s*(?:and|then|also)\s+', caseSensitive: false),
            '',
          )
          .replaceAll(
            RegExp(r'\s+(?:and|then|also)\s*$', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'^[,;]\s*'), '')
          .replaceAll(RegExp(r'\s*[,;]$'), '')
          .trim(),
    );
  }

  String _descriptionFromInstruction(String instruction, {String? taskTitle}) {
    final colonIndex = instruction.indexOf(':');
    if (colonIndex != -1 && colonIndex < instruction.length - 1) {
      return _cleanQuoted(instruction.substring(colonIndex + 1));
    }

    final rawDescription = _afterAny(instruction, [
      'set description of',
      'set description for',
      'set description to',
      'set description',
      'update description of',
      'update description for',
      'update description to',
      'update description',
      'add description to',
      'add description for',
      'add description on',
      'add description',
      'description to',
      'description for',
      'description on',
      'description',
    ]);
    return _stripTaskTitlePrefix(rawDescription, taskTitle);
  }

  String _stripTaskTitlePrefix(String value, String? taskTitle) {
    var cleaned = _cleanQuoted(value);
    if (cleaned.isEmpty || taskTitle == null || taskTitle.trim().isEmpty) {
      return cleaned;
    }

    final normalizedCleaned = _normalize(cleaned);
    final normalizedTitle = _normalize(taskTitle);
    if (normalizedCleaned == normalizedTitle) {
      return '';
    }

    if (normalizedCleaned.startsWith('$normalizedTitle ')) {
      cleaned = cleaned.substring(taskTitle.length).trim();
    }

    return _cleanQuoted(
      cleaned
          .replaceFirst(
            RegExp(r'^(?:to|as|with|that says|says)\s+', caseSensitive: false),
            '',
          )
          .trim(),
    );
  }

  String _titleAfterRenameInstruction(String instruction) {
    return _cleanQuoted(
      _afterAny(instruction, [
        'rename this task to',
        'rename task to',
        'rename this to',
        'rename to',
        'call this task',
        'call this',
        ' to ',
      ]),
    );
  }

  String _cleanQuoted(String value) {
    var cleaned = value.trim();
    while (cleaned.length >= 2 &&
        ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
            (cleaned.startsWith("'") && cleaned.endsWith("'")))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  String _toTitleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) {
          final lower = word.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }

  String _formatNewStageName(String value) {
    if (!sentenceCaseFormattingEnabled) {
      return value.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    return _toTitleCase(value);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildPrompt(
    String boardId,
    String instruction,
    List<KanbanTask> tasks,
    List<String> stages,
  ) {
    final taskJson =
        tasks
            .map(
              (task) => {
                'id': task.id,
                'board_id': task.boardId,
                'title': task.title,
                'description': task.description,
                'status': task.status,
              },
            )
            .toList();

    return '''
You are a command planner for a kanban app.
Return one JSON object only. Do not include markdown.
If the user asks for more than one action, return a batch object with a commands array.

Allowed actions:
- batch: runs multiple commands in order. Requires commands.
- create_board: requires title. board_id, task_id, status, and stage_name must be null.
- rename_board: renames the current board. Requires board_id and title.
- create: creates a task. Requires board_id, title, and status. task_id and stage_name must be null.
- create_many: creates multiple tasks. Requires board_id, titles, and status. task_id and stage_name must be null.
- move: moves or puts a task in a stage. Requires task_id and status.
- edit: edits a task. Requires task_id and at least one of title, description, status.
- clear_description: clears a task description. Requires task_id.
- delete: deletes a task. Requires task_id.
- add_stage: creates a stage. Requires board_id and stage_name.
- open_task: opens a task editor. Requires task_id.
- open_board: switches to a board. Requires title.

Allowed stage/status values for tasks:
${jsonEncode(stages)}

Use only task_id values from the provided tasks. If the user names a task loosely, choose the closest matching task.
For create and add_stage, use this board_id unless the action is create_board: $boardId
${_newStageFormattingInstruction()}
For task status, use the exact stage name from the allowed stage list.

JSON schema:
{
  "action": "batch" | "create_board" | "rename_board" | "create" | "create_many" | "move" | "edit" | "clear_description" | "delete" | "add_stage" | "open_task" | "open_board",
  "board_id": "$boardId or null",
  "task_id": "existing task id or null",
  "status": "exact stage name or null",
  "title": "board or task title or null",
  "titles": ["task title"],
  "description": "description or null",
  "stage_name": "new stage name or null",
  "commands": ["same command object shape, used only for batch"],
  "message": "short confirmation for the user"
}

Tasks:
${jsonEncode(taskJson)}

User instruction:
$instruction
''';
  }

  String _newStageFormattingInstruction() {
    if (!sentenceCaseFormattingEnabled) {
      return "For a new stage name, preserve the user's capitalization.";
    }
    return "For a new stage name, preserve the user's wording as Title Case.";
  }

  String _buildAnalysisPrompt(
    String instruction,
    List<KanbanTask> tasks,
    List<String> stages,
  ) {
    final taskJson =
        tasks
            .map(
              (task) => {
                'title': task.title,
                'description': task.description,
                'status': task.status,
              },
            )
            .toList();

    return '''
You are a board-management analyst for a kanban app.
Read the board and answer the user's analysis request.
Do not modify tasks. Do not return JSON. Do not return function calls.
Never include <start_function_call> or <end_function_call> tokens.
Keep the answer concise, practical, and specific to the board.

Stages:
${jsonEncode(stages)}

Useful sections when relevant:
- Summary
- Risks
- Suggested next step
- Cleanup ideas

Tasks:
${jsonEncode(taskJson)}

User analysis request:
$instruction
''';
  }

  String _buildChatPrompt(
    String message,
    List<KanbanTask> tasks,
    List<String> stages,
  ) {
    final taskJson =
        tasks
            .map(
              (task) => {
                'title': task.title,
                'description': task.description,
                'status': task.status,
              },
            )
            .toList();

    return '''
You are an offline board assistant inside a kanban app.
Answer the user's question conversationally and practically.
Do not modify tasks. Do not return JSON. Do not return function calls.
Never include <start_function_call> or <end_function_call> tokens.
If the user asks for an action, explain the command they can run in Command mode.
Keep the answer concise.

Stages:
${jsonEncode(stages)}

Tasks:
${jsonEncode(taskJson)}

User message:
$message
''';
  }

  String _buildSingleTaskPrompt({
    required String instruction,
    required KanbanTask task,
    required List<String> stages,
  }) {
    return '''
You are a command planner for one existing kanban task.
Return one JSON object only. Do not include markdown.

Allowed actions for this screen:
- move: move or put this task in a stage.
- edit: edit title, description, and/or status for this task.
- clear_description: clear the description for this task.
- delete: delete this task.

Forbidden actions:
- create_board
- rename_board
- create
- create_many
- add_stage

Allowed stage/status values:
${jsonEncode(stages)}

Always use this task_id: ${task.id}
For task status, use the exact stage name from the allowed stage list.

JSON schema:
{
  "action": "move" | "edit" | "clear_description" | "delete",
  "board_id": null,
  "task_id": "${task.id}",
  "status": "exact stage name or null",
  "title": "new title or null",
  "description": "new description or null",
  "stage_name": null,
  "message": "short confirmation for the user"
}

Current task:
{
  "id": ${jsonEncode(task.id)},
  "title": ${jsonEncode(task.title)},
  "description": ${jsonEncode(task.description)},
  "status": ${jsonEncode(task.status)}
}

User instruction:
$instruction
''';
  }
}

class AiNotConfiguredException implements Exception {
  const AiNotConfiguredException();

  @override
  String toString() {
    return 'Install an offline AI model before using AI commands.';
  }
}

class AiCommandException implements Exception {
  const AiCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}
