import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/friendly_error_message.dart';
import '../../drive_links/data/drive_link_providers.dart';
import '../../drive_links/data/google_drive_url_parser.dart';
import '../../drive_links/presentation/drive_link_preview_block.dart';
import '../data/kanban_providers.dart';
import '../domain/kanban_task.dart';
import 'task_editor_sheet.dart';

class KanbanBoardView extends ConsumerStatefulWidget {
  const KanbanBoardView({
    required this.boardId,
    required this.canEdit,
    super.key,
  });

  final String boardId;
  final bool canEdit;

  @override
  ConsumerState<KanbanBoardView> createState() => _KanbanBoardViewState();
}

class _KanbanBoardViewState extends ConsumerState<KanbanBoardView> {
  List<KanbanStage>? _optimisticStages;
  final _stageScrollController = ScrollController();

  @override
  void dispose() {
    _stageScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KanbanBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boardId != widget.boardId) {
      _optimisticStages = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.boardId == demoBoardId) {
      return const _AllTasksByBoard();
    }

    final stagesValue = ref.watch(stagesProvider(widget.boardId));

    return stagesValue.when(
      data: (stages) {
        final displayedStages = _optimisticStages ?? stages;
        return Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent ||
                !_stageScrollController.hasClients) {
              return;
            }

            final position = _stageScrollController.position;
            final nextOffset =
                (_stageScrollController.offset + event.scrollDelta.dy)
                    .clamp(position.minScrollExtent, position.maxScrollExtent)
                    .toDouble();
            _stageScrollController.jumpTo(nextOffset);
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: Scrollbar(
              controller: _stageScrollController,
              thumbVisibility: true,
              child: ReorderableListView.builder(
                scrollController: _stageScrollController,
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                itemCount: displayedStages.length,
                proxyDecorator: (child, index, animation) => child,
                onReorder: (oldIndex, newIndex) async {
                  if (!widget.canEdit) {
                    return;
                  }
                  if (oldIndex < 0 ||
                      oldIndex >= displayedStages.length ||
                      newIndex < 0 ||
                      newIndex > displayedStages.length) {
                    return;
                  }
                  final items = List<KanbanStage>.from(displayedStages);
                  if (oldIndex < newIndex) newIndex -= 1;
                  final item = items.removeAt(oldIndex);
                  items.insert(newIndex, item);
                  setState(() => _optimisticStages = items);
                  try {
                    await ref
                        .read(kanbanRepositoryProvider)
                        .reorderStages(items.map((s) => s.id).toList());
                    await Future<void>.delayed(
                      const Duration(milliseconds: 250),
                    );
                    if (!mounted) {
                      return;
                    }
                    setState(() => _optimisticStages = null);
                    invalidateBoard(ref, widget.boardId);
                  } catch (error) {
                    if (!context.mounted) {
                      return;
                    }
                    setState(() => _optimisticStages = null);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          friendlyErrorMessage(
                            error,
                            fallback: 'Could not move that stage.',
                          ),
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (context, index) {
                  final stage = displayedStages[index];
                  return Padding(
                    key: ValueKey(stage.id),
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: 312,
                      child: _KanbanColumn(
                        boardId: widget.boardId,
                        canEdit: widget.canEdit,
                        reorderIndex: index,
                        stage: stage,
                      ),
                    ),
                  );
                },
                footer:
                    widget.boardId == demoBoardId || !widget.canEdit
                        ? null
                        : _AddStageButton(
                          key: ValueKey('add-stage-${widget.boardId}'),
                          boardId: widget.boardId,
                        ),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, _) => Center(
            child: Text(
              friendlyErrorMessage(error, fallback: 'Could not load stages.'),
            ),
          ),
    );
  }
}

class _AllTasksByBoard extends ConsumerStatefulWidget {
  const _AllTasksByBoard();

  @override
  ConsumerState<_AllTasksByBoard> createState() => _AllTasksByBoardState();
}

class _AllTasksByBoardState extends ConsumerState<_AllTasksByBoard> {
  final _boardScrollController = ScrollController();

  @override
  void dispose() {
    _boardScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardsValue = ref.watch(allBoardsProvider);
    final tasksValue = ref.watch(allTasksProvider);

    final boards =
        boardsValue.valueOrNull
            ?.where((board) => board.id != demoBoardId)
            .toList();
    final tasks = tasksValue.valueOrNull;

    if (boards == null && boardsValue.hasError) {
      return Center(
        child: Text(
          friendlyErrorMessage(
            boardsValue.error!,
            fallback: 'Could not load boards.',
          ),
        ),
      );
    }

    if (tasks == null && tasksValue.hasError) {
      return Center(
        child: Text(
          friendlyErrorMessage(
            tasksValue.error!,
            fallback: 'Could not load tasks.',
          ),
        ),
      );
    }

    if (boards == null || tasks == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final projectBoards =
        boards.where((board) => board.isProject).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    if (projectBoards.isEmpty) {
      return const Center(child: Text('No project boards yet.'));
    }

    final projectBoardIds = projectBoards.map((board) => board.id).toSet();
    final tasksByBoard = <String, List<KanbanTask>>{};
    for (final task in tasks.where(
      (task) => projectBoardIds.contains(task.boardId),
    )) {
      tasksByBoard.putIfAbsent(task.boardId, () => []).add(task);
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent ||
            !_boardScrollController.hasClients) {
          return;
        }

        final position = _boardScrollController.position;
        final nextOffset =
            (_boardScrollController.offset + event.scrollDelta.dy)
                .clamp(position.minScrollExtent, position.maxScrollExtent)
                .toDouble();
        _boardScrollController.jumpTo(nextOffset);
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: Scrollbar(
          controller: _boardScrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _boardScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
            itemCount: projectBoards.length,
            itemBuilder: (context, index) {
              final board = projectBoards[index];
              final boardTasks = tasksByBoard[board.id] ?? const [];
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: SizedBox(
                  width: 340,
                  child: _BoardTaskColumn(board: board, tasks: boardTasks),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BoardTaskColumn extends ConsumerWidget {
  const _BoardTaskColumn({required this.board, required this.tasks});

  final KanbanBoard board;
  final List<KanbanTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit = ref.watch(canEditBoardProvider(board.id)).value ?? false;
    final sortedTasks = [...tasks]..sort((a, b) {
      final statusOrder = a.status.compareTo(b.status);
      if (statusOrder != 0) {
        return statusOrder;
      }
      return TaskPriority.compareTasks(a, b);
    });

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    board.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _TaskCountPill(count: sortedTasks.length),
              ],
            ),
            if (board.description?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                board.description!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child:
                  sortedTasks.isEmpty
                      ? Center(
                        child: Text(
                          'No tasks in this board.',
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.only(top: 2, bottom: 2),
                        itemCount: sortedTasks.length,
                        separatorBuilder:
                            (context, index) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final task = sortedTasks[index];
                          return _TaskCard(
                            task: task,
                            canEdit: canEdit,
                            draggable: false,
                            onTap:
                                () => _showTaskDetails(
                                  context: context,
                                  boardId: board.id,
                                  task: task,
                                  canEdit: canEdit,
                                ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTaskDetails({
    required BuildContext context,
    required String boardId,
    required KanbanTask task,
    required bool canEdit,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder:
          (sheetContext) => _TaskDetailsSheet(
            task: task,
            canEdit: canEdit,
            onEdit: () {
              Navigator.of(sheetContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) {
                  return;
                }

                _showTaskEditor(
                  context: context,
                  boardId: boardId,
                  initialStatus: task.status,
                  task: task,
                  canEdit: canEdit,
                );
              });
            },
          ),
    );
  }

  void _showTaskEditor({
    required BuildContext context,
    required String boardId,
    required String initialStatus,
    KanbanTask? task,
    bool canEdit = true,
  }) {
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
            initialStatus: initialStatus,
            task: task,
            canEdit: canEdit,
          ),
    );
  }
}

class _TaskCountPill extends StatelessWidget {
  const _TaskCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _KanbanColumn extends ConsumerWidget {
  const _KanbanColumn({
    required this.boardId,
    required this.canEdit,
    required this.reorderIndex,
    required this.stage,
  });

  final String boardId;
  final bool canEdit;
  final int reorderIndex;
  final KanbanStage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksValue = ref.watch(
      tasksForStatusProvider(
        TasksForStatusRequest(boardId: boardId, status: stage.name),
      ),
    );

    return DragTarget<KanbanTask>(
      onWillAcceptWithDetails: (_) => canEdit,
      onAcceptWithDetails: (details) async {
        if (!canEdit) {
          return;
        }
        await ref
            .read(kanbanRepositoryProvider)
            .moveTask(taskId: details.data.id, status: stage.name);
        invalidateBoard(ref, boardId);
      },
      builder: (context, candidateData, rejectedData) {
        final colorScheme = Theme.of(context).colorScheme;
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color:
                isHovering
                    ? colorScheme.primaryContainer.withValues(alpha: 0.38)
                    : colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color:
                  isHovering ? colorScheme.primary : colorScheme.outlineVariant,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 0, 14),
                child: Row(
                  children: [
                    _StatusDot(colorValue: stage.colorValue, label: stage.name),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stage.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (boardId != demoBoardId && canEdit)
                      ReorderableDragStartListener(
                        index: reorderIndex,
                        child: Tooltip(
                          message: 'Move stage',
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (boardId != demoBoardId && canEdit) ...[
                      IconButton(
                        // Add task button
                        tooltip: 'Add task',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_rounded),
                        onPressed:
                            () => _showTaskEditor(
                              context: context,
                              boardId: boardId,
                              initialStatus: stage.name,
                            ),
                      ),
                      // Stage options menu
                      PopupMenuButton<void>(
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                        itemBuilder:
                            (context) => [
                              PopupMenuItem(
                                child: const Text('Rename Stage'),
                                onTap:
                                    () => _showRenameStageDialog(
                                      context,
                                      ref,
                                      stage,
                                    ),
                              ),
                              PopupMenuItem(
                                // TODO: Add confirmation dialog for deleting stages with tasks
                                child: const Text('Remove Stage'),
                                onTap: () async {
                                  await ref
                                      .read(kanbanRepositoryProvider)
                                      .deleteStage(stage.id);
                                  invalidateBoard(ref, boardId);
                                },
                              ),
                            ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: tasksValue.when(
                  data:
                      (tasks) => ListView.separated(
                        padding: const EdgeInsets.only(top: 2, bottom: 2),
                        itemCount: tasks.length,
                        separatorBuilder:
                            (context, index) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final taskCanEdit =
                              boardId == demoBoardId
                                  ? ref
                                          .watch(
                                            canEditBoardProvider(task.boardId),
                                          )
                                          .value ??
                                      false
                                  : canEdit;

                          return _TaskCard(
                            task: task,
                            onTap:
                                () => _showTaskDetails(
                                  context: context,
                                  boardId: task.boardId,
                                  task: task,
                                  canEdit: taskCanEdit,
                                ),
                            canEdit: taskCanEdit,
                          );
                        },
                      ),
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, stackTrace) => Center(
                        child: Text(
                          friendlyErrorMessage(
                            error,
                            fallback: 'Could not load tasks.',
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTaskEditor({
    required BuildContext context,
    required String boardId,
    required String initialStatus,
    KanbanTask? task,
    bool initialVoiceMode = false,
    bool canEdit = true,
  }) {
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
            initialStatus: initialStatus,
            task: task,
            initialVoiceMode: initialVoiceMode,
            canEdit: canEdit,
          ),
    );
  }

  void _showTaskDetails({
    required BuildContext context,
    required String boardId,
    required KanbanTask task,
    required bool canEdit,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder:
          (sheetContext) => _TaskDetailsSheet(
            task: task,
            canEdit: canEdit,
            onEdit: () {
              Navigator.of(sheetContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) {
                  return;
                }

                _showTaskEditor(
                  context: context,
                  boardId: boardId,
                  initialStatus: task.status,
                  task: task,
                  canEdit: canEdit,
                );
              });
            },
          ),
    );
  }

  void _showRenameStageDialog(
    BuildContext context,
    WidgetRef ref,
    KanbanStage stage,
  ) {
    final controller = TextEditingController(text: stage.name);
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rename Stage'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'New Stage Name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final newName = controller.text.trim();
                  if (newName.isNotEmpty && newName != stage.name) {
                    final stages =
                        ref.read(stagesProvider(boardId)).value ?? const [];
                    final duplicate = stages.any(
                      (existingStage) =>
                          existingStage.id != stage.id &&
                          existingStage.name.trim().toLowerCase() ==
                              newName.toLowerCase(),
                    );
                    if (duplicate) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'A stage with that name already exists in this board.',
                          ),
                          backgroundColor: Colors.red.shade700,
                        ),
                      );
                      return;
                    }

                    try {
                      await ref
                          .read(kanbanRepositoryProvider)
                          .updateStageName(
                            stageId: stage.id,
                            oldName: stage.name,
                            newName: newName,
                            boardId: boardId,
                          );
                      invalidateBoard(ref, boardId);
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
                                fallback: 'Could not rename that stage.',
                              ),
                            ),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text('Rename'),
              ),
            ],
          ),
    );
  }
}

class _AddStageButton extends ConsumerWidget {
  const _AddStageButton({required this.boardId, super.key});
  final String boardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: IconButton(
        onPressed: () => _showAddStageDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        tooltip: 'Add Stage',
      ),
    );
  }

  void _showAddStageDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('New Stage'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Stage Name'),
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
                    final stages =
                        ref.read(stagesProvider(boardId)).value ?? const [];
                    final duplicate = stages.any(
                      (stage) =>
                          stage.name.trim().toLowerCase() == name.toLowerCase(),
                    );
                    if (duplicate) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'A stage with that name already exists in this board.',
                          ),
                          backgroundColor: Colors.red.shade700,
                        ),
                      );
                      return;
                    }

                    try {
                      await ref
                          .read(kanbanRepositoryProvider)
                          .createStage(boardId: boardId, name: name);
                      invalidateBoard(ref, boardId);
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
                                fallback: 'Could not add that stage.',
                              ),
                            ),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }
}

class _TaskDetailsSheet extends ConsumerStatefulWidget {
  const _TaskDetailsSheet({
    required this.task,
    required this.canEdit,
    required this.onEdit,
  });

  final KanbanTask task;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  ConsumerState<_TaskDetailsSheet> createState() => _TaskDetailsSheetState();
}

class _TaskDetailsSheetState extends ConsumerState<_TaskDetailsSheet> {
  bool _overviewExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(kanbanRepositoryProvider)
          .markNotificationsRead(
            boardId: widget.task.boardId,
            taskId: widget.task.id,
          );
      ref.invalidate(notificationsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final canEdit = widget.canEdit;
    final boards = ref.watch(allBoardsProvider).value ?? const [];
    final members = ref.watch(boardMembersProvider(task.boardId)).value ?? [];
    final commentsValue = ref.watch(taskCommentsProvider(task.id));
    final memberById = {for (final member in members) member.userId: member};
    final boardName = _boardName(boards, task.boardId) ?? 'Board';
    final assignee = _memberName(memberById, task.assigneeId) ?? 'Unassigned';
    final createdBy = _memberName(memberById, task.createdBy);
    final updatedBy = _memberName(memberById, task.updatedBy);
    final description = task.description?.trim();
    final dueAt = task.dueAt;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _TaskDetailChip(
                                  icon: Icons.flag_rounded,
                                  label: task.status,
                                  color: _fallbackStatusColor(task.status),
                                ),
                                _TaskDetailChip(
                                  icon: Icons.priority_high_rounded,
                                  label: TaskPriority.label(task.priority),
                                  color: _priorityColor(task.priority),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              task.title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      if (canEdit)
                        IconButton(
                          tooltip: 'Delete task',
                          color: Theme.of(context).colorScheme.error,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _confirmAndDeleteTask(context, ref),
                        ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _TaskDetailsSection(
                    title: 'Overview',
                    expanded: _overviewExpanded,
                    onExpansionChanged:
                        (expanded) =>
                            setState(() => _overviewExpanded = expanded),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumns = constraints.maxWidth >= 560;
                        final itemWidth =
                            twoColumns
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _TaskMetaTile(
                              width: itemWidth,
                              icon: Icons.folder_open_rounded,
                              label: 'Board',
                              value: boardName,
                            ),
                            _TaskMetaTile(
                              width: itemWidth,
                              icon: Icons.person_outline_rounded,
                              label: 'Assignee',
                              value: assignee,
                            ),
                            _TaskMetaTile(
                              width: itemWidth,
                              icon: Icons.event_rounded,
                              label: 'Due',
                              value:
                                  dueAt == null
                                      ? 'No due date'
                                      : _formatTaskDate(dueAt),
                            ),
                            _TaskMetaTile(
                              width: itemWidth,
                              icon: Icons.calendar_today_rounded,
                              label: 'Created',
                              value: _formatTaskDateTime(task.createdAt),
                            ),
                            _TaskMetaTile(
                              width: itemWidth,
                              icon: Icons.update_rounded,
                              label: 'Updated',
                              value: _formatTaskDateTime(task.updatedAt),
                            ),
                            if (createdBy != null)
                              _TaskMetaTile(
                                width: itemWidth,
                                icon: Icons.person_add_alt_1_rounded,
                                label: 'Created by',
                                value: createdBy,
                              ),
                            if (updatedBy != null)
                              _TaskMetaTile(
                                width: itemWidth,
                                icon: Icons.manage_accounts_rounded,
                                label: 'Updated by',
                                value: updatedBy,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _TaskDetailsSection(
                    title: 'Description',
                    child: DriveLinkPreviewBlock(
                      text: description,
                      emptyText: 'No description.',
                      linksValue: ref.watch(driveLinksForTaskProvider(task.id)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _TaskDetailsSection(
                    title: 'Images',
                    child:
                        task.attachmentUrls.isEmpty
                            ? Text(
                              'No images attached.',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            )
                            : Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children:
                                  task.attachmentUrls
                                      .map(
                                        (url) => ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.network(
                                            url,
                                            width: 132,
                                            height: 132,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                  ),
                  const SizedBox(height: 14),
                  _TaskDetailsSection(
                    title: 'Comments',
                    child: commentsValue.when(
                      loading:
                          () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: LinearProgressIndicator(),
                          ),
                      error:
                          (error, _) => Text(
                            friendlyErrorMessage(
                              error,
                              fallback: 'Could not load comments.',
                            ),
                          ),
                      data: (comments) {
                        if (comments.isEmpty) {
                          return Text(
                            'No comments yet.',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          );
                        }

                        return Column(
                          children: [
                            for (var i = 0; i < comments.length; i++) ...[
                              _TaskCommentTile(
                                body: comments[i].body,
                                author:
                                    comments[i].authorEmail ??
                                    _memberName(
                                      memberById,
                                      comments[i].authorId,
                                    ) ??
                                    'Collaborator',
                                createdAt: comments[i].createdAt,
                              ),
                              if (i != comments.length - 1)
                                const Divider(height: 18),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (canEdit)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Edit Task'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteTask(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final task = widget.task;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete task?'),
            content: Text(
              'This will permanently delete "${task.title}" and its comments.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref.read(kanbanRepositoryProvider).deleteTask(task.id);
      invalidateBoard(ref, task.boardId);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detailedErrorMessage(
                error,
                fallback: 'Could not delete this task.',
              ),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  String? _memberName(Map<String, KanbanBoardMember> members, String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    return members[id]?.displayLabel;
  }

  String? _boardName(List<KanbanBoard> boards, String id) {
    for (final board in boards) {
      if (board.id == id) {
        return board.name;
      }
    }
    return null;
  }
}

class _TaskDetailChip extends StatelessWidget {
  const _TaskDetailChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor:
          color == null
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : color!.withValues(alpha: 0.12),
      side: BorderSide.none,
      labelStyle: color == null ? null : TextStyle(color: color),
    );
  }
}

class _TaskDetailsSection extends StatelessWidget {
  const _TaskDetailsSection({
    required this.title,
    required this.child,
    this.expanded,
    this.onExpansionChanged,
  });

  final String title;
  final Widget child;
  final bool? expanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final isCollapsible = expanded != null && onExpansionChanged != null;
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap:
                    isCollapsible
                        ? () => onExpansionChanged!(!expanded!)
                        : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (isCollapsible)
                      Icon(
                        expanded!
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              if (!isCollapsible || expanded!) ...[
                const SizedBox(height: 12),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskMetaTile extends StatelessWidget {
  const _TaskMetaTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCommentTile extends StatelessWidget {
  const _TaskCommentTile({
    required this.body,
    required this.author,
    required this.createdAt,
  });

  final String body;
  final String author;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    author,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _formatTaskDateTime(createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Color _fallbackStatusColor(String label) {
  return switch (label.toLowerCase()) {
    'to do' => const Color(0xFF5E6AD2),
    'in progress' => const Color(0xFFB26A00),
    'done' => const Color(0xFF1B7F5A),
    _ => Colors.blueGrey,
  };
}

Color _priorityColor(String priority) {
  return switch (TaskPriority.normalize(priority)) {
    TaskPriority.low => const Color(0xFF5D7A66),
    TaskPriority.medium => const Color(0xFF3867B7),
    TaskPriority.high => const Color(0xFFB26A00),
    TaskPriority.urgent => const Color(0xFFC62828),
    _ => const Color(0xFF3867B7),
  };
}

String _formatTaskDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day}/${local.year} $hour:$minute';
}

String _formatTaskDate(DateTime value) {
  final local = value.toLocal();
  return '${local.month}/${local.day}/${local.year}';
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({this.colorValue, required this.label});
  final int? colorValue;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorValue != null ? Color(colorValue!) : _fallbackColor(label),
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 10),
    );
  }

  Color _fallbackColor(String label) {
    return switch (label.toLowerCase()) {
      'to do' => const Color(0xFF5E6AD2),
      'in progress' => const Color(0xFFB26A00),
      'done' => const Color(0xFF1B7F5A),
      _ => Colors.blueGrey,
    };
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onTap,
    required this.canEdit,
    this.draggable,
  });

  final KanbanTask task;
  final VoidCallback onTap;
  final bool canEdit;
  final bool? draggable;

  @override
  Widget build(BuildContext context) {
    final visibleDescription = GoogleDriveUrlParser.removeDriveUrls(
      task.description ?? '',
    );
    final hasDescription = visibleDescription.isNotEmpty;
    final dueAt = task.dueAt;
    final isOverdue =
        dueAt != null &&
        DateTime(dueAt.year, dueAt.month, dueAt.day).isBefore(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );
    final canDrag = draggable ?? canEdit;
    final colorScheme = Theme.of(context).colorScheme;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _TaskBadge(
                            label: task.status,
                            color: _fallbackColor(task.status),
                          ),
                          _TaskBadge(
                            label: TaskPriority.label(task.priority),
                            color: _priorityColor(task.priority),
                            icon: Icons.flag_rounded,
                          ),
                        ],
                      ),
                    ),
                    if (canDrag) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Long-press and drag to move',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  task.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasDescription) ...[
                  const SizedBox(height: 10),
                  Text(
                    visibleDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
                if (dueAt != null || task.attachmentUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (dueAt != null)
                        _TaskMiniChip(
                          icon: Icons.event_rounded,
                          label: DateFormat('MMM d').format(dueAt),
                          color:
                              isOverdue
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                        ),
                      if (task.attachmentUrls.isNotEmpty)
                        _TaskMiniChip(
                          icon: Icons.image_outlined,
                          label: '${task.attachmentUrls.length}',
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                    ],
                  ),
                ],
                if (task.updatedAt != task.createdAt) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: Color(0xFF9E9E9E),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Updated ${DateFormat('MMM d').format(task.updatedAt)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: const Color(0xFF9E9E9E)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!canDrag) {
      return card;
    }

    return LongPressDraggable<KanbanTask>(
      data: task,
      feedback: SizedBox(
        width: 260,
        child: Opacity(opacity: 0.92, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }

  Color _fallbackColor(String label) {
    return switch (label.toLowerCase()) {
      'to do' => const Color(0xFF5E6AD2),
      'in progress' => const Color(0xFFB26A00),
      'done' => const Color(0xFF1B7F5A),
      _ => Colors.blueGrey,
    };
  }
}

class _TaskBadge extends StatelessWidget {
  const _TaskBadge({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskMiniChip extends StatelessWidget {
  const _TaskMiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
