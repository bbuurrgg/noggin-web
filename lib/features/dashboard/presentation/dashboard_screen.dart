import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/friendly_error_message.dart';
import '../../ai_control/presentation/ai_command_sheet.dart';
import '../../auth/data/auth_providers.dart';
import '../../drive_links/data/drive_link_providers.dart';
import '../../drive_links/data/google_drive_url_parser.dart';
import '../../drive_links/presentation/drive_link_preview_block.dart';
import '../../kanban/data/kanban_providers.dart';
import '../../kanban/domain/kanban_task.dart';
import '../../kanban/presentation/kanban_board.dart';
import '../../kanban/presentation/mention_autocomplete_text_field.dart';
import '../../kanban/presentation/task_editor_sheet.dart';
import '../../settings/presentation/settings_screen.dart';

enum _DashboardView { home, board }

const bool _showDueSoonDashboardMetric = false;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _chatPanelOpen = false;
  bool _workspaceDrawerOpen = false;
  bool _workspaceDrawerExpandedContent = false;
  _DashboardView _view = _DashboardView.home;

  @override
  Widget build(BuildContext context) {
    final selectedBoardId = ref.watch(selectedBoardIdProvider);
    final boardsValue = ref.watch(allBoardsProvider);
    final pendingInvites = ref.watch(pendingBoardInvitesProvider).value ?? [];
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final canEditSelectedBoard =
        ref.watch(canEditBoardProvider(selectedBoardId)).value ?? false;
    final isWideLayout = MediaQuery.sizeOf(context).width >= 900;
    final showSideChat =
        isWideLayout && _chatPanelOpen && selectedBoardId != demoBoardId;
    final sideChatWidth =
        isWideLayout && MediaQuery.sizeOf(context).width >= 1200
            ? 420.0
            : 360.0;
    final isDashboardBoard = selectedBoardId == demoBoardId;

    final currentBoard = boardsValue.maybeWhen(
      data: (boards) {
        if (boards.isEmpty) return null;
        return boards.firstWhere(
          (p) => p.id == selectedBoardId,
          orElse:
              () => boards.firstWhere(
                (p) => p.id == demoBoardId,
                orElse: () => boards.first,
              ),
        );
      },
      orElse: () => null,
    );
    final workspaceTitle =
        isDashboardBoard ? 'Dashboard' : currentBoard?.name ?? 'Board';
    final topBar = Builder(
      builder:
          (context) => _WorkspaceTopBar(
            title: workspaceTitle,
            drawerOpen: isWideLayout && _workspaceDrawerOpen,
            onToggleDrawer: () {
              if (isWideLayout) {
                if (_workspaceDrawerOpen) {
                  setState(() {
                    _workspaceDrawerExpandedContent = false;
                    _workspaceDrawerOpen = false;
                  });
                } else {
                  setState(() => _workspaceDrawerOpen = true);
                  Future<void>.delayed(const Duration(milliseconds: 150), () {
                    if (!mounted || !_workspaceDrawerOpen) return;
                    setState(() => _workspaceDrawerExpandedContent = true);
                  });
                }
                return;
              }

              Scaffold.of(context).openDrawer();
            },
            actions: [
              if (!isDashboardBoard) _PresenceAction(boardId: selectedBoardId),
              if (!isDashboardBoard)
                IconButton(
                  tooltip: showSideChat ? 'Close board chat' : 'Board chat',
                  icon: Icon(
                    Icons.forum_rounded,
                    color:
                        showSideChat
                            ? Theme.of(context).colorScheme.primary
                            : null,
                  ),
                  onPressed: () {
                    if (isWideLayout) {
                      setState(() => _chatPanelOpen = !_chatPanelOpen);
                      return;
                    }

                    _showChat(context, selectedBoardId);
                  },
                ),
              _NotificationsAction(
                onOpenChat: (boardId) => _showChat(context, boardId),
                onOpenTask:
                    (boardId, task) => _showTask(context, boardId, task),
                onOpenInvites: () => _showPendingInvites(context),
              ),
              if (!isDashboardBoard)
                IconButton(
                  tooltip: 'Activity',
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () => _showActivity(context, selectedBoardId),
                ),
              if (!isDashboardBoard && canEditSelectedBoard)
                IconButton(
                  tooltip: 'Add task',
                  icon: const Icon(Icons.add_task_rounded),
                  onPressed: () => _showAddTask(context, selectedBoardId),
                ),
            ],
          ),
    );

    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer:
          isWideLayout
              ? null
              : Drawer(
                child: _WorkspaceDrawerContent(
                  boardsValue: boardsValue,
                  pendingInvites: pendingInvites,
                  selectedBoardId: selectedBoardId,
                  profile: profile,
                  userEmail: user?.email,
                  onSelectBoard: (boardId) {
                    ref.read(selectedBoardIdProvider.notifier).state = boardId;
                    Navigator.pop(context);
                  },
                  onRenameBoard:
                      (board) => _showRenameBoard(context, ref, board),
                  onCollaborators:
                      (board) => _showCollaborators(context, board),
                  onLeaveBoard: (board) => _showLeaveBoard(context, ref, board),
                  onDeleteBoard:
                      (board) => _showDeleteBoard(context, ref, board),
                  onAddBoard: () => _showAddBoard(context, ref),
                  onAddTask: () {
                    Navigator.pop(context);
                    _showAddTask(context, selectedBoardId);
                  },
                  onPendingInvites: () {
                    Navigator.pop(context);
                    _showPendingInvites(context);
                  },
                  onSettings: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  onSignOut: () async {
                    Navigator.pop(context);
                    await ref.read(supabaseClientProvider).auth.signOut();
                  },
                  canEditSelectedBoard: canEditSelectedBoard,
                ),
              ),
      body: boardsValue.when(
        loading: () => const _DashboardLoading(),
        error:
            (error, _) => _DashboardError(
              message: friendlyErrorMessage(
                error,
                fallback: 'Could not load your workspace.',
              ),
            ),
        data: (boards) {
          if (boards.length == 1 && boards.first.id == demoBoardId) {
            return _EmptyBoardState(
              onCreateBoard: () => _showAddBoard(context, ref),
            );
          }

          final tasksValue = ref.watch(boardTasksProvider(selectedBoardId));
          final board = CustomScrollView(
            slivers: [
              // Hiding the stats overview cards for now as requested
              // SliverToBoxAdapter(child: _BentoOverview()),
              SliverFillRemaining(
                hasScrollBody: true,
                child: KanbanBoardView(
                  boardId: selectedBoardId,
                  canEdit: canEditSelectedBoard,
                ),
              ),
            ],
          );
          final home = tasksValue.when(
            loading: () => const _DashboardLoading(),
            error:
                (error, _) => _DashboardError(
                  message: friendlyErrorMessage(
                    error,
                    fallback: 'Could not load your dashboard.',
                  ),
                ),
            data:
                (tasks) => _FocusedDashboardHome(
                  boards: boards,
                  selectedBoard: currentBoard,
                  selectedBoardId: selectedBoardId,
                  tasks: tasks,
                  currentUserId: user?.id,
                  displayName:
                      profile?.displayName.isNotEmpty == true
                          ? profile!.displayName
                          : user?.email?.split('@').first,
                  canEditBoard: canEditSelectedBoard,
                  view: _view,
                  onViewChanged: (view) => setState(() => _view = view),
                  onAddTask: () => _showAddTask(context, selectedBoardId),
                  onOpenTask: (task) => _showTask(context, task.boardId, task),
                  onOpenChat:
                      selectedBoardId == demoBoardId
                          ? null
                          : () => _showChat(context, selectedBoardId),
                  onOpenActivity:
                      selectedBoardId == demoBoardId
                          ? null
                          : () => _showActivity(context, selectedBoardId),
                ),
          );
          final effectiveView = isDashboardBoard ? _view : _DashboardView.board;
          final content =
              effectiveView == _DashboardView.home
                  ? home
                  : Column(
                    children: [
                      if (isDashboardBoard)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _DashboardViewSwitcher(
                              view: effectiveView,
                              onChanged: (view) => setState(() => _view = view),
                            ),
                          ),
                        ),
                      Expanded(child: board),
                    ],
                  );

          final mainContent =
              showSideChat
                  ? Row(
                    children: [
                      Expanded(child: content),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                        ),
                        child: SizedBox(
                          width: sideChatWidth,
                          child: _BoardChatSheet(
                            boardId: selectedBoardId,
                            fillAvailable: true,
                            onClose:
                                () => setState(() => _chatPanelOpen = false),
                          ),
                        ),
                      ),
                    ],
                  )
                  : content;

          if (!isWideLayout) {
            return SafeArea(
              child: Column(
                children: [
                  topBar,
                  Expanded(
                    child: _DashboardWorkspaceSurface(child: mainContent),
                  ),
                ],
              ),
            );
          }

          return Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _workspaceDrawerOpen ? 1 : 0),
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  final drawerWidth = 64 + ((280 - 64) * value);
                  return SizedBox(
                    width: drawerWidth,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: drawerWidth,
                        maxWidth: drawerWidth,
                        child: child,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: _workspaceDrawerExpandedContent ? 280 : 64,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: _WorkspaceDrawerContent(
                      boardsValue: boardsValue,
                      pendingInvites: pendingInvites,
                      selectedBoardId: selectedBoardId,
                      profile: profile,
                      userEmail: user?.email,
                      onSelectBoard:
                          (boardId) =>
                              ref.read(selectedBoardIdProvider.notifier).state =
                                  boardId,
                      onRenameBoard:
                          (board) => _showRenameBoard(context, ref, board),
                      onCollaborators:
                          (board) => _showCollaborators(context, board),
                      onLeaveBoard:
                          (board) => _showLeaveBoard(context, ref, board),
                      onDeleteBoard:
                          (board) => _showDeleteBoard(context, ref, board),
                      onAddBoard: () => _showAddBoard(context, ref),
                      onAddTask: () => _showAddTask(context, selectedBoardId),
                      onPendingInvites: () => _showPendingInvites(context),
                      onSettings:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                      onSignOut:
                          () async =>
                              ref.read(supabaseClientProvider).auth.signOut(),
                      compact: !_workspaceDrawerExpandedContent,
                      canEditSelectedBoard: canEditSelectedBoard,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  child: Column(
                    children: [
                      topBar,
                      Expanded(
                        child: _DashboardWorkspaceSurface(child: mainContent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(right: showSideChat ? sideChatWidth : 0),
        child: PopupMenuButton<int>(
          offset: const Offset(0, -128),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          onSelected: (value) {
            if (value == 1) _showAddTask(context, selectedBoardId);
            if (value == 2) _showGemini(context, selectedBoardId);
          },
          itemBuilder:
              (context) => [
                if (selectedBoardId != demoBoardId && canEditSelectedBoard)
                  PopupMenuItem(
                    value: 1,
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_task_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Text('Add Task'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 2,
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 12),
                      const Text('AI Assistant'),
                    ],
                  ),
                ),
              ],
          child: const FloatingActionButton(
            onPressed: null,
            child: Icon(Icons.auto_awesome_rounded),
          ),
        ),
      ),
    );
  }

  void _showGemini(BuildContext context, String boardId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => AiCommandSheet(boardId: boardId),
    );
  }

  void _showChat(BuildContext context, String boardId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _BoardChatSheet(boardId: boardId),
    );
  }

  void _showTask(BuildContext context, String boardId, KanbanTask task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder:
          (_) => TaskEditorSheet(
            boardId: boardId,
            initialStatus: task.status,
            task: task,
          ),
    );
  }

  void _showCollaborators(BuildContext context, KanbanBoard board) {
    showDialog<void>(
      context: context,
      builder: (_) => _CollaboratorsDialog(board: board),
    );
  }

  void _showActivity(BuildContext context, String boardId) {
    showDialog<void>(
      context: context,
      builder: (_) => _ActivityDialog(boardId: boardId),
    );
  }

  void _showPendingInvites(BuildContext context) {
    ref
        .read(kanbanRepositoryProvider)
        .markNotificationsRead(notificationType: 'invite');
    ref.invalidate(notificationsProvider);
    showDialog<void>(
      context: context,
      builder: (_) => const _PendingInvitesDialog(),
    );
  }

  void _showAddTask(BuildContext context, String boardId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => TaskEditorSheet(boardId: boardId, initialStatus: 'To Do'),
    );
  }

  void _showRenameBoard(
    BuildContext context,
    WidgetRef ref,
    KanbanBoard board,
  ) {
    final controller = TextEditingController(text: board.name);
    var boardType = board.boardType;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: board.name.length,
    );

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Board Settings'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Board name',
                        ),
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted:
                            (_) => _renameBoard(
                              context,
                              ref,
                              board,
                              controller.text,
                              boardType,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _BoardTypeSelector(
                        value: boardType,
                        onChanged:
                            (value) => setDialogState(() => boardType = value),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed:
                          () => _renameBoard(
                            context,
                            ref,
                            board,
                            controller.text,
                            boardType,
                          ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _renameBoard(
    BuildContext context,
    WidgetRef ref,
    KanbanBoard board,
    String name,
    String boardType,
  ) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty ||
        (trimmedName == board.name && boardType == board.boardType)) {
      Navigator.pop(context);
      return;
    }

    try {
      await ref
          .read(kanbanRepositoryProvider)
          .renameBoard(
            boardId: board.id,
            name: trimmedName,
            boardType: boardType,
          );
      invalidateKanban(ref, boardId: board.id);

      if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detailedErrorMessage(error, fallback: 'Could not rename board.'),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _showDeleteBoard(
    BuildContext context,
    WidgetRef ref,
    KanbanBoard board,
  ) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete Board'),
            content: Text(
              'Are you sure you want to delete "${board.name}"? This will also remove all its tasks.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final selectedId = ref.read(selectedBoardIdProvider);
                    await ref
                        .read(kanbanRepositoryProvider)
                        .deleteBoard(board.id);
                    invalidateKanban(ref, boardId: board.id);

                    if (selectedId == board.id) {
                      ref.read(selectedBoardIdProvider.notifier).state =
                          demoBoardId;
                    }

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (context.mounted &&
                        (Scaffold.maybeOf(context)?.isDrawerOpen ?? false)) {
                      Navigator.pop(context);
                    }
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('Deleted "${board.name}".')),
                    );
                  } catch (error) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          detailedErrorMessage(
                            error,
                            fallback: 'Could not delete this board.',
                          ),
                        ),
                      ),
                    );
                  }
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  void _showLeaveBoard(BuildContext context, WidgetRef ref, KanbanBoard board) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave Board'),
            content: Text(
              'Leave "${board.name}"? You will lose access until the owner invites you again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final selectedId = ref.read(selectedBoardIdProvider);
                    await ref
                        .read(kanbanRepositoryProvider)
                        .leaveBoard(board.id);
                    invalidateKanban(ref, boardId: board.id);

                    if (selectedId == board.id) {
                      ref.read(selectedBoardIdProvider.notifier).state =
                          demoBoardId;
                    }

                    if (context.mounted) Navigator.pop(context);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            detailedErrorMessage(
                              error,
                              fallback: 'Could not leave board.',
                            ),
                          ),
                          backgroundColor: Colors.red.shade700,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Leave', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  void _showAddBoard(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    var boardType = 'project';
    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('New Board'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Board name',
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 16),
                      _BoardTypeSelector(
                        value: boardType,
                        onChanged:
                            (value) => setDialogState(() => boardType = value),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final name = controller.text.trim();
                        if (name.isNotEmpty) {
                          try {
                            final boardId = await ref
                                .read(kanbanRepositoryProvider)
                                .createBoard(name: name, boardType: boardType);
                            ref.read(selectedBoardIdProvider.notifier).state =
                                boardId;
                            invalidateKanban(ref, boardId: boardId);
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    detailedErrorMessage(
                                      error,
                                      fallback: 'Could not create board.',
                                    ),
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          }
                        }
                      },
                      child: const Text('Create'),
                    ),
                  ],
                ),
          ),
    );
  }
}

class _WorkspaceTopBar extends StatelessWidget {
  const _WorkspaceTopBar({
    required this.title,
    required this.drawerOpen,
    required this.onToggleDrawer,
    required this.actions,
  });

  final String title;
  final bool drawerOpen;
  final VoidCallback onToggleDrawer;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: drawerOpen ? 'Hide boards' : 'Show boards',
              icon: Icon(
                drawerOpen
                    ? Icons.keyboard_double_arrow_left_rounded
                    : Icons.menu_rounded,
              ),
              onPressed: onToggleDrawer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ...actions,
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _BoardTypeSelector extends StatelessWidget {
  const _BoardTypeSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment<String>(
          value: 'project',
          icon: Icon(Icons.account_tree_rounded),
          label: Text('Project'),
        ),
        ButtonSegment<String>(
          value: 'list',
          icon: Icon(Icons.list_alt_rounded),
          label: Text('List'),
        ),
      ],
      selected: {value == 'list' ? 'list' : 'project'},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _WorkspaceDrawerContent extends StatefulWidget {
  const _WorkspaceDrawerContent({
    required this.boardsValue,
    required this.pendingInvites,
    required this.selectedBoardId,
    required this.profile,
    required this.userEmail,
    required this.onSelectBoard,
    required this.onRenameBoard,
    required this.onCollaborators,
    required this.onLeaveBoard,
    required this.onDeleteBoard,
    required this.onAddBoard,
    required this.onAddTask,
    required this.onPendingInvites,
    required this.onSettings,
    required this.onSignOut,
    required this.canEditSelectedBoard,
    this.compact = false,
  });

  final AsyncValue<List<KanbanBoard>> boardsValue;
  final List<KanbanPendingBoardInvite> pendingInvites;
  final String selectedBoardId;
  final UserProfile? profile;
  final String? userEmail;
  final ValueChanged<String> onSelectBoard;
  final ValueChanged<KanbanBoard> onRenameBoard;
  final ValueChanged<KanbanBoard> onCollaborators;
  final ValueChanged<KanbanBoard> onLeaveBoard;
  final ValueChanged<KanbanBoard> onDeleteBoard;
  final VoidCallback onAddBoard;
  final VoidCallback onAddTask;
  final VoidCallback onPendingInvites;
  final VoidCallback onSettings;
  final Future<void> Function() onSignOut;
  final bool canEditSelectedBoard;
  final bool compact;

  @override
  State<_WorkspaceDrawerContent> createState() =>
      _WorkspaceDrawerContentState();
}

class _WorkspaceDrawerContentState extends State<_WorkspaceDrawerContent> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.profile?.avatarUrl;
    if (widget.compact) {
      return _WorkspaceRailContent(
        boardsValue: widget.boardsValue,
        pendingInvites: widget.pendingInvites,
        selectedBoardId: widget.selectedBoardId,
        avatarUrl: avatarUrl,
        onSelectBoard: widget.onSelectBoard,
        onAddBoard: widget.onAddBoard,
        onPendingInvites: widget.onPendingInvites,
        onSettings: widget.onSettings,
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Image.asset('images/logo_256.png', height: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Noggin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFC53627),
                    ),
                  ),
                ),
                if (widget.pendingInvites.isNotEmpty)
                  _DrawerIconButton(
                    tooltip: 'Pending invites',
                    icon: Icons.mark_email_unread_rounded,
                    badge: widget.pendingInvites.length,
                    onPressed: widget.onPendingInvites,
                  ),
                _DrawerIconButton(
                  tooltip: 'New board',
                  icon: Icons.add_rounded,
                  onPressed: widget.onAddBoard,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search boards',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon:
                      _query.isEmpty
                          ? null
                          : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          _SelectedBoardActionCard(
            boardsValue: widget.boardsValue,
            selectedBoardId: widget.selectedBoardId,
            canEditSelectedBoard: widget.canEditSelectedBoard,
            onAddTask: widget.onAddTask,
            onRenameBoard: widget.onRenameBoard,
          ),
          Expanded(
            child: widget.boardsValue.when(
              data: (boards) {
                if (boards.isEmpty) return const SizedBox();

                final dashboardBoards =
                    boards
                        .where((board) => board.id == demoBoardId)
                        .where(_matchesSearch)
                        .toList();
                final projectBoards =
                    boards
                        .where(
                          (board) => board.id != demoBoardId && board.isProject,
                        )
                        .where(_matchesSearch)
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));
                final listBoards =
                    boards
                        .where(
                          (board) => board.id != demoBoardId && board.isList,
                        )
                        .where(_matchesSearch)
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));
                final hasSearchResults =
                    dashboardBoards.isNotEmpty ||
                    projectBoards.isNotEmpty ||
                    listBoards.isNotEmpty;

                if (!hasSearchResults) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'No boards found',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [
                    for (final board in dashboardBoards)
                      _BoardListTile(
                        board: board,
                        selected: board.id == widget.selectedBoardId,
                        onSelect: () => widget.onSelectBoard(board.id),
                        onRename: () => widget.onRenameBoard(board),
                        onCollaborators: () => widget.onCollaborators(board),
                        onLeave: () => widget.onLeaveBoard(board),
                        onDelete: () => widget.onDeleteBoard(board),
                      ),
                    if (projectBoards.isNotEmpty) ...[
                      _DrawerSectionHeader(
                        title: 'Projects',
                        count: projectBoards.length,
                      ),
                      for (final board in projectBoards)
                        _BoardListTile(
                          board: board,
                          selected: board.id == widget.selectedBoardId,
                          onSelect: () => widget.onSelectBoard(board.id),
                          onRename: () => widget.onRenameBoard(board),
                          onCollaborators: () => widget.onCollaborators(board),
                          onLeave: () => widget.onLeaveBoard(board),
                          onDelete: () => widget.onDeleteBoard(board),
                        ),
                    ],
                    if (listBoards.isNotEmpty) ...[
                      _DrawerSectionHeader(
                        title: 'Lists',
                        count: listBoards.length,
                      ),
                      for (final board in listBoards)
                        _BoardListTile(
                          board: board,
                          selected: board.id == widget.selectedBoardId,
                          onSelect: () => widget.onSelectBoard(board.id),
                          onRename: () => widget.onRenameBoard(board),
                          onCollaborators: () => widget.onCollaborators(board),
                          onLeave: () => widget.onLeaveBoard(board),
                          onDelete: () => widget.onDeleteBoard(board),
                        ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (error, _) => Center(
                    child: Text(
                      friendlyErrorMessage(
                        error,
                        fallback: 'Could not load boards.',
                      ),
                    ),
                  ),
            ),
          ),
          const Divider(height: 1),
          _DrawerAccountFooter(
            avatarUrl: avatarUrl,
            title:
                widget.profile?.displayName.trim().isNotEmpty == true
                    ? widget.profile!.displayName
                    : widget.userEmail ?? 'Signed in',
            subtitle:
                widget.profile?.username.trim().isNotEmpty == true
                    ? '@${widget.profile!.username}'
                    : widget.userEmail ?? 'Noggin account',
            onSettings: widget.onSettings,
            onSignOut: widget.onSignOut,
          ),
        ],
      ),
    );
  }

  bool _matchesSearch(KanbanBoard board) {
    if (_query.isEmpty) return true;
    return board.name.toLowerCase().contains(_query.toLowerCase());
  }
}

class _WorkspaceRailContent extends StatelessWidget {
  const _WorkspaceRailContent({
    required this.boardsValue,
    required this.pendingInvites,
    required this.selectedBoardId,
    required this.avatarUrl,
    required this.onSelectBoard,
    required this.onAddBoard,
    required this.onPendingInvites,
    required this.onSettings,
  });

  final AsyncValue<List<KanbanBoard>> boardsValue;
  final List<KanbanPendingBoardInvite> pendingInvites;
  final String selectedBoardId;
  final String? avatarUrl;
  final ValueChanged<String> onSelectBoard;
  final VoidCallback onAddBoard;
  final VoidCallback onPendingInvites;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 10),
          Image.asset('images/logo_256.png', height: 28),
          const SizedBox(height: 10),
          _RailIconButton(
            tooltip: 'New board',
            icon: Icons.add_rounded,
            onPressed: onAddBoard,
          ),
          if (pendingInvites.isNotEmpty)
            _RailIconButton(
              tooltip: 'Pending invites',
              icon: Icons.mark_email_unread_rounded,
              badge: pendingInvites.length,
              onPressed: onPendingInvites,
            ),
          const Divider(height: 18),
          Expanded(
            child: boardsValue.when(
              data: (boards) {
                final dashboardBoards =
                    boards.where((board) => board.id == demoBoardId).toList();
                final projectBoards =
                    boards
                        .where(
                          (board) => board.id != demoBoardId && board.isProject,
                        )
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));
                final listBoards =
                    boards
                        .where(
                          (board) => board.id != demoBoardId && board.isList,
                        )
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  children: [
                    for (final board in dashboardBoards)
                      _BoardRailButton(
                        board: board,
                        selected: board.id == selectedBoardId,
                        onPressed: () => onSelectBoard(board.id),
                      ),
                    if (projectBoards.isNotEmpty)
                      const _RailGroupDivider(tooltip: 'Projects'),
                    for (final board in projectBoards)
                      _BoardRailButton(
                        board: board,
                        selected: board.id == selectedBoardId,
                        onPressed: () => onSelectBoard(board.id),
                      ),
                    if (listBoards.isNotEmpty)
                      const _RailGroupDivider(tooltip: 'Lists'),
                    for (final board in listBoards)
                      _BoardRailButton(
                        board: board,
                        selected: board.id == selectedBoardId,
                        onPressed: () => onSelectBoard(board.id),
                      ),
                  ],
                );
              },
              loading:
                  () => const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              error:
                  (_, _) => const Center(
                    child: Icon(Icons.error_outline_rounded, size: 20),
                  ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Tooltip(
              message: 'Settings',
              child: IconButton(
                onPressed: onSettings,
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      avatarUrl == null || avatarUrl!.isEmpty
                          ? null
                          : NetworkImage(avatarUrl!),
                  child:
                      avatarUrl == null || avatarUrl!.isEmpty
                          ? const Icon(Icons.person_outline_rounded, size: 18)
                          : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardRailButton extends StatelessWidget {
  const _BoardRailButton({
    required this.board,
    required this.selected,
    required this.onPressed,
  });

  final KanbanBoard board;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: board.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 42,
            decoration: BoxDecoration(
              color:
                  selected ? colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              board.id == demoBoardId
                  ? Icons.apps_rounded
                  : board.isList
                  ? Icons.list_alt_rounded
                  : Icons.account_tree_rounded,
              color:
                  selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailGroupDivider extends StatelessWidget {
  const _RailGroupDivider({required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _DrawerSectionHeader extends StatelessWidget {
  const _DrawerSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerIconButton extends StatelessWidget {
  const _DrawerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(icon),
            onPressed: onPressed,
          ),
          if (badge != null)
            Positioned(
              right: 4,
              top: 4,
              child: _NotificationDot(count: badge!),
            ),
        ],
      ),
    );
  }
}

class _SelectedBoardActionCard extends StatelessWidget {
  const _SelectedBoardActionCard({
    required this.boardsValue,
    required this.selectedBoardId,
    required this.canEditSelectedBoard,
    required this.onAddTask,
    required this.onRenameBoard,
  });

  final AsyncValue<List<KanbanBoard>> boardsValue;
  final String selectedBoardId;
  final bool canEditSelectedBoard;
  final VoidCallback onAddTask;
  final ValueChanged<KanbanBoard> onRenameBoard;

  @override
  Widget build(BuildContext context) {
    final selectedBoard = boardsValue.maybeWhen(
      data:
          (boards) => boards.cast<KanbanBoard?>().firstWhere(
            (board) => board?.id == selectedBoardId,
            orElse: () => null,
          ),
      orElse: () => null,
    );
    if (selectedBoard == null ||
        selectedBoard.id == demoBoardId ||
        !canEditSelectedBoard) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isList = selectedBoard.isList;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                isList ? Icons.list_alt_rounded : Icons.account_tree_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedBoard.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Add task',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_task_rounded, size: 20),
                onPressed: onAddTask,
              ),
              IconButton(
                tooltip: 'Rename',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_rounded, size: 20),
                onPressed: () => onRenameBoard(selectedBoard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(icon: Icon(icon), onPressed: onPressed),
          if (badge != null)
            Positioned(
              right: 7,
              top: 7,
              child: _NotificationDot(count: badge!),
            ),
        ],
      ),
    );
  }
}

class _NotificationDot extends StatelessWidget {
  const _NotificationDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onError,
          fontWeight: FontWeight.w800,
          fontSize: 9,
        ),
      ),
    );
  }
}

class _DrawerAccountFooter extends StatelessWidget {
  const _DrawerAccountFooter({
    required this.avatarUrl,
    required this.title,
    required this.subtitle,
    required this.onSettings,
    required this.onSignOut,
  });

  final String? avatarUrl;
  final String title;
  final String subtitle;
  final VoidCallback onSettings;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onSettings,
            child: CircleAvatar(
              radius: 17,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage:
                  avatarUrl == null || avatarUrl!.isEmpty
                      ? null
                      : NetworkImage(avatarUrl!),
              child:
                  avatarUrl == null || avatarUrl!.isEmpty
                      ? const Icon(Icons.person_outline_rounded, size: 19)
                      : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onSettings,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.settings_rounded, size: 20),
            onPressed: onSettings,
          ),
          PopupMenuButton<String>(
            tooltip: 'Account actions',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (value) {
              if (value == 'sign-out') onSignOut();
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(
                    value: 'sign-out',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Sign out'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
    );
  }
}

class _FocusedDashboardHome extends StatelessWidget {
  const _FocusedDashboardHome({
    required this.boards,
    required this.selectedBoard,
    required this.selectedBoardId,
    required this.tasks,
    required this.currentUserId,
    required this.displayName,
    required this.canEditBoard,
    required this.view,
    required this.onViewChanged,
    required this.onAddTask,
    required this.onOpenTask,
    this.onOpenChat,
    this.onOpenActivity,
  });

  final List<KanbanBoard> boards;
  final KanbanBoard? selectedBoard;
  final String selectedBoardId;
  final List<KanbanTask> tasks;
  final String? currentUserId;
  final String? displayName;
  final bool canEditBoard;
  final _DashboardView view;
  final ValueChanged<_DashboardView> onViewChanged;
  final VoidCallback onAddTask;
  final ValueChanged<KanbanTask> onOpenTask;
  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextWeek = today.add(const Duration(days: 7));
    final projectBoardIds =
        boards
            .where((board) => board.id != demoBoardId && board.isProject)
            .map((board) => board.id)
            .toSet();
    final dashboardTasks =
        selectedBoardId == demoBoardId
            ? tasks
                .where((task) => projectBoardIds.contains(task.boardId))
                .toList()
            : tasks;
    final activeTasks = dashboardTasks.where((task) => !_isDone(task)).toList();
    final myTasks =
        activeTasks
            .where(
              (task) =>
                  task.assigneeId != null && task.assigneeId == currentUserId,
            )
            .toList()
          ..sort(_taskPrioritySort);
    final overdue =
        activeTasks
            .where(
              (task) =>
                  task.dueAt != null && _dateOnly(task.dueAt!).isBefore(today),
            )
            .toList()
          ..sort(_taskPrioritySort);
    final dueSoon =
        activeTasks.where((task) {
            final dueAt = task.dueAt;
            if (dueAt == null) return false;
            final dueDate = _dateOnly(dueAt);
            return !dueDate.isBefore(today) && !dueDate.isAfter(nextWeek);
          }).toList()
          ..sort(_taskPrioritySort);
    final staleCutoff = now.subtract(const Duration(days: 7));
    final staleTasks =
        activeTasks
            .where((task) => task.updatedAt.isBefore(staleCutoff))
            .toList()
          ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final needsDetails =
        activeTasks
            .where((task) => task.assigneeId == null || task.dueAt == null)
            .toList()
          ..sort(_taskPrioritySort);
    final upcomingDeadlines =
        activeTasks.where((task) => task.dueAt != null).toList()
          ..sort(_taskPrioritySort);
    final recent = [...dashboardTasks]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final boardName = selectedBoard?.name ?? 'Dashboard';
    final boardNames = {for (final board in boards) board.id: board.name};
    final focusTasks =
        [
          ...overdue,
          ...dueSoon.where(
            (task) => !overdue.any((item) => item.id == task.id),
          ),
          ...myTasks.where(
            (task) =>
                !overdue.any((item) => item.id == task.id) &&
                !dueSoon.any((item) => item.id == task.id),
          ),
        ].take(4).toList();

    final myWorkSection = _DashboardTaskSection(
      title: 'My Work',
      emptyText: 'No active tasks assigned to you.',
      tasks: myTasks.take(5).toList(),
      boardNames: boardNames,
      showBoardName: selectedBoardId == demoBoardId,
      onOpenTask: onOpenTask,
      minHeight: 176,
    );
    final urgentSection = _DashboardTaskSection(
      title: overdue.isEmpty ? 'Due Soon' : 'Overdue',
      emptyText:
          overdue.isEmpty
              ? 'Nothing due in the next 7 days.'
              : 'No overdue tasks. Nice.',
      tasks: (overdue.isEmpty ? dueSoon : overdue).take(5).toList(),
      boardNames: boardNames,
      showBoardName: selectedBoardId == demoBoardId,
      highlightOverdue: overdue.isNotEmpty,
      onOpenTask: onOpenTask,
      minHeight: 176,
    );
    final recentSection = _DashboardTaskSection(
      title: 'Recently Updated',
      emptyText: 'No tasks yet.',
      tasks: recent.take(6).toList(),
      boardNames: boardNames,
      showBoardName: selectedBoardId == demoBoardId,
      onOpenTask: onOpenTask,
      minHeight: 362,
    );
    final staleSection = _DashboardTaskSection(
      title: 'Stale Tasks',
      emptyText: 'Nothing has gone quiet for 7+ days.',
      tasks: staleTasks.take(5).toList(),
      boardNames: boardNames,
      showBoardName: selectedBoardId == demoBoardId,
      onOpenTask: onOpenTask,
      minHeight: 176,
    );
    final needsDetailsSection = _DashboardTaskSection(
      title: 'Needs Details',
      emptyText: 'All active tasks have an assignee and due date.',
      tasks: needsDetails.take(5).toList(),
      boardNames: boardNames,
      showBoardName: selectedBoardId == demoBoardId,
      onOpenTask: onOpenTask,
      minHeight: 176,
    );
    final upcomingDeadlinesSection = _UpcomingDeadlinesCard(
      tasks: upcomingDeadlines.take(6).toList(),
      boardNames: boardNames,
      showBoardName: selectedBoardId == demoBoardId,
      onOpenTask: onOpenTask,
    );
    final stayOnTrackSection = _StayOnTrackCard(tasks: dashboardTasks);
    final calendarSection = _DashboardCalendarCard(tasks: dashboardTasks);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_timeGreeting(DateTime.now())}, ${_displayFirstName(displayName)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selectedBoardId == demoBoardId
                        ? 'Here is what needs attention across every board.'
                        : 'Here is what needs attention in $boardName.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _DashboardViewSwitcher(view: view, onChanged: onViewChanged),
          ],
        ),
        const SizedBox(height: 14),
        _DashboardMetricStrip(
          metrics: [
            _DashboardMetricData(
              icon: Icons.assignment_ind_rounded,
              label: 'Mine',
              value: '${myTasks.length}',
              color: Theme.of(context).colorScheme.primary,
            ),
            _DashboardMetricData(
              icon: Icons.warning_amber_rounded,
              label: 'Overdue',
              value: '${overdue.length}',
              color: Colors.red.shade700,
            ),
            if (_showDueSoonDashboardMetric)
              _DashboardMetricData(
                icon: Icons.event_available_rounded,
                label: 'Due Soon',
                value: '${dueSoon.length}',
                color: Colors.orange.shade800,
              ),
            _DashboardMetricData(
              icon: Icons.task_alt_rounded,
              label: 'Active',
              value: '${activeTasks.length}',
              color: Colors.green.shade700,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (canEditBoard && selectedBoardId != demoBoardId)
              FilledButton.icon(
                onPressed: onAddTask,
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('New Task'),
              ),
            if (onOpenChat != null)
              TextButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.forum_rounded),
                label: const Text('Board Chat'),
              ),
            if (onOpenActivity != null)
              TextButton.icon(
                onPressed: onOpenActivity,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Activity'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 860) {
              return Column(
                children: [
                  _TodaysFocusCard(
                    tasks: focusTasks,
                    boardNames: boardNames,
                    showBoardName: selectedBoardId == demoBoardId,
                    onOpenTask: onOpenTask,
                  ),
                  const SizedBox(height: 10),
                  myWorkSection,
                  const SizedBox(height: 10),
                  urgentSection,
                  const SizedBox(height: 10),
                  upcomingDeadlinesSection,
                  const SizedBox(height: 10),
                  recentSection,
                  const SizedBox(height: 10),
                  staleSection,
                  const SizedBox(height: 10),
                  needsDetailsSection,
                  const SizedBox(height: 10),
                  stayOnTrackSection,
                  const SizedBox(height: 10),
                  calendarSection,
                ],
              );
            }
            if (constraints.maxWidth < 1160) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _TodaysFocusCard(
                          tasks: focusTasks,
                          boardNames: boardNames,
                          showBoardName: selectedBoardId == demoBoardId,
                          onOpenTask: onOpenTask,
                        ),
                        const SizedBox(height: 10),
                        myWorkSection,
                        const SizedBox(height: 10),
                        urgentSection,
                        const SizedBox(height: 10),
                        upcomingDeadlinesSection,
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        recentSection,
                        const SizedBox(height: 10),
                        staleSection,
                        const SizedBox(height: 10),
                        needsDetailsSection,
                        const SizedBox(height: 10),
                        stayOnTrackSection,
                        const SizedBox(height: 10),
                        calendarSection,
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _TodaysFocusCard(
                        tasks: focusTasks,
                        boardNames: boardNames,
                        showBoardName: selectedBoardId == demoBoardId,
                        onOpenTask: onOpenTask,
                      ),
                      const SizedBox(height: 10),
                      myWorkSection,
                      const SizedBox(height: 10),
                      urgentSection,
                      const SizedBox(height: 10),
                      upcomingDeadlinesSection,
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      recentSection,
                      const SizedBox(height: 10),
                      staleSection,
                      const SizedBox(height: 10),
                      needsDetailsSection,
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      stayOnTrackSection,
                      const SizedBox(height: 10),
                      calendarSection,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _displayFirstName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return 'there';
    }
    return trimmed.split(RegExp(r'\s+')).first;
  }

  static String _timeGreeting(DateTime now) {
    if (now.hour >= 5 && now.hour < 18) {
      return 'Good day';
    }
    return 'Good evening';
  }

  static bool _isDone(KanbanTask task) {
    final status = task.status.toLowerCase();
    return status == 'done' ||
        status == 'complete' ||
        status == 'completed' ||
        status.contains('done');
  }

  static int _taskPrioritySort(KanbanTask a, KanbanTask b) {
    final aDue = a.dueAt;
    final bDue = b.dueAt;
    if (aDue == null && bDue == null) {
      return b.updatedAt.compareTo(a.updatedAt);
    }
    if (aDue == null) return 1;
    if (bDue == null) return -1;
    return aDue.compareTo(bDue);
  }
}

class _DashboardViewSwitcher extends StatelessWidget {
  const _DashboardViewSwitcher({required this.view, required this.onChanged});

  final _DashboardView view;
  final ValueChanged<_DashboardView> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBoard = view == _DashboardView.board;

    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isBoard ? Icons.view_kanban_rounded : Icons.dashboard_rounded,
            size: 15,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            isBoard ? 'Board' : 'Home',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: 38,
            height: 28,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: isBoard,
                onChanged:
                    (value) => onChanged(
                      value ? _DashboardView.board : _DashboardView.home,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetricData {
  const _DashboardMetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _DashboardMetricStrip extends StatelessWidget {
  const _DashboardMetricStrip({required this.metrics});

  final List<_DashboardMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            if (compact) {
              return Wrap(
                runSpacing: 6,
                children:
                    metrics
                        .map(
                          (metric) => SizedBox(
                            width: constraints.maxWidth / 2,
                            child: _DashboardMetricItem(metric: metric),
                          ),
                        )
                        .toList(),
              );
            }

            return Row(
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  Expanded(child: _DashboardMetricItem(metric: metrics[index])),
                  if (index != metrics.length - 1)
                    SizedBox(
                      height: 34,
                      child: VerticalDivider(
                        width: 16,
                        thickness: 1,
                        color: colorScheme.outlineVariant,
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DashboardMetricItem extends StatelessWidget {
  const _DashboardMetricItem({required this.metric});

  final _DashboardMetricData metric;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, color: metric.color, size: 16),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.1,
                ),
                children: [
                  TextSpan(
                    text: metric.value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  TextSpan(text: '  ${metric.label}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardWorkspaceSurface extends StatelessWidget {
  const _DashboardWorkspaceSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: child,
    );
  }
}

class _DashboardTaskSection extends StatelessWidget {
  const _DashboardTaskSection({
    required this.title,
    required this.emptyText,
    required this.tasks,
    required this.boardNames,
    required this.showBoardName,
    required this.onOpenTask,
    this.highlightOverdue = false,
    this.minHeight = 176,
  });

  final String title;
  final String emptyText;
  final List<KanbanTask> tasks;
  final Map<String, String> boardNames;
  final bool showBoardName;
  final ValueChanged<KanbanTask> onOpenTask;
  final bool highlightOverdue;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              if (tasks.isEmpty)
                _DashboardEmptyState(text: emptyText)
              else
                ...tasks.map(
                  (task) => _DashboardTaskTile(
                    task: task,
                    boardName: showBoardName ? boardNames[task.boardId] : null,
                    highlightOverdue: highlightOverdue,
                    onTap: () => onOpenTask(task),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTaskTile extends StatelessWidget {
  const _DashboardTaskTile({
    required this.task,
    required this.onTap,
    this.boardName,
    this.highlightOverdue = false,
  });

  final KanbanTask task;
  final String? boardName;
  final VoidCallback onTap;
  final bool highlightOverdue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dueAt = task.dueAt;
    final dueText = dueAt == null ? null : 'Due ${_formatDate(dueAt)}';
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -3),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        Icons.radio_button_unchecked_rounded,
        size: 18,
        color: highlightOverdue ? colorScheme.error : colorScheme.primary,
      ),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (boardName != null) boardName, task.status].join(' - '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          dueText == null
              ? null
              : SizedBox(
                width: 92,
                child: Text(
                  dueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        highlightOverdue
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                    fontWeight:
                        highlightOverdue ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _StayOnTrackCard extends StatelessWidget {
  const _StayOnTrackCard({required this.tasks});

  final List<KanbanTask> tasks;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = tasks.length;
    final completed = tasks.where(_isDone).length;
    final progress = total == 0 ? 0.0 : completed / total;
    final percent = (progress * 100).round();

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 138),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stay on track',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      total == 0
                          ? 'Create your first task to start tracking progress.'
                          : progress >= 0.75
                          ? "You're doing great."
                          : 'Keep moving through the active work.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$completed of $total tasks completed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isDone(KanbanTask task) {
    final status = task.status.toLowerCase();
    return status == 'done' ||
        status == 'complete' ||
        status == 'completed' ||
        status.contains('done');
  }
}

class _DashboardCalendarCard extends StatelessWidget {
  const _DashboardCalendarCard({required this.tasks});

  final List<KanbanTask> tasks;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final today = DateTime(now.year, now.month, now.day);
    final firstVisible = monthStart.subtract(
      Duration(days: monthStart.weekday % DateTime.daysPerWeek),
    );
    final dueDays = <DateTime>{};
    final overdueDays = <DateTime>{};

    for (final task in tasks) {
      final dueAt = task.dueAt;
      if (dueAt == null || _isDone(task)) continue;
      final day = DateTime(dueAt.year, dueAt.month, dueAt.day);
      dueDays.add(day);
      if (day.isBefore(today)) {
        overdueDays.add(day);
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 278),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Calendar',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    _formatMonth(now),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children:
                    const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                        .map(
                          (day) => Expanded(
                            child: Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 8),
              ...List.generate(6, (weekIndex) {
                return Padding(
                  padding: EdgeInsets.only(top: weekIndex == 0 ? 0 : 4),
                  child: Row(
                    children: List.generate(7, (dayIndex) {
                      final date = firstVisible.add(
                        Duration(days: weekIndex * 7 + dayIndex),
                      );
                      final day = DateTime(date.year, date.month, date.day);

                      return Expanded(
                        child: _CalendarDayCell(
                          day: date.day,
                          muted: date.month != now.month,
                          selected: day == today,
                          hasDueTask: dueDays.contains(day),
                          overdue: overdueDays.contains(day),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isDone(KanbanTask task) {
    final status = task.status.toLowerCase();
    return status == 'done' ||
        status == 'complete' ||
        status == 'completed' ||
        status.contains('done');
  }

  static String _formatMonth(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.muted,
    required this.selected,
    required this.hasDueTask,
    required this.overdue,
  });

  final int day;
  final bool muted;
  final bool selected;
  final bool hasDueTask;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        selected
            ? colorScheme.onPrimary
            : muted
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
            : colorScheme.onSurface;

    return SizedBox(
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (hasDueTask)
            Positioned(
              bottom: 1,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: overdue ? colorScheme.error : colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpcomingDeadlinesCard extends StatelessWidget {
  const _UpcomingDeadlinesCard({
    required this.tasks,
    required this.boardNames,
    required this.showBoardName,
    required this.onOpenTask,
  });

  final List<KanbanTask> tasks;
  final Map<String, String> boardNames;
  final bool showBoardName;
  final ValueChanged<KanbanTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 176),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upcoming Deadlines',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              if (tasks.isEmpty)
                const _DashboardEmptyState(text: 'No dated active tasks.')
              else
                ...tasks.map(
                  (task) => _DeadlineTimelineTile(
                    task: task,
                    boardName: showBoardName ? boardNames[task.boardId] : null,
                    onTap: () => onOpenTask(task),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeadlineTimelineTile extends StatelessWidget {
  const _DeadlineTimelineTile({
    required this.task,
    required this.onTap,
    this.boardName,
  });

  final KanbanTask task;
  final String? boardName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dueAt = task.dueAt!;
    final today = DateTime.now();
    final label = _deadlineLabel(dueAt, today);
    final overdue = _dateOnly(
      dueAt,
    ).isBefore(DateTime(today.year, today.month, today.day));

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -3),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        Icons.event_rounded,
        size: 18,
        color: overdue ? colorScheme.error : colorScheme.primary,
      ),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (boardName != null) boardName, task.status].join(' - '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: 92,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: overdue ? colorScheme.error : colorScheme.onSurfaceVariant,
            fontWeight: overdue ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _deadlineLabel(DateTime dueAt, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = _dateOnly(dueAt);
    final days = dueDate.difference(today).inDays;
    if (days < 0) return 'Overdue';
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days <= 7) return 'This week';
    return _formatDate(dueAt);
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _TodaysFocusCard extends StatelessWidget {
  const _TodaysFocusCard({
    required this.tasks,
    required this.boardNames,
    required this.showBoardName,
    required this.onOpenTask,
  });

  final List<KanbanTask> tasks;
  final Map<String, String> boardNames;
  final bool showBoardName;
  final ValueChanged<KanbanTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 176),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Focus",
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              if (tasks.isEmpty)
                const _DashboardEmptyState(
                  text: 'No dated priorities right now.',
                )
              else
                ...tasks.map(
                  (task) => _DashboardTaskTile(
                    task: task,
                    boardName: showBoardName ? boardNames[task.boardId] : null,
                    highlightOverdue: _isOverdue(task),
                    onTap: () => onOpenTask(task),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isOverdue(KanbanTask task) {
    final dueAt = task.dueAt;
    if (dueAt == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(dueAt.year, dueAt.month, dueAt.day).isBefore(today);
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('images/logo_256.png', height: 56),
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading workspace',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BoardListTile extends ConsumerWidget {
  const _BoardListTile({
    required this.board,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onCollaborators,
    required this.onLeave,
    required this.onDelete,
  });

  final KanbanBoard board;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onCollaborators;
  final VoidCallback onLeave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    if (board.id == demoBoardId) {
      return _CompactDrawerRow(
        icon: Icons.apps_rounded,
        title: board.name,
        selected: selected,
        onTap: onSelect,
      );
    }

    final access = ref.watch(boardAccessProvider(board.id)).value;
    final members = ref.watch(boardMembersProvider(board.id)).value ?? [];
    final invites = ref.watch(boardInvitesProvider(board.id)).value ?? [];
    final collaboratorCount = members.where((m) => !m.isOwner).length;
    final shared = collaboratorCount > 0 || invites.isNotEmpty;
    final roleLabel = access == null ? 'Shared' : _roleLabel(access);

    return _CompactDrawerRow(
      icon: board.isList ? Icons.list_alt_rounded : Icons.account_tree_rounded,
      title: board.name,
      selected: selected,
      onTap: onSelect,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            Container(
              constraints: const BoxConstraints(maxWidth: 60),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                roleLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (shared)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message:
                    invites.isEmpty
                        ? '$collaboratorCount collaborator${collaboratorCount == 1 ? '' : 's'}'
                        : '$collaboratorCount collaborator${collaboratorCount == 1 ? '' : 's'}, ${invites.length} pending',
                child: Icon(
                  invites.isEmpty
                      ? Icons.people_alt_rounded
                      : Icons.mark_email_unread_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Board actions',
            icon: const Icon(Icons.more_vert_rounded, size: 19),
            onSelected: (value) {
              if (value == 'rename') onRename();
              if (value == 'collaborators') onCollaborators();
              if (value == 'leave') onLeave();
              if (value == 'delete') onDelete();
            },
            itemBuilder:
                (context) => [
                  if (access?.canEdit ?? false)
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('Rename'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'collaborators',
                    child: Row(
                      children: [
                        Icon(Icons.group_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Collaborators'),
                      ],
                    ),
                  ),
                  if (access != null && !access.isOwner)
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(Icons.exit_to_app_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('Leave board'),
                        ],
                      ),
                    ),
                  if (access?.isOwner ?? false)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                ],
          ),
        ],
      ),
    );
  }

  String _roleLabel(KanbanBoardMember member) {
    if (member.isOwner) return 'Owner';
    return switch (member.role) {
      'editor' => 'Editor',
      'viewer' => 'Viewer',
      _ => 'Collaborator',
    };
  }
}

class _CompactDrawerRow extends StatelessWidget {
  const _CompactDrawerRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 42,
          decoration: BoxDecoration(
            color: selected ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 9),
              Icon(
                icon,
                size: 20,
                color:
                    selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsAction extends ConsumerWidget {
  const _NotificationsAction({
    required this.onOpenChat,
    required this.onOpenTask,
    required this.onOpenInvites,
  });

  final ValueChanged<String> onOpenChat;
  final void Function(String boardId, KanbanTask task) onOpenTask;
  final VoidCallback onOpenInvites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider).value ?? const [];
    final pendingInvites =
        ref.watch(pendingBoardInvitesProvider).value ??
        const <KanbanPendingBoardInvite>[];
    final notifiedInviteIds =
        notifications
            .where((notification) => notification.notificationType == 'invite')
            .map(_inviteIdFromNotification)
            .whereType<String>()
            .toSet();
    final count =
        notifications.length +
        pendingInvites
            .where((invite) => !notifiedInviteIds.contains(invite.id))
            .length;

    return IconButton(
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded),
          if (count > 0)
            Positioned(
              right: -8,
              top: -8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 18,
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onError,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      onPressed:
          () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            builder:
                (_) => _NotificationsSheet(
                  onOpenChat: onOpenChat,
                  onOpenTask: onOpenTask,
                  onOpenInvites: onOpenInvites,
                ),
          ),
    );
  }
}

class _NotificationsSheet extends ConsumerStatefulWidget {
  const _NotificationsSheet({
    required this.onOpenChat,
    required this.onOpenTask,
    required this.onOpenInvites,
  });

  final ValueChanged<String> onOpenChat;
  final void Function(String boardId, KanbanTask task) onOpenTask;
  final VoidCallback onOpenInvites;

  @override
  ConsumerState<_NotificationsSheet> createState() =>
      _NotificationsSheetState();
}

class _NotificationsSheetState extends ConsumerState<_NotificationsSheet> {
  final _busyInviteIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final notificationsValue = ref.watch(notificationsProvider);
    final pendingInvitesValue = ref.watch(pendingBoardInvitesProvider);
    final boards = ref.watch(allBoardsProvider).value ?? const [];
    final boardById = {for (final board in boards) board.id: board};

    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: notificationsValue.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, _) => Center(
                        child: Text(
                          friendlyErrorMessage(
                            error,
                            fallback: 'Could not load notifications.',
                          ),
                        ),
                      ),
                  data: (notifications) {
                    final pendingInvites =
                        pendingInvitesValue.value ??
                        const <KanbanPendingBoardInvite>[];
                    final boardIds =
                        notifications
                            .map((notification) => notification.boardId)
                            .whereType<String>()
                            .toSet();
                    final membersByBoard = {
                      for (final boardId in boardIds)
                        boardId:
                            ref.watch(boardMembersProvider(boardId)).value ??
                            const <KanbanBoardMember>[],
                    };
                    final notifiedInviteIds =
                        notifications
                            .where(
                              (notification) =>
                                  notification.notificationType == 'invite',
                            )
                            .map(_inviteIdFromNotification)
                            .whereType<String>()
                            .toSet();
                    final inviteNotifications =
                        pendingInvites
                            .where(
                              (invite) =>
                                  !notifiedInviteIds.contains(invite.id),
                            )
                            .toList();
                    final displayItems = _notificationDisplayItems(
                      notifications,
                    );
                    final itemCount =
                        displayItems.length + inviteNotifications.length;

                    if (itemCount == 0) {
                      return const Center(child: Text('No notifications.'));
                    }

                    return ListView.separated(
                      itemCount: itemCount,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index >= displayItems.length) {
                          final invite =
                              inviteNotifications[index - displayItems.length];
                          return _InviteNotificationTile(
                            invite: invite,
                            busy: _busyInviteIds.contains(invite.id),
                            onOpen: () => _openPendingInvite(context),
                            onAccept: () => _acceptInvite(invite),
                            onDecline: () => _declineInvite(invite),
                          );
                        }

                        final item = displayItems[index];
                        if (item is _TaskNotificationGroup) {
                          final latest = item.latest;
                          final boardName =
                              boardById[latest.boardId]?.name ?? 'Board';
                          return ListTile(
                            leading: const Icon(Icons.dynamic_feed_rounded),
                            title: Text(
                              _taskGroupTitle(item),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _taskGroupSubtitle(item, boardName),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _openTaskNotificationGroup(item),
                          );
                        }

                        final notification = item as KanbanNotification;
                        final boardName =
                            boardById[notification.boardId]?.name ?? 'Board';
                        final actorName = _actorName(
                          notification,
                          membersByBoard[notification.boardId] ??
                              const <KanbanBoardMember>[],
                        );
                        final invite = _pendingInviteForNotification(
                          pendingInvites,
                          notification,
                        );

                        if (invite != null) {
                          return _InviteNotificationTile(
                            invite: invite,
                            busy: _busyInviteIds.contains(invite.id),
                            onOpen: () => _openNotification(notification),
                            onAccept: () => _acceptInvite(invite),
                            onDecline: () => _declineInvite(invite),
                          );
                        }

                        return ListTile(
                          leading: Icon(_notificationIcon(notification)),
                          title: Text(
                            _notificationTitle(
                              notification,
                              boardName,
                              actorName,
                            ),
                          ),
                          subtitle: Text(
                            _notificationSubtitle(notification, boardName),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _openNotification(notification),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  KanbanPendingBoardInvite? _pendingInviteForNotification(
    List<KanbanPendingBoardInvite> pendingInvites,
    KanbanNotification notification,
  ) {
    final inviteId = _inviteIdFromNotification(notification);
    if (inviteId == null) {
      return null;
    }
    for (final invite in pendingInvites) {
      if (invite.id == inviteId) {
        return invite;
      }
    }
    return null;
  }

  List<Object> _notificationDisplayItems(
    List<KanbanNotification> notifications,
  ) {
    final grouped = <String, List<KanbanNotification>>{};
    for (final notification in notifications) {
      final key = _taskNotificationGroupKey(notification);
      if (key != null) {
        grouped.putIfAbsent(key, () => []).add(notification);
      }
    }

    final emittedGroups = <String>{};
    final items = <Object>[];
    for (final notification in notifications) {
      final key = _taskNotificationGroupKey(notification);
      if (key == null) {
        items.add(notification);
        continue;
      }

      if (emittedGroups.add(key)) {
        final group = grouped[key]!;
        if (group.length == 1) {
          items.add(notification);
        } else {
          items.add(_TaskNotificationGroup(group));
        }
      }
    }
    return items;
  }

  String? _taskNotificationGroupKey(KanbanNotification notification) {
    if (!_isTaskNotification(notification)) {
      return null;
    }
    final boardId = notification.boardId;
    final taskId = notification.taskId;
    if (boardId == null || taskId == null) {
      return null;
    }
    return '$boardId:$taskId';
  }

  bool _isTaskNotification(KanbanNotification notification) {
    return switch (notification.notificationType) {
      'task_created' ||
      'task_updated' ||
      'task_moved' ||
      'comment_added' ||
      'mention' => notification.taskId != null,
      _ => false,
    };
  }

  String _taskGroupTitle(_TaskNotificationGroup group) {
    final subject = group.subject;
    final label = subject == null || subject.isEmpty ? 'this task' : subject;
    return '${group.count} updates on $label';
  }

  String _taskGroupSubtitle(_TaskNotificationGroup group, String boardName) {
    final actors = group.actorNames.take(2).toList();
    final actorText =
        actors.isEmpty
            ? 'Recent activity'
            : actors.length == 1
            ? actors.first
            : '${actors.first}, ${actors.last}';
    final extraActors = group.actorNames.length - actors.length;
    final actorSummary =
        extraActors > 0 ? '$actorText + $extraActors more' : actorText;
    return '$boardName - $actorSummary';
  }

  String? _actorName(
    KanbanNotification notification,
    List<KanbanBoardMember> members,
  ) {
    final actorId = notification.actorId;
    if (actorId == null || actorId.isEmpty) {
      return null;
    }

    for (final member in members) {
      if (member.userId == actorId) {
        return member.displayLabel;
      }
    }

    final metadataName = notification.actorDisplayName?.trim();
    if (metadataName != null && metadataName.isNotEmpty) {
      return metadataName;
    }

    return null;
  }

  String _notificationTitle(
    KanbanNotification notification,
    String boardName,
    String? actorName,
  ) {
    final subject = notification.subject?.trim();
    final actor = actorName ?? 'Someone';
    return switch (notification.notificationType) {
      'chat' => '$actor sent a chat in $boardName',
      'invite' => actorName == null ? 'Board invitation' : '$actor invited you',
      'mention' => '$actor mentioned you',
      'task_created' =>
        subject == null || subject.isEmpty
            ? '$actor created a task'
            : '$actor created $subject',
      'task_updated' =>
        subject == null || subject.isEmpty
            ? '$actor updated a task'
            : '$actor updated $subject',
      'task_moved' =>
        subject == null || subject.isEmpty
            ? '$actor moved a task'
            : '$actor moved $subject',
      'comment_added' =>
        subject == null || subject.isEmpty
            ? '$actor commented'
            : '$actor commented',
      _ => notification.title,
    };
  }

  String _notificationSubtitle(
    KanbanNotification notification,
    String boardName,
  ) {
    final subject = notification.subject?.trim();
    return switch (notification.notificationType) {
      'chat' =>
        subject == null || subject.isEmpty ? 'Open board chat' : subject,
      'mention' =>
        subject == null || subject.isEmpty
            ? boardName
            : '$boardName - $subject',
      'comment_added' =>
        subject == null || subject.isEmpty
            ? boardName
            : '$boardName - $subject',
      'task_created' || 'task_updated' || 'task_moved' => boardName,
      _ =>
        subject == null || subject.isEmpty
            ? boardName
            : '$boardName - $subject',
    };
  }

  IconData _notificationIcon(KanbanNotification notification) {
    return switch (notification.notificationType) {
      'chat' => Icons.forum_rounded,
      'invite' => Icons.person_add_alt_1_rounded,
      'mention' => Icons.alternate_email_rounded,
      'task_created' => Icons.add_task_rounded,
      'task_updated' => Icons.edit_note_rounded,
      'task_moved' => Icons.low_priority_rounded,
      'comment_added' => Icons.comment_rounded,
      _ => Icons.notifications_none_rounded,
    };
  }

  Future<void> _openNotification(KanbanNotification notification) async {
    final repository = ref.read(kanbanRepositoryProvider);
    final navigator = Navigator.of(context);
    final onOpenInvites = widget.onOpenInvites;
    final onOpenChat = widget.onOpenChat;
    final onOpenTask = widget.onOpenTask;
    await repository.markNotificationsRead(
      boardId: notification.boardId,
      taskId: notification.taskId,
      notificationType: notification.notificationType,
    );
    ref.invalidate(notificationsProvider);

    if (!navigator.mounted) {
      return;
    }
    navigator.pop();

    final boardId = notification.boardId;
    if (notification.notificationType == 'invite') {
      _runAfterSheetPop(onOpenInvites);
      return;
    }
    if ((notification.notificationType == 'chat' ||
            (notification.notificationType == 'mention' &&
                notification.taskId == null)) &&
        boardId != null) {
      _runAfterSheetPop(() => onOpenChat(boardId));
      return;
    }
    if (boardId != null && notification.taskId != null) {
      final tasks = await repository.listTasks(boardId);
      final matches = tasks.where((task) => task.id == notification.taskId);
      if (matches.isNotEmpty) {
        final task = matches.first;
        _runAfterSheetPop(() => onOpenTask(boardId, task));
      }
    }
  }

  Future<void> _openTaskNotificationGroup(_TaskNotificationGroup group) async {
    final latest = group.latest;
    final repository = ref.read(kanbanRepositoryProvider);
    final navigator = Navigator.of(context);
    final onOpenTask = widget.onOpenTask;

    await repository.markNotificationsRead(
      boardId: latest.boardId,
      taskId: latest.taskId,
    );
    ref.invalidate(notificationsProvider);

    if (!navigator.mounted) {
      return;
    }
    navigator.pop();

    final boardId = latest.boardId;
    final taskId = latest.taskId;
    if (boardId == null || taskId == null) {
      return;
    }

    final tasks = await repository.listTasks(boardId);
    final matches = tasks.where((task) => task.id == taskId);
    if (matches.isNotEmpty) {
      final task = matches.first;
      _runAfterSheetPop(() => onOpenTask(boardId, task));
    }
  }

  Future<void> _openPendingInvite(BuildContext context) async {
    final navigator = Navigator.of(context);
    await ref
        .read(kanbanRepositoryProvider)
        .markNotificationsRead(notificationType: 'invite');
    ref.invalidate(notificationsProvider);

    if (!navigator.mounted) {
      return;
    }
    navigator.pop();
    final onOpenInvites = widget.onOpenInvites;
    _runAfterSheetPop(onOpenInvites);
  }

  void _runAfterSheetPop(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action();
    });
  }

  Future<void> _acceptInvite(KanbanPendingBoardInvite invite) async {
    if (_busyInviteIds.contains(invite.id)) {
      return;
    }

    setState(() => _busyInviteIds.add(invite.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boardId = await ref
          .read(kanbanRepositoryProvider)
          .acceptBoardInvite(invite.id);
      await ref
          .read(kanbanRepositoryProvider)
          .markNotificationsRead(notificationType: 'invite');
      ref.read(selectedBoardIdProvider.notifier).state = boardId;
      invalidateKanban(ref, boardId: boardId);
      ref.invalidate(pendingBoardInvitesProvider);
      ref.invalidate(notificationsProvider);

      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Joined ${invite.boardName}.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              fallback: 'Could not accept that invitation.',
            ),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyInviteIds.remove(invite.id));
      }
    }
  }

  Future<void> _declineInvite(KanbanPendingBoardInvite invite) async {
    if (_busyInviteIds.contains(invite.id)) {
      return;
    }

    setState(() => _busyInviteIds.add(invite.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(kanbanRepositoryProvider).declineBoardInvite(invite.id);
      await ref
          .read(kanbanRepositoryProvider)
          .markNotificationsRead(notificationType: 'invite');
      ref.invalidate(pendingBoardInvitesProvider);
      ref.invalidate(notificationsProvider);

      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Declined ${invite.boardName}.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              fallback: 'Could not decline that invitation.',
            ),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyInviteIds.remove(invite.id));
      }
    }
  }
}

class _InviteNotificationTile extends StatelessWidget {
  const _InviteNotificationTile({
    required this.invite,
    required this.busy,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  final KanbanPendingBoardInvite invite;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final inviter = invite.inviterEmail?.trim();
    return ListTile(
      leading: const Icon(Icons.person_add_alt_1_rounded),
      title: Text(
        inviter == null || inviter.isEmpty
            ? 'Invitation to ${invite.boardName}'
            : '$inviter invited you to ${invite.boardName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_roleName(invite.role)} access',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          busy
              ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : SizedBox(
                width: 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Decline invite',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: onDecline,
                    ),
                    IconButton.filled(
                      tooltip: 'Accept invite',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.check_rounded),
                      onPressed: onAccept,
                    ),
                  ],
                ),
              ),
      onTap: onOpen,
    );
  }
}

class _TaskNotificationGroup {
  _TaskNotificationGroup(List<KanbanNotification> notifications)
    : notifications = List.unmodifiable(notifications);

  final List<KanbanNotification> notifications;

  KanbanNotification get latest => notifications.first;
  int get count => notifications.length;

  String? get subject {
    for (final notification in notifications) {
      final value = notification.subject?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  List<String> get actorNames {
    final seen = <String>{};
    final names = <String>[];
    for (final notification in notifications) {
      final value = notification.actorDisplayName?.trim();
      if (value != null && value.isNotEmpty && seen.add(value)) {
        names.add(value);
      }
    }
    return names;
  }
}

String? _inviteIdFromNotification(KanbanNotification notification) {
  if (notification.notificationType != 'invite') {
    return null;
  }
  const prefix = 'invite:';
  if (!notification.sourceKey.startsWith(prefix)) {
    return null;
  }
  return notification.sourceKey.substring(prefix.length);
}

String _roleName(String role) {
  return switch (role) {
    'editor' => 'Editor',
    'viewer' => 'Viewer',
    _ => role,
  };
}

class _PresenceAction extends ConsumerWidget {
  const _PresenceAction({required this.boardId});

  final String boardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(boardPresenceProvider(boardId)).value ?? [];
    final members = ref.watch(boardMembersProvider(boardId)).value ?? [];
    if (presence.isEmpty) {
      return const SizedBox.shrink();
    }

    final membersById = {for (final member in members) member.userId: member};
    final labels =
        presence.map((user) {
          final member = membersById[user.userId];
          return member?.displayLabel ?? user.email;
        }).toList();

    return Tooltip(
      message: labels.join(', '),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ActionChip(
          avatar: const Icon(Icons.circle_rounded, size: 12),
          label: Text('${presence.length}'),
          visualDensity: VisualDensity.compact,
          onPressed:
              () => showDialog<void>(
                context: context,
                builder:
                    (_) => _BoardPresenceDialog(
                      presence: presence,
                      membersById: membersById,
                    ),
              ),
        ),
      ),
    );
  }
}

class _BoardPresenceDialog extends StatelessWidget {
  const _BoardPresenceDialog({
    required this.presence,
    required this.membersById,
  });

  final List<KanbanPresenceUser> presence;
  final Map<String, KanbanBoardMember> membersById;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Viewing this board'),
      content: SizedBox(
        width: 360,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: presence.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final user = presence[index];
            final member = membersById[user.userId];
            final name = member?.displayLabel ?? user.email;
            final subtitle =
                member == null
                    ? user.email
                    : '${member.email} - ${_roleName(member.role)}';

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _ChatAvatar(author: name, avatarUrl: member?.avatarUrl),
              title: Text(name),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.visibility_rounded, size: 20),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ActivityDialog extends ConsumerStatefulWidget {
  const _ActivityDialog({required this.boardId});

  final String boardId;

  @override
  ConsumerState<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends ConsumerState<_ActivityDialog> {
  static const _activityPageSize = 50;

  final _scrollController = ScrollController();
  final List<KanbanActivityEvent> _olderEvents = [];
  bool _loadingOlder = false;
  bool _hasOlderEvents = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadOlderActivity);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadOlderActivity);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadOlderActivity() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 120) {
      return;
    }
    _loadOlderActivity();
  }

  Future<void> _loadOlderActivity() async {
    if (_loadingOlder || !_hasOlderEvents) {
      return;
    }

    final liveEvents =
        ref.read(boardActivityProvider(widget.boardId)).valueOrNull ??
        const <KanbanActivityEvent>[];
    final allEvents = _mergeActivity(liveEvents);
    if (allEvents.isEmpty) {
      return;
    }

    setState(() => _loadingOlder = true);
    try {
      final older = await ref
          .read(kanbanRepositoryProvider)
          .listBoardActivity(
            boardId: widget.boardId,
            before: allEvents.last.createdAt,
            limit: _activityPageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _olderEvents.addAll(older);
        _hasOlderEvents = older.length >= _activityPageSize;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              fallback: 'Could not load older activity.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingOlder = false);
      }
    }
  }

  List<KanbanActivityEvent> _mergeActivity(
    List<KanbanActivityEvent> liveEvents,
  ) {
    final byId = <String, KanbanActivityEvent>{
      for (final event in liveEvents) event.id: event,
      for (final event in _olderEvents) event.id: event,
    };
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    final activityValue = ref.watch(boardActivityProvider(widget.boardId));
    final members = ref.watch(boardMembersProvider(widget.boardId)).value ?? [];
    final memberById = {for (final member in members) member.userId: member};

    return AlertDialog(
      title: const Text('Board activity'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: activityValue.when(
          loading:
              () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Text(
                friendlyErrorMessage(
                  error,
                  fallback: 'Could not load activity.',
                ),
              ),
          data: (liveEvents) {
            final events = _mergeActivity(liveEvents);
            if (events.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No activity yet.'),
              );
            }

            return ListView.separated(
              controller: _scrollController,
              shrinkWrap: true,
              itemCount: events.length + 1,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == events.length) {
                  if (!_hasOlderEvents && !_loadingOlder) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: _loadingOlder ? null : _loadOlderActivity,
                        icon:
                            _loadingOlder
                                ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.history_rounded),
                        label: Text(
                          _loadingOlder
                              ? 'Loading older activity'
                              : 'Load older activity',
                        ),
                      ),
                    ),
                  );
                }
                final event = events[index];
                final actorName =
                    memberById[event.actorId]?.displayLabel ??
                    event.actorEmail ??
                    'Someone';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_activityIcon(event.eventType)),
                  title: Text(_activityText(event, actorName)),
                  subtitle: Text(_formatActivityTime(event.createdAt)),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  IconData _activityIcon(String type) {
    return switch (type) {
      'task_created' => Icons.add_task_rounded,
      'task_moved' => Icons.drive_file_move_rounded,
      'task_assigned' => Icons.assignment_ind_rounded,
      'task_updated' => Icons.edit_rounded,
      'task_deleted' => Icons.delete_outline_rounded,
      'task_commented' => Icons.chat_bubble_outline_rounded,
      _ => Icons.bolt_rounded,
    };
  }

  String _activityText(KanbanActivityEvent event, String actorName) {
    final subject = event.subject == null ? 'task' : '"${event.subject}"';
    return switch (event.eventType) {
      'task_created' => '$actorName created $subject',
      'task_moved' => '$actorName moved $subject',
      'task_assigned' => '$actorName assigned $subject',
      'task_updated' => '$actorName updated $subject',
      'task_deleted' => '$actorName deleted $subject',
      'task_commented' => '$actorName commented on $subject',
      'comment_added' => '$actorName commented on $subject',
      _ => '$actorName ${event.subject ?? event.eventType}',
    };
  }

  String _formatActivityTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} $hour:$minute';
  }
}

class _PendingInvitesDialog extends ConsumerStatefulWidget {
  const _PendingInvitesDialog();

  @override
  ConsumerState<_PendingInvitesDialog> createState() =>
      _PendingInvitesDialogState();
}

class _PendingInvitesDialogState extends ConsumerState<_PendingInvitesDialog> {
  final _busyInviteIds = <String>{};

  Future<void> _accept(KanbanPendingBoardInvite invite) async {
    if (_busyInviteIds.contains(invite.id)) {
      return;
    }

    setState(() => _busyInviteIds.add(invite.id));
    try {
      final boardId = await ref
          .read(kanbanRepositoryProvider)
          .acceptBoardInvite(invite.id);
      ref.read(selectedBoardIdProvider.notifier).state = boardId;
      invalidateKanban(ref, boardId: boardId);
      ref.invalidate(pendingBoardInvitesProvider);
      ref.invalidate(notificationsProvider);

      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Joined ${invite.boardName}.')));
    } catch (error, stackTrace) {
      _logInviteError('accept invite', error, stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_pendingInviteErrorMessage(error)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyInviteIds.remove(invite.id));
      }
    }
  }

  Future<void> _decline(KanbanPendingBoardInvite invite) async {
    if (_busyInviteIds.contains(invite.id)) {
      return;
    }

    setState(() => _busyInviteIds.add(invite.id));
    try {
      await ref.read(kanbanRepositoryProvider).declineBoardInvite(invite.id);
      ref.invalidate(pendingBoardInvitesProvider);
      ref.invalidate(notificationsProvider);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Declined ${invite.boardName}.')));
    } catch (error, stackTrace) {
      _logInviteError('decline invite', error, stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_pendingInviteErrorMessage(error)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyInviteIds.remove(invite.id));
      }
    }
  }

  void _logInviteError(String action, Object error, StackTrace stackTrace) {
    debugPrint('Pending invite $action failed: ${error.runtimeType}');
    if (error is PostgrestException) {
      debugPrint('PostgREST code: ${error.code}');
      debugPrint('PostgREST message: ${error.message}');
      debugPrint('PostgREST details: ${error.details}');
      debugPrint('PostgREST hint: ${error.hint}');
    } else {
      debugPrint(error.toString());
    }
    debugPrintStack(
      label: 'Pending invite $action stack',
      stackTrace: stackTrace,
    );
  }

  String _pendingInviteErrorMessage(Object error) {
    if (error is PostgrestException) {
      final parts =
          [
                if (error.code != null) error.code,
                error.message,
                if (error.details != null) error.details,
                if (error.hint != null) error.hint,
              ]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .toList();

      final rawMessage = parts.join(' ');
      final friendly = friendlyErrorMessage(
        error,
        fallback: 'Could not manage that invitation.',
      );

      if (friendly ==
          'The database rejected that change. Please refresh and try again.') {
        return rawMessage.isEmpty ? friendly : rawMessage;
      }
      return friendly;
    }

    return friendlyErrorMessage(
      error,
      fallback: 'Could not manage that invitation.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final invitesValue = ref.watch(pendingBoardInvitesProvider);

    return AlertDialog(
      title: const Text('Pending invites'),
      content: SizedBox(
        width: 460,
        child: invitesValue.when(
          loading:
              () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Text(
                friendlyErrorMessage(
                  error,
                  fallback: 'Could not load invitations.',
                ),
              ),
          data: (invites) {
            if (invites.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No pending invitations.'),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              itemCount: invites.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final invite = invites[index];
                final busy = _busyInviteIds.contains(invite.id);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_shared_rounded),
                  title: Text(invite.boardName),
                  subtitle: Text(
                    '${_roleName(invite.role)} invite'
                    '${invite.inviterEmail == null ? '' : ' from ${invite.inviterEmail}'}',
                  ),
                  trailing:
                      busy
                          ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Decline invite',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => _decline(invite),
                              ),
                              IconButton.filled(
                                tooltip: 'Accept invite',
                                icon: const Icon(Icons.check_rounded),
                                onPressed: () => _accept(invite),
                              ),
                            ],
                          ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _roleName(String role) {
    return switch (role) {
      'editor' => 'Editor',
      'viewer' => 'Viewer',
      _ => role,
    };
  }
}

class _BoardChatSheet extends ConsumerStatefulWidget {
  const _BoardChatSheet({
    required this.boardId,
    this.fillAvailable = false,
    this.onClose,
  });

  final String boardId;
  final bool fillAvailable;
  final VoidCallback? onClose;

  @override
  ConsumerState<_BoardChatSheet> createState() => _BoardChatSheetState();
}

class _BoardChatSheetState extends ConsumerState<_BoardChatSheet> {
  static const _messagePageSize = 50;

  final _controller = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<KanbanBoardMessage> _olderMessages = [];
  bool _sending = false;
  bool _loadingOlder = false;
  bool _hasOlderMessages = true;
  bool _scrolledToInitialLatest = false;
  String? _pendingMessageId;
  KanbanBoardMessage? _replyingTo;
  String? _openMessageOptionsId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadOlderMessages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markChatNotificationsRead();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _messageFocusNode.dispose();
    _scrollController.removeListener(_maybeLoadOlderMessages);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadOlderMessages() {
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels > 80) {
      return;
    }
    _loadOlderMessages();
  }

  Future<void> _markChatNotificationsRead() async {
    if (!mounted) {
      return;
    }

    await ref
        .read(kanbanRepositoryProvider)
        .markNotificationsRead(
          boardId: widget.boardId,
          notificationType: 'chat',
        );

    if (mounted) {
      ref.invalidate(notificationsProvider);
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) {
      return;
    }

    setState(() => _sending = true);
    final messageId = _pendingMessageId ?? const Uuid().v4();
    final replyToMessageId = _replyingTo?.id;
    _pendingMessageId = messageId;
    try {
      await ref
          .read(kanbanRepositoryProvider)
          .addBoardMessage(
            boardId: widget.boardId,
            body: body,
            messageId: messageId,
            replyToMessageId: replyToMessageId,
          );
      try {
        await ref
            .read(driveLinkRepositoryProvider)
            .replaceMessageLinks(
              boardId: widget.boardId,
              messageId: messageId,
              links: GoogleDriveUrlParser.extractLinks(body),
            );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyErrorMessage(
                  error,
                  fallback: 'Message sent, but Drive previews could not save.',
                ),
              ),
            ),
          );
        }
      }
      _controller.clear();
      if (mounted) {
        setState(() => _replyingTo = null);
        _scrollToLatest();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, fallback: 'Could not send message.'),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingMessageId = null;
        });
      }
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasOlderMessages) {
      return;
    }

    final liveMessages =
        ref.read(boardMessagesProvider(widget.boardId)).valueOrNull ??
        const <KanbanBoardMessage>[];
    final allMessages = _mergeMessages(liveMessages);
    if (allMessages.isEmpty) {
      return;
    }

    setState(() => _loadingOlder = true);
    final oldMaxExtent =
        _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent
            : 0.0;
    try {
      final older = await ref
          .read(kanbanRepositoryProvider)
          .listBoardMessages(
            boardId: widget.boardId,
            before: allMessages.first.createdAt,
            limit: _messagePageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _olderMessages.addAll(older);
        _hasOlderMessages = older.length >= _messagePageSize;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }
        final newMaxExtent = _scrollController.position.maxScrollExtent;
        final delta = newMaxExtent - oldMaxExtent;
        if (delta > 0) {
          _scrollController.jumpTo(_scrollController.position.pixels + delta);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              fallback: 'Could not load older messages.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingOlder = false);
      }
    }
  }

  List<KanbanBoardMessage> _mergeMessages(
    List<KanbanBoardMessage> liveMessages,
  ) {
    final byId = <String, KanbanBoardMessage>{
      for (final message in _olderMessages) message.id: message,
      for (final message in liveMessages) message.id: message,
    };
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    final messagesValue = ref.watch(boardMessagesProvider(widget.boardId));
    final reactions =
        ref.watch(boardMessageReactionsProvider(widget.boardId)).value ??
        const <KanbanMessageReaction>[];
    final reactionsByMessage = <String, List<KanbanMessageReaction>>{};
    for (final reaction in reactions) {
      reactionsByMessage
          .putIfAbsent(reaction.messageId, () => <KanbanMessageReaction>[])
          .add(reaction);
    }
    final members =
        ref.watch(boardMembersProvider(widget.boardId)).value ??
        const <KanbanBoardMember>[];
    final memberById = {for (final member in members) member.userId: member};
    final currentUser = ref.watch(currentUserProvider);

    final chatContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.forum_rounded),
            const SizedBox(width: 10),
            Text(
              'Board Chat',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (widget.onClose != null)
              IconButton(
                tooltip: 'Close chat',
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onClose,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: messagesValue.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, _) => Center(
                  child: Text(
                    friendlyErrorMessage(
                      error,
                      fallback: 'Could not load messages.',
                    ),
                  ),
                ),
            data: (liveMessages) {
              final sortedMessages = _mergeMessages(liveMessages);
              final messageById = {
                for (final message in sortedMessages) message.id: message,
              };
              if (sortedMessages.isEmpty) {
                return const Center(child: Text('No messages yet.'));
              }

              if (!_scrolledToInitialLatest) {
                _scrolledToInitialLatest = true;
                _scrollToLatest();
              }
              return LayoutBuilder(
                builder:
                    (context, constraints) => SingleChildScrollView(
                      controller: _scrollController,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_hasOlderMessages || _loadingOlder) ...[
                              TextButton.icon(
                                onPressed:
                                    _loadingOlder ? null : _loadOlderMessages,
                                icon:
                                    _loadingOlder
                                        ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(
                                          Icons.keyboard_arrow_up_rounded,
                                        ),
                                label: Text(
                                  _loadingOlder
                                      ? 'Loading older messages'
                                      : 'Load older messages',
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            for (final message in sortedMessages) ...[
                              Builder(
                                builder: (context) {
                                  final member = memberById[message.authorId];
                                  final author =
                                      member?.displayLabel ??
                                      (message.authorId == currentUser?.id
                                          ? 'You'
                                          : 'Collaborator');
                                  final replyToMessage =
                                      message.replyToMessageId == null
                                          ? null
                                          : messageById[message
                                              .replyToMessageId];
                                  final replyMember =
                                      replyToMessage == null
                                          ? null
                                          : memberById[replyToMessage.authorId];
                                  final replyAuthor =
                                      replyToMessage == null
                                          ? null
                                          : replyToMessage.authorId ==
                                              currentUser?.id
                                          ? 'You'
                                          : replyMember?.displayLabel ??
                                              'Collaborator';
                                  return _BoardChatBubble(
                                    message: message,
                                    author: author,
                                    avatarUrl: member?.avatarUrl,
                                    replyToMessage: replyToMessage,
                                    replyAuthor: replyAuthor,
                                    isMine: message.authorId == currentUser?.id,
                                    canDelete:
                                        message.authorId == currentUser?.id,
                                    reactions:
                                        reactionsByMessage[message.id] ??
                                        const <KanbanMessageReaction>[],
                                    currentUserId: currentUser?.id,
                                    sentAt: _formatChatTime(message.createdAt),
                                    showDetails:
                                        _openMessageOptionsId == message.id,
                                    onToggleDetails:
                                        () => _toggleMessageOptions(message.id),
                                    onDelete: () {
                                      setState(
                                        () => _openMessageOptionsId = null,
                                      );
                                      _deleteMessage(message);
                                    },
                                    onReact:
                                        (emoji) =>
                                            _toggleReaction(message, emoji),
                                    onReply: () => _startReply(message),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (_replyingTo != null) ...[
          _ChatReplyComposerPreview(
            author:
                _replyingTo!.authorId == currentUser?.id
                    ? 'You'
                    : memberById[_replyingTo!.authorId]?.displayLabel ??
                        'Collaborator',
            body: _replyingTo!.body,
            onCancel: _cancelReply,
          ),
          const SizedBox(height: 8),
        ],
        MentionAutocompleteTextField(
          controller: _controller,
          focusNode: _messageFocusNode,
          members: members,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.send,
          decoration: InputDecoration(
            labelText: 'Message collaborators',
            filled: true,
            suffixIcon: IconButton(
              tooltip: 'Send message',
              icon:
                  _sending
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.send_rounded),
              onPressed: _sending ? null : _send,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (_) => _send(),
        ),
      ],
    );

    final chatBody =
        widget.fillAvailable
            ? DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: chatContent,
              ),
            )
            : SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: chatContent,
            );

    return SafeArea(
      child: Padding(
        padding:
            widget.fillAvailable
                ? const EdgeInsets.fromLTRB(12, 12, 14, 24)
                : EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
        child: chatBody,
      ),
    );
  }

  String _formatChatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} $hour:$minute';
  }

  Future<void> _deleteMessage(KanbanBoardMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete message?'),
            content: const Text(
              'This deletes the chat message for everyone on the board.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(kanbanRepositoryProvider).deleteBoardMessage(message.id);
      if (mounted) {
        setState(() {
          _olderMessages.removeWhere(
            (oldMessage) => oldMessage.id == message.id,
          );
        });
        ref.invalidate(boardMessagesProvider(widget.boardId));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, fallback: 'Could not delete message.'),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _toggleReaction(KanbanBoardMessage message, String emoji) async {
    try {
      await ref
          .read(kanbanRepositoryProvider)
          .toggleBoardMessageReaction(
            boardId: widget.boardId,
            messageId: message.id,
            emoji: emoji,
          );
      ref.invalidate(boardMessageReactionsProvider(widget.boardId));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, fallback: 'Could not update reaction.'),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _startReply(KanbanBoardMessage message) {
    setState(() {
      _replyingTo = message;
      _openMessageOptionsId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _messageFocusNode.requestFocus();
      }
    });
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  void _toggleMessageOptions(String messageId) {
    setState(() {
      _openMessageOptionsId =
          _openMessageOptionsId == messageId ? null : messageId;
    });
  }
}

class _ChatReplyComposerPreview extends StatelessWidget {
  const _ChatReplyComposerPreview({
    required this.author,
    required this.body,
    required this.onCancel,
  });

  final String author;
  final String body;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Icon(Icons.reply_rounded, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Replying to $author',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _chatReplySnippet(body),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cancel reply',
              icon: const Icon(Icons.close_rounded),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatReplyPreview extends StatelessWidget {
  const _ChatReplyPreview({
    required this.author,
    required this.body,
    required this.alignEnd,
  });

  final String author;
  final String body;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment:
                alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _chatReplySnippet(body),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _chatReplySnippet(String body) {
  final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 120) {
    return normalized;
  }
  return '${normalized.substring(0, 117)}...';
}

class _BoardChatBubble extends ConsumerStatefulWidget {
  const _BoardChatBubble({
    required this.message,
    required this.author,
    required this.avatarUrl,
    required this.replyToMessage,
    required this.replyAuthor,
    required this.isMine,
    required this.canDelete,
    required this.reactions,
    required this.currentUserId,
    required this.sentAt,
    required this.showDetails,
    required this.onToggleDetails,
    required this.onDelete,
    required this.onReact,
    required this.onReply,
  });

  final KanbanBoardMessage message;
  final String author;
  final String? avatarUrl;
  final KanbanBoardMessage? replyToMessage;
  final String? replyAuthor;
  final bool isMine;
  final bool canDelete;
  final List<KanbanMessageReaction> reactions;
  final String? currentUserId;
  final String sentAt;
  final bool showDetails;
  final VoidCallback onToggleDetails;
  final VoidCallback onDelete;
  final ValueChanged<String> onReact;
  final VoidCallback onReply;

  @override
  ConsumerState<_BoardChatBubble> createState() => _BoardChatBubbleState();
}

class _BoardChatBubbleState extends ConsumerState<_BoardChatBubble> {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleDetails,
        child: Row(
          mainAxisAlignment:
              widget.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!widget.isMine) ...[
              _ChatAvatar(author: widget.author, avatarUrl: widget.avatarUrl),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        widget.isMine
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment:
                          widget.isMine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                      children: [
                        if (widget.replyToMessage != null) ...[
                          _ChatReplyPreview(
                            author: widget.replyAuthor ?? 'Collaborator',
                            body: widget.replyToMessage!.body,
                            alignEnd: widget.isMine,
                          ),
                          const SizedBox(height: 8),
                        ],
                        DriveLinkPreviewBlock(
                          text: widget.message.body,
                          linksValue: ref.watch(
                            driveLinksForMessageProvider(widget.message.id),
                          ),
                          alignEnd: widget.isMine,
                        ),
                        _MessageReactionRow(
                          reactions: widget.reactions,
                          currentUserId: widget.currentUserId,
                          alignEnd: widget.isMine,
                          showControls: widget.showDetails,
                          canDelete: widget.canDelete,
                          onReact: widget.onReact,
                          onDelete: widget.onDelete,
                          onReply: widget.onReply,
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              widget.sentAt,
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          crossFadeState:
                              widget.showDetails
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 140),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.isMine) ...[
              const SizedBox(width: 8),
              _ChatAvatar(author: widget.author, avatarUrl: widget.avatarUrl),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageReactionRow extends StatelessWidget {
  const _MessageReactionRow({
    required this.reactions,
    required this.currentUserId,
    required this.alignEnd,
    required this.showControls,
    required this.canDelete,
    required this.onReact,
    required this.onDelete,
    required this.onReply,
  });

  static const _quickEmojis = ['👍', '❤️', '😂', '🎉', '👀'];

  final List<KanbanMessageReaction> reactions;
  final String? currentUserId;
  final bool alignEnd;
  final bool showControls;
  final bool canDelete;
  final ValueChanged<String> onReact;
  final VoidCallback onDelete;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<KanbanMessageReaction>>{};
    for (final reaction in reactions) {
      final emojiReactions = grouped.putIfAbsent(
        reaction.emoji,
        () => <KanbanMessageReaction>[],
      );
      if (!emojiReactions.any(
        (existing) => existing.userId == reaction.userId,
      )) {
        emojiReactions.add(reaction);
      }
    }

    if (grouped.isEmpty && !showControls) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
        children: [
          ...grouped.entries.map((entry) {
            final reacted =
                currentUserId != null &&
                entry.value.any((reaction) => reaction.userId == currentUserId);
            return _ReactionChip(
              emoji: entry.key,
              count: entry.value.length,
              selected: reacted,
              onPressed: () => onReact(entry.key),
            );
          }),
          if (showControls) ...[
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.reply_rounded, size: 16),
              label: const Text('Reply'),
              tooltip: 'Reply to message',
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              onPressed: onReply,
            ),
            PopupMenuButton<String>(
              tooltip: 'React',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 0),
              onSelected: onReact,
              itemBuilder:
                  (context) =>
                      _quickEmojis
                          .map(
                            (emoji) => PopupMenuItem(
                              value: emoji,
                              child: Text(
                                emoji,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          )
                          .toList(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(Icons.add_reaction_outlined, size: 16),
                ),
              ),
            ),
            if (canDelete)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete'),
                tooltip: 'Delete for everyone',
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onPressed: onDelete,
              ),
          ],
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final String emoji;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ActionChip(
      visualDensity: VisualDensity.compact,
      label: Text('$emoji $count'),
      tooltip: selected ? 'Remove reaction' : 'React with $emoji',
      side: BorderSide(
        color: selected ? colorScheme.primary : colorScheme.outlineVariant,
      ),
      backgroundColor:
          selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surface,
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: selected ? colorScheme.primary : colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      onPressed: onPressed,
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.author, this.avatarUrl});

  final String author;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child:
          url == null || url.isEmpty
              ? Text(
                _initial(author),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              )
              : null,
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _EmptyBoardState extends StatelessWidget {
  const _EmptyBoardState({required this.onCreateBoard});

  final VoidCallback onCreateBoard;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dashboard_customize_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Create your first board',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Boards, stages, and tasks will sync to your Noggin account.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreateBoard,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Board'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollaboratorsDialog extends ConsumerStatefulWidget {
  const _CollaboratorsDialog({required this.board});

  final KanbanBoard board;

  @override
  ConsumerState<_CollaboratorsDialog> createState() =>
      _CollaboratorsDialogState();
}

class _CollaboratorsDialogState extends ConsumerState<_CollaboratorsDialog> {
  final _emailController = TextEditingController();
  String _role = 'editor';
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _submitting) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(kanbanRepositoryProvider)
          .inviteBoardMember(
            boardId: widget.board.id,
            email: email,
            role: _role,
          );
      _invalidateCollaboration();
      _emailController.clear();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation saved.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_inviteErrorMessage(error)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _inviteErrorMessage(Object error) {
    if (error is PostgrestException) {
      final parts =
          [
                if (error.code != null) error.code,
                error.message,
                if (error.details != null) error.details,
                if (error.hint != null) error.hint,
              ]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .toList();

      final rawMessage = parts.join(' ');
      final friendly = friendlyErrorMessage(
        error,
        fallback: 'Could not invite that collaborator.',
      );

      if (friendly ==
          'The database rejected that change. Please refresh and try again.') {
        return rawMessage.isEmpty ? friendly : rawMessage;
      }
      return friendly;
    }

    return friendlyErrorMessage(
      error,
      fallback: 'Could not invite that collaborator.',
    );
  }

  Future<void> _remove(KanbanBoardMember member) async {
    final confirmed = await _confirm(
      title: 'Remove collaborator',
      message: 'Remove ${member.email} from this board?',
      confirmLabel: 'Remove',
    );
    if (!confirmed) {
      return;
    }

    await ref
        .read(kanbanRepositoryProvider)
        .removeBoardMember(boardId: widget.board.id, userId: member.userId);
    _invalidateCollaboration();
  }

  Future<void> _leave() async {
    final confirmed = await _confirm(
      title: 'Leave board',
      message:
          'Leave "${widget.board.name}"? You will lose access until the owner invites you again.',
      confirmLabel: 'Leave',
    );
    if (!confirmed) {
      return;
    }

    final selectedId = ref.read(selectedBoardIdProvider);
    await ref.read(kanbanRepositoryProvider).leaveBoard(widget.board.id);
    invalidateKanban(ref, boardId: widget.board.id);

    if (selectedId == widget.board.id) {
      ref.read(selectedBoardIdProvider.notifier).state = demoBoardId;
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _changeRole(KanbanBoardMember member, String role) async {
    if (member.role == role) {
      return;
    }

    await ref
        .read(kanbanRepositoryProvider)
        .updateBoardMemberRole(
          boardId: widget.board.id,
          userId: member.userId,
          role: role,
        );
    _invalidateCollaboration();
  }

  Future<void> _cancelInvite(KanbanBoardInvite invite) async {
    final confirmed = await _confirm(
      title: 'Cancel invitation',
      message: 'Cancel the invitation for ${invite.email}?',
      confirmLabel: 'Cancel invite',
    );
    if (!confirmed) {
      return;
    }

    await ref
        .read(kanbanRepositoryProvider)
        .cancelBoardInvite(boardId: widget.board.id, inviteId: invite.id);
    _invalidateCollaboration();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
    );
    return confirmed ?? false;
  }

  void _invalidateCollaboration() {
    ref.invalidate(boardMembersProvider(widget.board.id));
    ref.invalidate(boardInvitesProvider(widget.board.id));
    ref.invalidate(boardAccessProvider(widget.board.id));
    ref.invalidate(canEditBoardProvider(widget.board.id));
  }

  @override
  Widget build(BuildContext context) {
    final membersValue = ref.watch(boardMembersProvider(widget.board.id));
    final invitesValue = ref.watch(boardInvitesProvider(widget.board.id));
    final currentUser = ref.watch(currentUserProvider);

    return AlertDialog(
      title: Text('${widget.board.name} collaborators'),
      content: SizedBox(
        width: 440,
        child: membersValue.when(
          loading:
              () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Text(
                friendlyErrorMessage(
                  error,
                  fallback: 'Could not load collaborators.',
                ),
              ),
          data: (members) {
            final invites = invitesValue.value ?? const <KanbanBoardInvite>[];
            final currentMember = members.where(
              (member) => member.userId == currentUser?.id,
            );
            final canManage =
                currentMember.isNotEmpty &&
                currentMember.first.canManageMembers;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canManage) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(labelText: 'Email'),
                          onSubmitted: (_) => _invite(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _role,
                        items: const [
                          DropdownMenuItem(
                            value: 'editor',
                            child: Text('Editor'),
                          ),
                          DropdownMenuItem(
                            value: 'viewer',
                            child: Text('Viewer'),
                          ),
                        ],
                        onChanged:
                            _submitting
                                ? null
                                : (value) {
                                  if (value != null) {
                                    setState(() => _role = value);
                                  }
                                },
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Invite collaborator',
                        onPressed: _submitting ? null : _invite,
                        icon:
                            _submitting
                                ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.person_add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...members.map(
                        (member) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            member.isOwner
                                ? Icons.admin_panel_settings_rounded
                                : Icons.person_outline_rounded,
                          ),
                          title: Text(member.displayLabel),
                          subtitle: Text(
                            '${member.handle} - ${_roleLabel(member)}',
                          ),
                          trailing:
                              canManage && !member.isOwner
                                  ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DropdownButton<String>(
                                        value:
                                            member.role == 'viewer'
                                                ? 'viewer'
                                                : 'editor',
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'editor',
                                            child: Text('Editor'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'viewer',
                                            child: Text('Viewer'),
                                          ),
                                        ],
                                        onChanged: (role) {
                                          if (role != null) {
                                            _changeRole(member, role);
                                          }
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Remove collaborator',
                                        icon: const Icon(
                                          Icons.person_remove_rounded,
                                        ),
                                        onPressed: () => _remove(member),
                                      ),
                                    ],
                                  )
                                  : null,
                        ),
                      ),
                      if (members.length == 1 && invites.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            canManage
                                ? 'No collaborators yet.'
                                : 'Only the owner has access right now.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (invites.isNotEmpty) ...[
                        const Divider(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Pending invitations',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...invites.map(
                          (invite) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.mail_outline_rounded),
                            title: Text(invite.email),
                            subtitle: Text('${_roleName(invite.role)} pending'),
                            trailing:
                                canManage
                                    ? IconButton(
                                      tooltip: 'Cancel invitation',
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () => _cancelInvite(invite),
                                    )
                                    : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        if (membersValue.value?.any(
              (member) => member.userId == currentUser?.id && !member.isOwner,
            ) ??
            false)
          TextButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('Leave board'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _roleLabel(KanbanBoardMember member) {
    if (member.isOwner) {
      return 'Owner';
    }
    return _roleName(member.role);
  }

  String _roleName(String role) {
    return switch (role) {
      'editor' => 'Editor',
      'viewer' => 'Viewer',
      _ => role,
    };
  }
}
