import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show
        AsyncValue,
        AsyncValueX,
        FutureProvider,
        Provider,
        StateProvider,
        StreamProvider,
        WidgetRef;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/kanban_task.dart';
import '../domain/kanban_repository.dart';
import 'supabase_kanban_repository.dart';

final supabaseKanbanRepositoryProvider = Provider<SupabaseKanbanRepository>((
  ref,
) {
  return SupabaseKanbanRepository(ref.watch(supabaseClientProvider));
});

final kanbanRepositoryProvider = Provider<KanbanRepository>((ref) {
  return ref.watch(supabaseKanbanRepositoryProvider);
});

final tasksForStatusProvider = Provider.autoDispose
    .family<AsyncValue<List<KanbanTask>>, TasksForStatusRequest>((
      ref,
      request,
    ) {
      final statusTasks = ref.watch(
        boardTasksProvider(request.boardId).select((tasksValue) {
          return tasksValue.when(
            data:
                (tasks) => AsyncValue.data(
                  _TasksForStatusSnapshot.fromTasks(tasks, request.status),
                ),
            loading: () => const AsyncValue<_TasksForStatusSnapshot>.loading(),
            error: AsyncValue<_TasksForStatusSnapshot>.error,
          );
        }),
      );

      return statusTasks.when(
        data: (snapshot) => AsyncValue.data(snapshot.tasks),
        loading: () => const AsyncValue.loading(),
        error: AsyncValue.error,
      );
    });

final taskByIdProvider = Provider.autoDispose
    .family<AsyncValue<KanbanTask?>, TaskByIdRequest>((ref, request) {
      final selection = ref.watch(
        boardTasksProvider(request.boardId).select((tasksValue) {
          return tasksValue.when(
            data:
                (tasks) => _TaskByIdSelection.data(
                  _TaskByIdSnapshot.fromTasks(tasks, request.taskId),
                ),
            loading: _TaskByIdSelection.loading,
            error: _TaskByIdSelection.error,
          );
        }),
      );

      return selection.toAsyncValue();
    });

KanbanTask? _taskById(List<KanbanTask> tasks, String taskId) {
  for (final task in tasks) {
    if (task.id == taskId) {
      return task;
    }
  }
  return null;
}

final allTasksProvider = StreamProvider.autoDispose<List<KanbanTask>>((ref) {
  return ref.watch(kanbanRepositoryProvider).watchTasks(demoBoardId);
});

final boardTasksProvider = StreamProvider.autoDispose
    .family<List<KanbanTask>, String>((ref, boardId) {
      return ref.watch(kanbanRepositoryProvider).watchTasks(boardId);
    });

final allBoardsProvider = StreamProvider.autoDispose<List<KanbanBoard>>((ref) {
  return ref.watch(kanbanRepositoryProvider).watchBoards();
});

final stagesProvider = StreamProvider.autoDispose
    .family<List<KanbanStage>, String>((ref, boardId) {
      return ref.watch(kanbanRepositoryProvider).watchStages(boardId);
    });

final boardMembersProvider = FutureProvider.autoDispose
    .family<List<KanbanBoardMember>, String>((ref, boardId) {
      return ref.watch(kanbanRepositoryProvider).listBoardMembers(boardId);
    });

final boardInvitesProvider = FutureProvider.autoDispose
    .family<List<KanbanBoardInvite>, String>((ref, boardId) {
      return ref.watch(kanbanRepositoryProvider).listBoardInvites(boardId);
    });

final pendingBoardInvitesProvider =
    FutureProvider.autoDispose<List<KanbanPendingBoardInvite>>((ref) {
      return ref.watch(kanbanRepositoryProvider).listPendingInvites();
    });

final canEditBoardProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  boardId,
) async {
  if (boardId == demoBoardId) {
    return true;
  }

  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return false;
  }

  final members = await ref.watch(boardMembersProvider(boardId).future);
  for (final member in members) {
    if (member.userId == userId) {
      return member.canEdit;
    }
  }
  return false;
});

final boardAccessProvider = FutureProvider.autoDispose
    .family<KanbanBoardMember?, String>((ref, boardId) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) {
        return null;
      }

      if (boardId == demoBoardId) {
        final user = ref.watch(supabaseClientProvider).auth.currentUser;
        return KanbanBoardMember(
          userId: userId,
          email: user?.email ?? 'Signed-in user',
          username: null,
          displayName: user?.email ?? 'Signed-in user',
          avatarUrl: null,
          role: 'owner',
          createdAt: DateTime.now(),
          isOwner: true,
        );
      }

      final members = await ref.watch(boardMembersProvider(boardId).future);
      for (final member in members) {
        if (member.userId == userId) {
          return member;
        }
      }
      return null;
    });

final taskCommentsProvider = StreamProvider.autoDispose
    .family<List<KanbanTaskComment>, String>((ref, taskId) {
      return ref.watch(kanbanRepositoryProvider).watchTaskComments(taskId);
    });

final boardActivityProvider = StreamProvider.autoDispose
    .family<List<KanbanActivityEvent>, String>((ref, boardId) {
      return ref.watch(kanbanRepositoryProvider).watchBoardActivity(boardId);
    });

final boardMessagesProvider = StreamProvider.autoDispose
    .family<List<KanbanBoardMessage>, String>((ref, boardId) {
      return ref.watch(kanbanRepositoryProvider).watchBoardMessages(boardId);
    });

final boardMessageReactionsProvider = StreamProvider.autoDispose
    .family<List<KanbanMessageReaction>, String>((ref, boardId) {
      return ref
          .watch(kanbanRepositoryProvider)
          .watchBoardMessageReactions(boardId);
    });

final notificationsProvider =
    StreamProvider.autoDispose<List<KanbanNotification>>((ref) {
      return ref.watch(kanbanRepositoryProvider).watchNotifications();
    });

final boardPresenceProvider = StreamProvider.autoDispose
    .family<List<KanbanPresenceUser>, String>((ref, boardId) {
      final client = ref.watch(supabaseClientProvider);
      final user = ref.watch(currentUserProvider);
      if (user == null || boardId == demoBoardId) {
        return Stream.value(const []);
      }

      final controller = StreamController<List<KanbanPresenceUser>>();
      final channel = client.channel(
        'board-presence:$boardId',
        opts: RealtimeChannelConfig(key: user.id, enabled: true),
      );

      void emit() {
        final users = <String, KanbanPresenceUser>{};
        for (final state in channel.presenceState()) {
          for (final presence in state.presences) {
            final payload = presence.payload;
            final userId = payload['user_id'] as String? ?? state.key;
            if (userId == user.id) {
              continue;
            }
            users[userId] = KanbanPresenceUser(
              userId: userId,
              email: payload['email'] as String? ?? 'Collaborator',
              editingTaskId: payload['editing_task_id'] as String?,
            );
          }
        }
        if (!controller.isClosed) {
          controller.add(users.values.toList());
        }
      }

      channel
          .onPresenceSync((_) => emit())
          .onPresenceJoin((_) => emit())
          .onPresenceLeave((_) => emit())
          .subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              channel.track({
                'user_id': user.id,
                'email': user.email ?? 'Collaborator',
                'viewing_board_id': boardId,
              });
            }
          });

      ref.onDispose(() async {
        await channel.untrack();
        await client.removeChannel(channel);
        await controller.close();
      });

      return controller.stream;
    });

/// Tracks the currently selected board ID. Defaults to the virtual All Tasks view.
final selectedBoardIdProvider = StateProvider<String>((ref) {
  return demoBoardId;
});

void invalidateBoardList(WidgetRef ref) {
  ref.invalidate(allBoardsProvider);
  ref.invalidate(pendingBoardInvitesProvider);
}

void invalidateBoard(WidgetRef ref, String boardId) {
  ref.invalidate(allTasksProvider);
  ref.invalidate(stagesProvider(boardId));
  ref.invalidate(boardActivityProvider(boardId));
  ref.invalidate(boardMessagesProvider(boardId));
  ref.invalidate(boardMessageReactionsProvider(boardId));
  ref.invalidate(notificationsProvider);
}

void invalidateBoardTaskSideEffects(WidgetRef ref, String boardId) {
  ref.invalidate(allTasksProvider);
  ref.invalidate(boardActivityProvider(boardId));
  ref.invalidate(notificationsProvider);
}

void invalidateBoardCollaboration(WidgetRef ref, String boardId) {
  ref.invalidate(boardMembersProvider(boardId));
  ref.invalidate(boardInvitesProvider(boardId));
  ref.invalidate(boardAccessProvider(boardId));
  ref.invalidate(canEditBoardProvider(boardId));
}

void invalidateKanban(WidgetRef ref, {String? boardId}) {
  invalidateBoardList(ref);
  if (boardId != null) {
    invalidateBoard(ref, boardId);
  }
}

class TasksForStatusRequest {
  const TasksForStatusRequest({required this.boardId, required this.status});

  final String boardId;
  final String status;

  @override
  bool operator ==(Object other) {
    return other is TasksForStatusRequest &&
        other.boardId == boardId &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(boardId, status);
}

class TaskByIdRequest {
  const TaskByIdRequest({required this.boardId, required this.taskId});

  final String boardId;
  final String taskId;

  @override
  bool operator ==(Object other) {
    return other is TaskByIdRequest &&
        other.boardId == boardId &&
        other.taskId == taskId;
  }

  @override
  int get hashCode => Object.hash(boardId, taskId);
}

class _TasksForStatusSnapshot {
  _TasksForStatusSnapshot._(this.tasks, this._signature);

  factory _TasksForStatusSnapshot.fromTasks(
    List<KanbanTask> allTasks,
    String status,
  ) {
    final tasks =
        allTasks.where((task) => task.status == status).toList()
          ..sort(TaskPriority.compareTasks);

    return _TasksForStatusSnapshot._(
      tasks,
      tasks.map(_TaskSignature.fromTask).toList(),
    );
  }

  final List<KanbanTask> tasks;
  final List<_TaskSignature> _signature;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! _TasksForStatusSnapshot ||
        other._signature.length != _signature.length) {
      return false;
    }
    for (var index = 0; index < _signature.length; index++) {
      if (_signature[index] != other._signature[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_signature);
}

class _TaskByIdSnapshot {
  _TaskByIdSnapshot._(this.task, this._signature);

  factory _TaskByIdSnapshot.fromTasks(List<KanbanTask> tasks, String taskId) {
    final task = _taskById(tasks, taskId);
    return _TaskByIdSnapshot._(
      task,
      task == null ? null : _TaskCardSignature.fromTask(task),
    );
  }

  final KanbanTask? task;
  final _TaskCardSignature? _signature;

  @override
  bool operator ==(Object other) {
    return other is _TaskByIdSnapshot && other._signature == _signature;
  }

  @override
  int get hashCode => _signature.hashCode;
}

class _TaskByIdSelection {
  const _TaskByIdSelection._({
    required this.state,
    this.snapshot,
    this.error,
    this.stackTrace,
  });

  factory _TaskByIdSelection.data(_TaskByIdSnapshot snapshot) {
    return _TaskByIdSelection._(
      state: _TaskByIdSelectionState.data,
      snapshot: snapshot,
    );
  }

  factory _TaskByIdSelection.loading() {
    return const _TaskByIdSelection._(state: _TaskByIdSelectionState.loading);
  }

  factory _TaskByIdSelection.error(Object error, StackTrace stackTrace) {
    return _TaskByIdSelection._(
      state: _TaskByIdSelectionState.error,
      error: error,
      stackTrace: stackTrace,
    );
  }

  final _TaskByIdSelectionState state;
  final _TaskByIdSnapshot? snapshot;
  final Object? error;
  final StackTrace? stackTrace;

  AsyncValue<KanbanTask?> toAsyncValue() {
    return switch (state) {
      _TaskByIdSelectionState.data => AsyncValue.data(snapshot?.task),
      _TaskByIdSelectionState.loading => const AsyncValue.loading(),
      _TaskByIdSelectionState.error => AsyncValue.error(error!, stackTrace!),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is _TaskByIdSelection &&
        other.state == state &&
        other.snapshot == snapshot &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(state, snapshot, error);
}

enum _TaskByIdSelectionState { data, loading, error }

class _TaskSignature {
  const _TaskSignature({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.sortOrder,
    required this.updatedAt,
    required this.assigneeId,
    required this.dueAt,
    required this.attachmentUrls,
  });

  factory _TaskSignature.fromTask(KanbanTask task) {
    return _TaskSignature(
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      sortOrder: task.sortOrder,
      updatedAt: task.updatedAt,
      assigneeId: task.assigneeId,
      dueAt: task.dueAt,
      attachmentUrls: Object.hashAll(task.attachmentUrls),
    );
  }

  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final int sortOrder;
  final DateTime updatedAt;
  final String? assigneeId;
  final DateTime? dueAt;
  final int attachmentUrls;

  @override
  bool operator ==(Object other) {
    return other is _TaskSignature &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.status == status &&
        other.priority == priority &&
        other.sortOrder == sortOrder &&
        other.updatedAt == updatedAt &&
        other.assigneeId == assigneeId &&
        other.dueAt == dueAt &&
        other.attachmentUrls == attachmentUrls;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      description,
      status,
      priority,
      sortOrder,
      updatedAt,
      assigneeId,
      dueAt,
      attachmentUrls,
    );
  }
}

class _TaskCardSignature {
  const _TaskCardSignature({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.updatedDay,
    required this.assigneeId,
    required this.dueAt,
    required this.attachmentUrls,
  });

  factory _TaskCardSignature.fromTask(KanbanTask task) {
    return _TaskCardSignature(
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      updatedDay: DateTime(
        task.updatedAt.year,
        task.updatedAt.month,
        task.updatedAt.day,
      ),
      assigneeId: task.assigneeId,
      dueAt: task.dueAt,
      attachmentUrls: Object.hashAll(task.attachmentUrls),
    );
  }

  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final DateTime updatedDay;
  final String? assigneeId;
  final DateTime? dueAt;
  final int attachmentUrls;

  @override
  bool operator ==(Object other) {
    return other is _TaskCardSignature &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.status == status &&
        other.priority == priority &&
        other.updatedDay == updatedDay &&
        other.assigneeId == assigneeId &&
        other.dueAt == dueAt &&
        other.attachmentUrls == attachmentUrls;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      description,
      status,
      priority,
      updatedDay,
      assigneeId,
      dueAt,
      attachmentUrls,
    );
  }
}
