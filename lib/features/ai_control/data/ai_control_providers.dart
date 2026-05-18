import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../kanban/data/kanban_providers.dart';
import '../domain/ai_task_command_executor.dart';
import 'on_device_llm_task_command_service.dart';

final onDeviceLlmTaskCommandServiceProvider =
    Provider<OnDeviceLlmTaskCommandService>((ref) {
      return const OnDeviceLlmTaskCommandService(
        sentenceCaseFormattingEnabled:
            FeatureFlags.sentenceCaseFormattingEnabled,
      );
    });

final aiTaskCommandExecutorProvider = Provider<AiTaskCommandExecutor>((ref) {
  return AiTaskCommandExecutor(ref.watch(kanbanRepositoryProvider));
});

final runOnDeviceLlmTaskCommandProvider = FutureProvider.autoDispose
    .family<String, OnDeviceLlmTaskCommandRequest>((ref, request) async {
      final repository = ref.watch(kanbanRepositoryProvider);
      final tasks = await repository.listTasks(request.boardId);
      final stages = await repository.listStages(request.boardId);
      final command = await ref
          .watch(onDeviceLlmTaskCommandServiceProvider)
          .planCommand(
            boardId: request.boardId,
            instruction: request.instruction,
            tasks: tasks,
            stages: stages.map((stage) => stage.name).toList(),
          );
      final result = await ref
          .watch(aiTaskCommandExecutorProvider)
          .execute(command);

      if (!result.success) {
        throw AiCommandException(result.message);
      }

      return result.message;
    });

class OnDeviceLlmTaskCommandRequest {
  const OnDeviceLlmTaskCommandRequest({
    required this.boardId,
    required this.instruction,
  });

  final String boardId;
  final String instruction;

  @override
  bool operator ==(Object other) {
    return other is OnDeviceLlmTaskCommandRequest &&
        other.boardId == boardId &&
        other.instruction == instruction;
  }

  @override
  int get hashCode => Object.hash(boardId, instruction);
}
