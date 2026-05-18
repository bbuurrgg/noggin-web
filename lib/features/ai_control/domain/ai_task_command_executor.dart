import '../../kanban/domain/kanban_repository.dart';
import 'ai_task_command.dart';

class AiTaskCommandExecutor {
  const AiTaskCommandExecutor(this._repository);

  final KanbanRepository _repository;

  Future<AiTaskCommandResult> execute(AiTaskCommand command) async {
    switch (command.type) {
      case AiTaskCommandType.batch:
        if (command.commands.isEmpty) {
          return const AiTaskCommandResult(
            success: false,
            message: 'The on-device AI did not provide any commands.',
          );
        }

        final messages = <String>[];
        var successCount = 0;
        for (final childCommand in command.commands) {
          final result = await execute(childCommand);
          messages.add(result.message);
          if (result.success) {
            successCount++;
            continue;
          }

          return AiTaskCommandResult(
            success: false,
            message:
                'Ran $successCount of ${command.commands.length} commands. ${result.message}',
          );
        }

        return AiTaskCommandResult(
          success: true,
          message:
              command.message ??
              'Ran $successCount command${successCount == 1 ? '' : 's'}. ${messages.join(' ')}',
        );
      case AiTaskCommandType.createBoard:
        final title = command.title;
        if (title == null || title.isEmpty) {
          return const AiTaskCommandResult(
            success: false,
            message: 'The on-device AI did not provide a board name.',
          );
        }
        await _repository.createBoard(
          name: title,
          description: command.description,
        );
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Created board "$title".',
        );
      case AiTaskCommandType.renameBoard:
        final title = command.title;
        if (command.boardId.isEmpty || title == null || title.isEmpty) {
          return const AiTaskCommandResult(
            success: false,
            message: 'The on-device AI did not provide a board rename.',
          );
        }
        await _repository.renameBoard(boardId: command.boardId, name: title);
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Renamed board to "$title".',
        );
      case AiTaskCommandType.create:
        final title = command.title;
        final status = command.status;
        if (command.boardId.isEmpty || title == null || title.isEmpty) {
          return const AiTaskCommandResult(
            success: false,
            message:
                'The on-device AI did not provide enough details to create a task.',
          );
        }
        await _repository.createTask(
          boardId: command.boardId,
          title: title,
          description: command.description,
          status: status == null || status.isEmpty ? 'To Do' : status,
        );
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Created "$title".',
        );
      case AiTaskCommandType.createMany:
        final titles =
            command.titles.isNotEmpty
                ? command.titles
                : [
                  if (command.title != null && command.title!.isNotEmpty)
                    command.title!,
                ];
        if (command.boardId.isEmpty || titles.isEmpty) {
          return const AiTaskCommandResult(
            success: false,
            message: 'The on-device AI did not provide tasks to create.',
          );
        }
        final status =
            command.status == null || command.status!.isEmpty
                ? 'To Do'
                : command.status!;
        for (final title in titles) {
          await _repository.createTask(
            boardId: command.boardId,
            title: title,
            description: command.description,
            status: status,
          );
        }
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Created ${titles.length} tasks.',
        );
      case AiTaskCommandType.move:
        final taskCheck = _requireTask(command);
        if (taskCheck != null) {
          return taskCheck;
        }
        final status = command.status;
        if (status == null || status.isEmpty) {
          return AiTaskCommandResult(
            success: false,
            message:
                command.message ??
                'The on-device AI did not choose a destination stage.',
          );
        }
        await _repository.moveTask(taskId: command.taskId, status: status);
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Moved task to $status.',
        );
      case AiTaskCommandType.edit:
        final taskCheck = _requireTask(command);
        if (taskCheck != null) {
          return taskCheck;
        }
        if (command.title == null &&
            command.description == null &&
            command.status == null) {
          return const AiTaskCommandResult(
            success: false,
            message: 'The on-device AI did not provide an edit.',
          );
        }
        await _repository.updateTask(
          taskId: command.taskId,
          title: command.title,
          description: command.description,
          status: command.status,
        );
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Updated task.',
        );
      case AiTaskCommandType.clearDescription:
        final taskCheck = _requireTask(command);
        if (taskCheck != null) {
          return taskCheck;
        }
        await _repository.clearTaskDescription(command.taskId);
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Cleared task description.',
        );
      case AiTaskCommandType.delete:
        final taskCheck = _requireTask(command);
        if (taskCheck != null) {
          return taskCheck;
        }
        await _repository.deleteTask(command.taskId);
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Deleted task.',
        );
      case AiTaskCommandType.addStage:
        final stageName = command.stageName ?? command.status ?? command.title;
        if (command.boardId.isEmpty || stageName == null || stageName.isEmpty) {
          return const AiTaskCommandResult(
            success: false,
            message:
                'The on-device AI did not provide enough details to add a stage.',
          );
        }
        await _repository.createStage(
          boardId: command.boardId,
          name: stageName,
        );
        return AiTaskCommandResult(
          success: true,
          message: command.message ?? 'Added stage "$stageName".',
        );
      case AiTaskCommandType.openTask:
      case AiTaskCommandType.openBoard:
        return const AiTaskCommandResult(
          success: false,
          message: 'This command needs to be handled by the app screen.',
        );
      case AiTaskCommandType.unknown:
        return const AiTaskCommandResult(
          success: false,
          message: 'The on-device AI returned an unsupported action.',
        );
    }
  }

  AiTaskCommandResult? _requireTask(AiTaskCommand command) {
    if (command.taskId.isEmpty) {
      return const AiTaskCommandResult(
        success: false,
        message: 'The on-device AI did not identify a task.',
      );
    }
    return null;
  }
}
