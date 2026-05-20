import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/utils/debug_rebuild_counter.dart';
import '../../../core/utils/friendly_error_message.dart';
import '../../ai_control/data/ai_control_providers.dart';
import '../../ai_control/data/on_device_llm_task_command_service.dart';
import '../../ai_control/domain/ai_task_command.dart';
import '../../auth/data/auth_providers.dart';
import '../data/kanban_providers.dart';
import '../domain/kanban_repository.dart';
import '../domain/kanban_task.dart';

class TaskEditorSheet extends ConsumerStatefulWidget {
  const TaskEditorSheet({
    super.key,
    required this.boardId,
    required this.initialStatus,
    this.task,
    this.initialVoiceMode = false,
    this.canEdit = true,
  });

  final String boardId;
  final String initialStatus;
  final KanbanTask? task;
  final bool initialVoiceMode;
  final bool canEdit;

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _commentController = TextEditingController();
  final _aiController = TextEditingController();
  late String _status;
  late String _priority;
  String? _assigneeId;
  DateTime? _dueAt;
  late List<String> _attachmentUrls;
  bool _postingComment = false;
  bool _saving = false;
  bool _deleting = false;
  bool _runningAi = false;
  bool _uploadingAttachment = false;
  final _speechToText = SpeechToText();
  bool _isListening = false;

  bool get _isEditing => widget.task != null;
  bool get _canModify => widget.canEdit;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    _status = task == null ? widget.initialStatus : task.status;
    _priority = TaskPriority.normalize(task?.priority);
    _assigneeId = task?.assigneeId;
    _dueAt = task?.dueAt;
    _attachmentUrls = List<String>.from(task?.attachmentUrls ?? const []);

    if (widget.initialVoiceMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleListening());
    }

    if (task != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref
            .read(kanbanRepositoryProvider)
            .markNotificationsRead(boardId: widget.boardId, taskId: task.id);
        ref.invalidate(notificationsProvider);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _commentController.dispose();
    _aiController.dispose();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (!_canModify || title.isEmpty || _saving) return;

    setState(() => _saving = true);
    final repository = ref.read(kanbanRepositoryProvider);

    if (_isEditing) {
      final canOverwrite = await _confirmOverwriteIfChanged(repository);
      if (!canOverwrite) {
        if (mounted) {
          setState(() => _saving = false);
        }
        return;
      }

      await repository.updateTask(
        taskId: widget.task!.id,
        title: title,
        description: description,
        status: _status,
        priority: _priority,
        assigneeId: _assigneeId ?? '',
        dueAt: _dueAt,
        clearDueAt: _dueAt == null,
        attachmentUrls: _attachmentUrls,
      );
    } else {
      await repository.createTask(
        boardId: widget.boardId,
        title: title,
        description: description,
        status: _status,
        priority: _priority,
        assigneeId: _assigneeId,
        dueAt: _dueAt,
      );
    }
    invalidateBoardTaskSideEffects(ref, widget.boardId);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmOverwriteIfChanged(KanbanRepository repository) async {
    final originalTask = widget.task;
    if (originalTask == null) {
      return true;
    }

    final tasks = await repository.listTasks(originalTask.boardId);
    KanbanTask? latestTask;
    for (final task in tasks) {
      if (task.id == originalTask.id) {
        latestTask = task;
        break;
      }
    }

    if (latestTask == null ||
        !latestTask.updatedAt.isAfter(originalTask.updatedAt)) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final overwrite = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Task changed'),
            content: const Text(
              'Someone else updated this task after you opened it. Save your changes anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Review'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
    );

    return overwrite ?? false;
  }

  Future<void> _deleteTask() async {
    final task = widget.task;
    if (!_canModify || task == null || _deleting || _saving) {
      return;
    }

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

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _deleting = true);
    try {
      await ref.read(kanbanRepositoryProvider).deleteTask(task.id);
      invalidateBoardTaskSideEffects(ref, widget.boardId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          detailedErrorMessage(error, fallback: 'Could not delete this task.'),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _pickDueDate() async {
    if (!_canModify) {
      return;
    }

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _dueAt = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _uploadAttachment() async {
    final task = widget.task;
    if (!_canModify || task == null || _uploadingAttachment) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }

    setState(() => _uploadingAttachment = true);
    try {
      final repository = ref.read(kanbanRepositoryProvider);
      final url = await repository.uploadTaskAttachment(
        boardId: widget.boardId,
        taskId: task.id,
        fileName: file.name,
        bytes: bytes,
        contentType: _imageContentType(file.extension),
      );
      final nextUrls = [..._attachmentUrls, url];
      await repository.updateTask(taskId: task.id, attachmentUrls: nextUrls);
      if (!mounted) {
        return;
      }
      setState(() => _attachmentUrls = nextUrls);
      invalidateBoardTaskSideEffects(ref, widget.boardId);
    } catch (error) {
      if (mounted) {
        _showMessage(
          detailedErrorMessage(error, fallback: 'Could not upload that image.'),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAttachment = false);
      }
    }
  }

  Future<void> _removeAttachment(String url) async {
    final task = widget.task;
    if (!_canModify || task == null || _saving || _uploadingAttachment) {
      return;
    }

    final nextUrls = _attachmentUrls.where((item) => item != url).toList();
    setState(() => _attachmentUrls = nextUrls);
    await ref
        .read(kanbanRepositoryProvider)
        .updateTask(taskId: task.id, attachmentUrls: nextUrls);
    invalidateBoardTaskSideEffects(ref, widget.boardId);
  }

  Future<void> _runAiOnTask() async {
    final task = widget.task;
    final instruction = _aiController.text.trim();
    if (_isCommandHelpRequest(instruction)) {
      _showTaskCommandHelp();
      return;
    }
    if (!_canModify ||
        task == null ||
        instruction.isEmpty ||
        _runningAi ||
        _saving ||
        _deleting) {
      return;
    }

    setState(() => _runningAi = true);
    try {
      final stages = await ref
          .read(kanbanRepositoryProvider)
          .listStages(widget.boardId);
      final command = await ref
          .read(onDeviceLlmTaskCommandServiceProvider)
          .planSingleTaskCommand(
            instruction: instruction,
            task: KanbanTask(
              id: task.id,
              boardId: task.boardId,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim(),
              status: _status,
              priority: _priority,
              sortOrder: task.sortOrder,
              createdAt: task.createdAt,
              updatedAt: task.updatedAt,
              assigneeId: _assigneeId,
              createdBy: task.createdBy,
              updatedBy: task.updatedBy,
              dueAt: _dueAt,
              attachmentUrls: _attachmentUrls,
            ),
            stages: stages.map((stage) => stage.name).toList(),
          );

      if (!mounted) return;

      switch (command.type) {
        case AiTaskCommandType.move:
          if (command.status != null &&
              stages.any((stage) => stage.name == command.status)) {
            setState(() => _status = command.status!);
          }
          break;
        case AiTaskCommandType.edit:
          if (command.title != null && command.title!.isNotEmpty) {
            _titleController.text = command.title!;
          }
          if (command.description != null) {
            _descriptionController.text = command.description!;
          }
          if (command.status != null &&
              stages.any((stage) => stage.name == command.status)) {
            setState(() => _status = command.status!);
          }
          break;
        case AiTaskCommandType.clearDescription:
          _descriptionController.clear();
          break;
        case AiTaskCommandType.delete:
          await ref.read(kanbanRepositoryProvider).deleteTask(task.id);
          invalidateBoardTaskSideEffects(ref, widget.boardId);
          if (mounted) Navigator.of(context).pop();
          break;
        case AiTaskCommandType.createBoard:
        case AiTaskCommandType.renameBoard:
        case AiTaskCommandType.addStage:
        case AiTaskCommandType.openTask:
        case AiTaskCommandType.openBoard:
        case AiTaskCommandType.create:
        case AiTaskCommandType.createMany:
        case AiTaskCommandType.batch:
        case AiTaskCommandType.unknown:
          throw const AiCommandException(
            'AI returned an unsupported task action.',
          );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              fallback: 'Could not run that AI command.',
            ),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _runningAi = false);
      }
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechToText.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }

    final available = await _speechToText.initialize();
    if (!available || !mounted) {
      _showMessage(
        'Microphone permission is required for spoken commands.',
        isError: true,
      );
      return;
    }

    setState(() => _isListening = true);
    await _speechToText.listen(
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        if (!result.finalResult) {
          _aiController.text = result.recognizedWords;
          return;
        }
        _handleFinalTranscript(result.recognizedWords);
      },
    );
  }

  Future<void> _handleFinalTranscript(String transcript) async {
    await _speechToText.stop();
    if (!mounted) {
      return;
    }

    _aiController.text = transcript;
    _aiController.selection = TextSelection.collapsed(
      offset: transcript.length,
    );
    setState(() => _isListening = false);
    await _runAiOnTask();
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  void _showTaskCommandHelp() {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Task Commands'),
            content: const SingleChildScrollView(
              child: Text(
                'These commands apply to the open task:\n'
                '\n'
                '/description Description text\n'
                '/addDescription Description text\n'
                '/setDescription Description text\n'
                '/clearDescription\n'
                '/move Done\n'
                '/rename New task title\n'
                '/delete\n'
                '\n'
                'Use /commands or /help from the board command sheet to see board, project, and stage commands.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Future<void> _addComment() async {
    final task = widget.task;
    final body = _commentController.text.trim();
    if (!_canModify || task == null || body.isEmpty || _postingComment) {
      return;
    }

    setState(() => _postingComment = true);
    try {
      await ref
          .read(kanbanRepositoryProvider)
          .addTaskComment(boardId: widget.boardId, taskId: task.id, body: body);
      _commentController.clear();
      ref.invalidate(taskCommentsProvider(task.id));
      ref.invalidate(boardActivityProvider(widget.boardId));
    } catch (error) {
      if (mounted) {
        _showMessage(
          friendlyErrorMessage(error, fallback: 'Could not add that comment.'),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _postingComment = false);
      }
    }
  }

  Future<void> _deleteComment(KanbanTaskComment comment) async {
    if (!_canModify) {
      return;
    }
    await ref.read(kanbanRepositoryProvider).deleteTaskComment(comment.id);
    ref.invalidate(taskCommentsProvider(comment.taskId));
  }

  @override
  Widget build(BuildContext context) {
    DebugRebuildCounter.mark(
      'TaskEditorSheet:${widget.task?.id ?? 'new'}',
      logEvery: 5,
    );

    final stages = ref.watch(stagesProvider(widget.boardId)).value ?? [];
    final statusOptions =
        {_status, ...stages.map((stage) => stage.name)}.toList();
    final members = ref.watch(boardMembersProvider(widget.boardId)).value ?? [];
    final memberById = {for (final member in members) member.userId: member};
    final commentsValue =
        _isEditing ? ref.watch(taskCommentsProvider(widget.task!.id)) : null;
    final currentUser = ref.watch(currentUserProvider);
    final task = widget.task;
    final createdBy = _memberEmail(memberById, task?.createdBy);
    final updatedBy = _memberEmail(memberById, task?.updatedBy);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing
                          ? _canModify
                              ? 'Edit Task'
                              : 'View Task'
                          : 'Add Task',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isEditing && _canModify)
                    IconButton(
                      tooltip: 'Delete task',
                      color: Theme.of(context).colorScheme.error,
                      onPressed: _deleting || _saving ? null : _deleteTask,
                      icon:
                          _deleting
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.delete_outline_rounded),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _TaskEditorSection(
                title: 'Details',
                children: [
                  TextField(
                    controller: _titleController,
                    autofocus: _canModify,
                    readOnly: !_canModify,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    readOnly: !_canModify,
                    minLines: 6,
                    maxLines: 10,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'Description',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _TaskEditorSection(
                title: 'Workflow',
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: InputDecoration(
                      labelText: 'Stage',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items:
                        statusOptions
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(
                                  status,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged:
                        _canModify
                            ? (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() => _status = value);
                            }
                            : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: InputDecoration(
                      labelText: 'Priority',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items:
                        TaskPriority.values
                            .map(
                              (priority) => DropdownMenuItem(
                                value: priority,
                                child: Text(TaskPriority.label(priority)),
                              ),
                            )
                            .toList(),
                    onChanged:
                        _canModify
                            ? (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _priority = TaskPriority.normalize(value);
                              });
                            }
                            : null,
                  ),
                  if (members.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue:
                          members.any((member) => member.userId == _assigneeId)
                              ? _assigneeId
                              : '',
                      decoration: InputDecoration(
                        labelText: 'Assignee',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Unassigned'),
                        ),
                        ...members.map(
                          (member) => DropdownMenuItem(
                            value: member.userId,
                            child: Text(
                              member.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged:
                          _canModify
                              ? (value) {
                                setState(() {
                                  _assigneeId =
                                      value == null || value.isEmpty
                                          ? null
                                          : value;
                                });
                              }
                              : null,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _canModify ? _pickDueDate : null,
                          icon: const Icon(Icons.event_rounded),
                          label: Text(
                            _dueAt == null
                                ? 'Set due date'
                                : 'Due ${_formatDate(_dueAt!)}',
                          ),
                        ),
                      ),
                      if (_dueAt != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Clear due date',
                          onPressed:
                              _canModify
                                  ? () => setState(() => _dueAt = null)
                                  : null,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _TaskAttachmentsEditor(
                urls: _attachmentUrls,
                canEdit: _canModify && _isEditing,
                uploading: _uploadingAttachment,
                onUpload: _uploadAttachment,
                onRemove: _removeAttachment,
              ),
              if (!_isEditing) const SizedBox(height: 18),
              if (_isEditing) ...[
                const SizedBox(height: 18),
                _TaskEditorSection(
                  title: 'Activity',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TaskInfoChip(
                          icon: Icons.calendar_today_rounded,
                          label:
                              'Created ${_formatDateTime(widget.task!.createdAt)}',
                        ),
                        _TaskInfoChip(
                          icon: Icons.update_rounded,
                          label:
                              'Updated ${_formatDateTime(widget.task!.updatedAt)}',
                        ),
                        if (createdBy != null)
                          _TaskInfoChip(
                            icon: Icons.person_add_alt_1_rounded,
                            label: 'Created by $createdBy',
                          ),
                        if (updatedBy != null)
                          _TaskInfoChip(
                            icon: Icons.manage_accounts_rounded,
                            label: 'Last updated by $updatedBy',
                          ),
                      ],
                    ),
                  ],
                ),
                if (_canModify && FeatureFlags.offlineAiEnabled) ...[
                  const SizedBox(height: 18),
                  TextField(
                    controller: _aiController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Offline AI for this task',
                      hintText: '/addDescription Details, /move Done, /delete',
                      filled: true,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip:
                                _isListening
                                    ? 'Stop listening'
                                    : 'Voice command',
                            icon: Icon(
                              _isListening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                            ),
                            color:
                                _isListening
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                            onPressed:
                                _runningAi || _saving || _deleting
                                    ? null
                                    : _toggleListening,
                          ),
                          IconButton(
                            tooltip: 'Run offline AI',
                            icon:
                                _runningAi
                                    ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.auto_awesome_rounded),
                            onPressed: _runningAi ? null : _runAiOnTask,
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _runAiOnTask(),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'Comments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                commentsValue!.when(
                  loading:
                      () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      ),
                  error:
                      (error, _) => Text(
                        friendlyErrorMessage(
                          error,
                          fallback: 'Could not load comments.',
                        ),
                      ),
                  data:
                      (comments) => Column(
                        children: [
                          if (comments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('No comments yet.'),
                              ),
                            ),
                          ...comments.map((comment) {
                            final author =
                                comment.authorEmail ??
                                memberById[comment.authorId]?.displayLabel ??
                                'Collaborator';
                            final canDelete =
                                _canModify &&
                                comment.authorId == currentUser?.id;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                child: Icon(Icons.chat_bubble_outline_rounded),
                              ),
                              title: Text(comment.body),
                              subtitle: Text(author),
                              trailing:
                                  canDelete
                                      ? IconButton(
                                        tooltip: 'Delete comment',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                        onPressed:
                                            () => _deleteComment(comment),
                                      )
                                      : null,
                            );
                          }),
                        ],
                      ),
                ),
                if (_canModify) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Add comment',
                      filled: true,
                      suffixIcon: IconButton(
                        tooltip: 'Post comment',
                        icon:
                            _postingComment
                                ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.send_rounded),
                        onPressed: _postingComment ? null : _addComment,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _addComment(),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Viewers can read comments but cannot add new ones.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
              if (_canModify) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving || _deleting ? null : _save,
                    icon:
                        _saving
                            ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Icon(
                              _isEditing
                                  ? Icons.save_rounded
                                  : Icons.add_rounded,
                            ),
                    label: Text(_isEditing ? 'Save Task' : 'Add Task'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _memberEmail(Map<String, KanbanBoardMember> members, String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    return members[id]?.displayLabel;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} $hour:$minute';
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }

  String? _imageContentType(String? extension) {
    return switch (extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => null,
    };
  }
}

class _TaskAttachmentsEditor extends StatelessWidget {
  const _TaskAttachmentsEditor({
    required this.urls,
    required this.canEdit,
    required this.uploading,
    required this.onUpload,
    required this.onRemove,
  });

  final List<String> urls;
  final bool canEdit;
  final bool uploading;
  final VoidCallback onUpload;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
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
                    'Images',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: uploading ? null : onUpload,
                    icon:
                        uploading
                            ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.upload_file_rounded),
                    label: const Text('Upload'),
                  ),
              ],
            ),
            if (!canEdit && urls.isEmpty)
              Text(
                'Save the task before adding images.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (urls.isEmpty)
              Text(
                'No images attached.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    urls
                        .map(
                          (url) => _AttachmentPreview(
                            url: url,
                            canRemove: canEdit,
                            onRemove: () => onRemove(url),
                          ),
                        )
                        .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskEditorSection extends StatelessWidget {
  const _TaskEditorSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.url,
    required this.canRemove,
    required this.onRemove,
  });

  final String url;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Tooltip(
          message: 'Open image',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAttachmentImage(context, url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder:
                    (context, error, stackTrace) => Container(
                      width: 96,
                      height: 96,
                      color: Theme.of(context).colorScheme.surface,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
              ),
            ),
          ),
        ),
        if (canRemove)
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filledTonal(
              tooltip: 'Remove image',
              iconSize: 16,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
      ],
    );
  }
}

void _showAttachmentImage(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder:
        (context) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (context, error, stackTrace) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white,
                            size: 48,
                          ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: IconButton.filledTonal(
                      tooltip: 'Close image',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
  );
}

class _TaskInfoChip extends StatelessWidget {
  const _TaskInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      side: BorderSide.none,
    );
  }
}

bool _isCommandHelpRequest(String instruction) {
  final normalized = instruction.trim().toLowerCase();
  return normalized == '/commands' ||
      normalized == '/help' ||
      normalized == 'commands' ||
      normalized == 'help';
}
