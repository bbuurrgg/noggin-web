import 'dart:typed_data';

import 'kanban_task.dart';

abstract interface class KanbanRepository {
  Stream<List<KanbanBoard>> watchBoards();

  Future<List<KanbanBoard>> listBoards();

  Stream<List<KanbanTask>> watchTasks(String boardId);

  Future<List<KanbanTask>> listTasks(String boardId);

  Future<String> createBoard({
    required String name,
    String? description,
    String boardType = 'project',
  });

  Future<void> renameBoard({
    required String boardId,
    required String name,
    String? boardType,
  });

  Future<String> createTask({
    required String boardId,
    required String title,
    String? description,
    required String status,
    String priority = TaskPriority.defaultValue,
    String? assigneeId,
    DateTime? dueAt,
  });

  Future<void> moveTask({
    required String taskId,
    required String status,
    int? sortOrder,
  });

  Future<KanbanTask?> findTaskBySpokenTitle(String boardId, String spokenTitle);

  Future<void> updateTaskTitle({required String taskId, required String title});

  Future<void> updateTask({
    required String taskId,
    String? title,
    String? description,
    String? status,
    String? priority,
    String? assigneeId,
    DateTime? dueAt,
    bool clearDueAt = false,
    List<String>? attachmentUrls,
  });

  Future<String> uploadTaskAttachment({
    required String boardId,
    required String taskId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  });

  Future<void> clearTaskDescription(String taskId);

  Future<void> deleteTask(String taskId);

  Stream<List<KanbanStage>> watchStages(String boardId);
  Future<List<KanbanStage>> listStages(String boardId);
  Future<void> createStage({
    required String boardId,
    required String name,
    int? colorValue,
  });
  Future<void> updateStageName({
    required String stageId,
    required String oldName,
    required String newName,
    required String boardId,
  });
  Future<void> reorderStages(List<String> stageIds);
  Future<void> deleteStage(String stageId);
  Future<void> deleteBoard(String boardId);

  Future<List<KanbanBoardMember>> listBoardMembers(String boardId);

  Future<List<KanbanBoardInvite>> listBoardInvites(String boardId);

  Future<List<KanbanPendingBoardInvite>> listPendingInvites();

  Future<void> inviteBoardMember({
    required String boardId,
    required String email,
    required String role,
  });

  Future<void> removeBoardMember({
    required String boardId,
    required String userId,
  });

  Future<void> leaveBoard(String boardId);

  Future<void> cancelBoardInvite({
    required String boardId,
    required String inviteId,
  });

  Future<String> acceptBoardInvite(String inviteId);

  Future<void> declineBoardInvite(String inviteId);

  Future<void> updateBoardMemberRole({
    required String boardId,
    required String userId,
    required String role,
  });

  Stream<List<KanbanTaskComment>> watchTaskComments(String taskId);

  Future<void> addTaskComment({
    required String boardId,
    required String taskId,
    required String body,
  });

  Future<void> deleteTaskComment(String commentId);

  Stream<List<KanbanActivityEvent>> watchBoardActivity(String boardId);

  Future<List<KanbanActivityEvent>> listBoardActivity({
    required String boardId,
    DateTime? before,
    int limit = 50,
  });

  Stream<List<KanbanBoardMessage>> watchBoardMessages(String boardId);

  Future<List<KanbanBoardMessage>> listBoardMessages({
    required String boardId,
    DateTime? before,
    int limit = 50,
  });

  Future<void> addBoardMessage({
    required String boardId,
    required String body,
    String? messageId,
    String? replyToMessageId,
  });

  Future<void> deleteBoardMessage(String messageId);

  Stream<List<KanbanMessageReaction>> watchBoardMessageReactions(
    String boardId,
  );

  Future<void> toggleBoardMessageReaction({
    required String boardId,
    required String messageId,
    required String emoji,
  });

  Stream<List<KanbanNotification>> watchNotifications();

  Future<void> markNotificationsRead({
    String? boardId,
    String? taskId,
    String? notificationType,
  });
}
