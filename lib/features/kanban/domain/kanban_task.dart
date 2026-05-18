const demoBoardId = 'default-board';

class TaskPriority {
  const TaskPriority._();

  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';
  static const urgent = 'urgent';
  static const defaultValue = medium;
  static const values = [low, medium, high, urgent];

  static String normalize(String? value) {
    final normalized = value?.toLowerCase();
    return values.contains(normalized) ? normalized! : defaultValue;
  }

  static String label(String value) {
    return switch (normalize(value)) {
      low => 'Low',
      medium => 'Medium',
      high => 'High',
      urgent => 'Urgent',
      _ => 'Medium',
    };
  }

  static int rank(String value) {
    return switch (normalize(value)) {
      urgent => 0,
      high => 1,
      medium => 2,
      low => 3,
      _ => 2,
    };
  }

  static int compareTasks(KanbanTask a, KanbanTask b) {
    final priority = rank(a.priority).compareTo(rank(b.priority));
    if (priority != 0) {
      return priority;
    }
    final sortOrder = a.sortOrder.compareTo(b.sortOrder);
    if (sortOrder != 0) {
      return sortOrder;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  }
}

class KanbanTask {
  const KanbanTask({
    required this.id,
    required this.boardId,
    required this.title,
    required this.status,
    this.priority = TaskPriority.defaultValue,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.assigneeId,
    this.createdBy,
    this.updatedBy,
    this.dueAt,
    this.attachmentUrls = const [],
  });

  final String id;
  final String boardId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? assigneeId;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? dueAt;
  final List<String> attachmentUrls;
}

class KanbanBoard {
  const KanbanBoard({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.boardType = 'project',
    this.description,
  });

  final String id;
  final String name;
  final String boardType;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isProject => boardType == 'project';
  bool get isList => boardType == 'list';
}

class KanbanStage {
  const KanbanStage({
    required this.id,
    required this.boardId,
    required this.name,
    required this.sortOrder,
    this.colorValue,
  });

  final String id;
  final String boardId;
  final String name;
  final int sortOrder;
  final int? colorValue;
}

class KanbanBoardMember {
  const KanbanBoardMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.createdAt,
    required this.isOwner,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String email;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String role;
  final DateTime createdAt;
  final bool isOwner;

  bool get canManageMembers => isOwner || role == 'owner';
  bool get canEdit => canManageMembers || role == 'editor';
  String get displayLabel =>
      displayName == null || displayName!.isEmpty ? email : displayName!;
  String get handle =>
      username == null || username!.isEmpty ? email : '@$username';
}

class KanbanBoardInvite {
  const KanbanBoardInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.createdAt,
    this.acceptedAt,
  });

  final String id;
  final String email;
  final String role;
  final DateTime createdAt;
  final DateTime? acceptedAt;
}

class KanbanPendingBoardInvite {
  const KanbanPendingBoardInvite({
    required this.id,
    required this.boardId,
    required this.boardName,
    required this.email,
    required this.role,
    required this.createdAt,
    this.inviterEmail,
  });

  final String id;
  final String boardId;
  final String boardName;
  final String email;
  final String role;
  final DateTime createdAt;
  final String? inviterEmail;
}

class KanbanTaskComment {
  const KanbanTaskComment({
    required this.id,
    required this.taskId,
    required this.boardId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.authorId,
    this.authorEmail,
  });

  final String id;
  final String taskId;
  final String boardId;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? authorId;
  final String? authorEmail;
}

class KanbanActivityEvent {
  const KanbanActivityEvent({
    required this.id,
    required this.boardId,
    required this.eventType,
    required this.createdAt,
    this.actorId,
    this.actorEmail,
    this.taskId,
    this.stageId,
    this.subject,
  });

  final String id;
  final String boardId;
  final String eventType;
  final DateTime createdAt;
  final String? actorId;
  final String? actorEmail;
  final String? taskId;
  final String? stageId;
  final String? subject;
}

class KanbanBoardMessage {
  const KanbanBoardMessage({
    required this.id,
    required this.boardId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.authorId,
    this.replyToMessageId,
  });

  final String id;
  final String boardId;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? authorId;
  final String? replyToMessageId;
}

class KanbanMessageReaction {
  const KanbanMessageReaction({
    required this.id,
    required this.boardId,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  final String id;
  final String boardId;
  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;
}

class KanbanPresenceUser {
  const KanbanPresenceUser({
    required this.userId,
    required this.email,
    this.editingTaskId,
  });

  final String userId;
  final String email;
  final String? editingTaskId;
}

class KanbanNotification {
  const KanbanNotification({
    required this.id,
    required this.recipientId,
    required this.notificationType,
    required this.sourceKey,
    required this.createdAt,
    this.boardId,
    this.actorId,
    this.actorDisplayName,
    this.taskId,
    this.subject,
  });

  final String id;
  final String recipientId;
  final String? boardId;
  final String? actorId;
  final String? actorDisplayName;
  final String notificationType;
  final String? taskId;
  final String? subject;
  final String sourceKey;
  final DateTime createdAt;

  String get title {
    return switch (notificationType) {
      'chat' => 'New chat message',
      'invite' => 'Board invitation',
      'mention' => 'You were mentioned',
      'task_created' => 'New task',
      'task_updated' => 'Task updated',
      'task_moved' => 'Task moved',
      'comment_added' => 'New comment',
      _ => 'Notification',
    };
  }
}
