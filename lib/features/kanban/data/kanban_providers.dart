import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show FutureProvider, Provider, StateProvider, StreamProvider, WidgetRef;
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

final tasksForStatusProvider = StreamProvider.autoDispose
    .family<List<KanbanTask>, TasksForStatusRequest>((ref, request) {
      return ref
          .watch(kanbanRepositoryProvider)
          .watchTasks(request.boardId)
          .map(
            (tasks) =>
                tasks.where((task) => task.status == request.status).toList()
                  ..sort(TaskPriority.compareTasks),
          );
    });

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

  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return false;
  }

  final members = await ref.watch(boardMembersProvider(boardId).future);
  for (final member in members) {
    if (member.userId == user.id) {
      return member.canEdit;
    }
  }
  return false;
});

final boardAccessProvider = FutureProvider.autoDispose
    .family<KanbanBoardMember?, String>((ref, boardId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) {
        return null;
      }

      if (boardId == demoBoardId) {
        return KanbanBoardMember(
          userId: user.id,
          email: user.email ?? 'Signed-in user',
          username: null,
          displayName: user.email ?? 'Signed-in user',
          avatarUrl: null,
          role: 'owner',
          createdAt: DateTime.now(),
          isOwner: true,
        );
      }

      final members = await ref.watch(boardMembersProvider(boardId).future);
      for (final member in members) {
        if (member.userId == user.id) {
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
  ref.invalidate(tasksForStatusProvider);
  ref.invalidate(boardMembersProvider(boardId));
  ref.invalidate(boardInvitesProvider(boardId));
  ref.invalidate(boardActivityProvider(boardId));
  ref.invalidate(boardMessagesProvider(boardId));
  ref.invalidate(boardMessageReactionsProvider(boardId));
  ref.invalidate(notificationsProvider);
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
