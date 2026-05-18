enum AiTaskCommandType {
  batch,
  createBoard,
  renameBoard,
  create,
  createMany,
  move,
  edit,
  clearDescription,
  delete,
  addStage,
  openTask,
  openBoard,
  unknown;

  static AiTaskCommandType fromJson(String? value) {
    return switch (value) {
      'batch' => AiTaskCommandType.batch,
      'create_board' => AiTaskCommandType.createBoard,
      'rename_board' => AiTaskCommandType.renameBoard,
      'create' => AiTaskCommandType.create,
      'create_many' => AiTaskCommandType.createMany,
      'move' => AiTaskCommandType.move,
      'edit' => AiTaskCommandType.edit,
      'clear_description' => AiTaskCommandType.clearDescription,
      'delete' => AiTaskCommandType.delete,
      'add_stage' => AiTaskCommandType.addStage,
      'open_task' => AiTaskCommandType.openTask,
      'open_board' => AiTaskCommandType.openBoard,
      _ => AiTaskCommandType.unknown,
    };
  }
}

class AiTaskCommand {
  const AiTaskCommand({
    required this.type,
    required this.boardId,
    required this.taskId,
    this.status,
    this.title,
    this.description,
    this.message,
    this.stageName,
    this.titles = const [],
    this.commands = const [],
  });

  final AiTaskCommandType type;
  final String boardId;
  final String taskId;
  final String? status;
  final String? title;
  final String? description;
  final String? message;
  final String? stageName;
  final List<String> titles;
  final List<AiTaskCommand> commands;

  factory AiTaskCommand.fromJson(Map<String, Object?> json) {
    final titlesJson = json['titles'] as List<Object?>? ?? const [];
    final commandsJson = json['commands'] as List<Object?>? ?? const [];
    return AiTaskCommand(
      type:
          commandsJson.isNotEmpty
              ? AiTaskCommandType.batch
              : AiTaskCommandType.fromJson(json['action'] as String?),
      boardId: (json['board_id'] as String? ?? '').trim(),
      taskId: (json['task_id'] as String? ?? '').trim(),
      status: (json['status'] as String?)?.trim(),
      title: (json['title'] as String?)?.trim(),
      description: (json['description'] as String?)?.trim(),
      message: (json['message'] as String?)?.trim(),
      stageName: (json['stage_name'] as String?)?.trim(),
      titles:
          titlesJson
              .map((item) {
                if (item is String) {
                  return item;
                }
                if (item is Map<String, Object?>) {
                  return item['title'] as String? ??
                      item['name'] as String? ??
                      '';
                }
                return '';
              })
              .map((title) => title.trim())
              .where((title) => title.isNotEmpty)
              .toList(),
      commands:
          commandsJson
              .whereType<Map<String, Object?>>()
              .map(AiTaskCommand.fromJson)
              .toList(),
    );
  }
}

class AiTaskCommandResult {
  const AiTaskCommandResult({required this.success, required this.message});

  final bool success;
  final String message;
}
