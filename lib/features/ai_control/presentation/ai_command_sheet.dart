import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/utils/friendly_error_message.dart';
import '../../kanban/data/kanban_providers.dart';
import '../../kanban/domain/kanban_task.dart';
import '../../kanban/presentation/task_editor_sheet.dart';
import '../data/ai_control_providers.dart';
import '../domain/ai_task_command.dart';
import '../domain/offline_model_type.dart';

class AiCommandSheet extends ConsumerStatefulWidget {
  const AiCommandSheet({required this.boardId, super.key});

  final String boardId;

  @override
  ConsumerState<AiCommandSheet> createState() => _AiCommandSheetState();
}

class _AiCommandSheetState extends ConsumerState<AiCommandSheet> {
  static const _wakeWord = 'crane';

  final _controller = TextEditingController();
  final _speech = SpeechToText();
  AiMode _mode = AiMode.command;
  bool _running = false;
  bool _listening = false;
  bool _keepListening = false;
  bool _speechRestartScheduled = false;
  bool _hasModel = false;
  bool _canRunSlashCommand = false;
  bool _installingModel = false;
  OfflineModelType _modelType = OfflineModelType.functionGemma;
  String? _analysis;
  String? _chatResponse;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    _refreshModelState();
  }

  @override
  void dispose() {
    _keepListening = false;
    _speech.stop();
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final canRunSlashCommand = _isSlashCommand(_controller.text);
    if (canRunSlashCommand == _canRunSlashCommand || !mounted) {
      return;
    }

    setState(() => _canRunSlashCommand = canRunSlashCommand);
  }

  void _refreshModelState() {
    final service = ref.read(onDeviceLlmTaskCommandServiceProvider);
    _hasModel = service.hasActiveModel;
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      _keepListening = false;
      await _speech.stop();
      if (mounted) {
        setState(() => _listening = false);
      }
      return;
    }

    _keepListening = true;
    await _startListening();
  }

  Future<void> _startListening() async {
    if (_listening || _running || !mounted) {
      return;
    }

    try {
      final available = await _speech.initialize(
        onError: _handleSpeechError,
        onStatus: _handleSpeechStatus,
      );
      if (!available || !mounted) {
        _keepListening = false;
        _showMessage(
          'Microphone permission is required for spoken commands.',
          isError: true,
        );
        return;
      }

      setState(() => _listening = true);
      await _speech.listen(
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 4),
        onResult: (result) {
          if (!mounted) {
            return;
          }
          if (!result.finalResult) {
            _controller.text = result.recognizedWords;
            return;
          }
          _handleFinalTranscript(result.recognizedWords);
        },
      );
    } catch (error) {
      _keepListening = false;
      if (!mounted) {
        return;
      }
      setState(() => _listening = false);
      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: 'Voice listening failed. Please try again.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _handleFinalTranscript(String transcript) async {
    await _speech.stop();
    if (!mounted) {
      return;
    }

    final commandText = _commandAfterWakeWord(transcript);
    if (commandText == null) {
      setState(() => _listening = false);
      await _restartListeningAfterCommand();
      return;
    }
    if (commandText.isEmpty) {
      setState(() {
        _listening = false;
        _controller.clear();
      });
      await _restartListeningAfterCommand();
      return;
    }

    _controller.text = commandText;
    _controller.selection = TextSelection.collapsed(offset: commandText.length);
    setState(() => _listening = false);
    await _submit();
    await _restartListeningAfterCommand();
  }

  String? _commandAfterWakeWord(String transcript) {
    final trimmedTranscript = transcript.trim();
    final normalizedTranscript = trimmedTranscript.toLowerCase();
    if (!normalizedTranscript.startsWith(_wakeWord)) {
      return null;
    }

    final command = trimmedTranscript.substring(_wakeWord.length).trim();
    return command.replaceFirst(RegExp(r'^[,;:\-]\s*'), '').trim();
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    final normalizedStatus = status.toLowerCase();
    final isDone =
        normalizedStatus == 'done' ||
        normalizedStatus == 'notlistening' ||
        normalizedStatus == 'not listening' ||
        normalizedStatus == 'not_listening' ||
        normalizedStatus == 'listeningdone' ||
        normalizedStatus == 'listening done' ||
        normalizedStatus == 'donenoresult' ||
        normalizedStatus == 'done no result';
    if (!isDone) {
      return;
    }

    if (_listening) {
      setState(() => _listening = false);
    }

    if (_keepListening && !_running) {
      _scheduleListeningRestart();
    }
  }

  void _handleSpeechError(Object error) {
    if (!mounted) {
      return;
    }

    if (_listening) {
      setState(() => _listening = false);
    }

    if (_keepListening && !_running) {
      _scheduleListeningRestart();
    }
  }

  void _scheduleListeningRestart() {
    if (_speechRestartScheduled || !mounted) {
      return;
    }

    _speechRestartScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 1200), () async {
      _speechRestartScheduled = false;
      if (!_keepListening || !mounted || _running || _listening || !_hasModel) {
        return;
      }

      await _startListening();
    });
  }

  Future<void> _restartListeningAfterCommand() async {
    if (!_keepListening || !mounted || !_hasModel) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!_keepListening || !mounted || _running || _listening) {
      return;
    }

    await _startListening();
  }

  Future<void> _submit() async {
    final instruction = _controller.text.trim();
    if (instruction.isEmpty || _running) {
      return;
    }
    if (_isCommandHelpRequest(instruction)) {
      _showCommandHelp();
      return;
    }
    if (_mode == AiMode.command && _isBoardChatCommand(instruction)) {
      await _sendBoardChatCommand(instruction);
      return;
    }
    if (!_hasModel &&
        !(_mode == AiMode.command && _isSlashCommand(instruction))) {
      _showMessage('Install an offline AI model first.', isError: true);
      return;
    }

    setState(() => _running = true);
    try {
      final repository = ref.read(kanbanRepositoryProvider);
      final tasks = await repository.listTasks(widget.boardId);
      final stages = await repository.listStages(widget.boardId);
      final stageNames = stages.map((stage) => stage.name).toList();

      if (_mode == AiMode.analysis) {
        final analysis = await ref
            .read(onDeviceLlmTaskCommandServiceProvider)
            .analyzeBoard(
              instruction: instruction,
              tasks: tasks,
              stages: stageNames,
            );

        if (!mounted) {
          return;
        }

        setState(() => _analysis = analysis);
        return;
      }
      if (_mode == AiMode.chat) {
        final response = await ref
            .read(onDeviceLlmTaskCommandServiceProvider)
            .chatWithBoard(
              message: instruction,
              tasks: tasks,
              stages: stageNames,
            );

        if (!mounted) {
          return;
        }

        setState(() {
          _chatResponse = response;
          _controller.clear();
        });
        return;
      }

      final command = await ref
          .read(onDeviceLlmTaskCommandServiceProvider)
          .planCommand(
            boardId: widget.boardId,
            instruction: instruction,
            tasks: tasks,
            stages: stageNames,
          );
      final result = await _handleCommand(command, tasks);

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor:
              result.success ? Colors.black87 : Colors.red.shade700,
        ),
      );

      if (result.success) {
        invalidateKanban(ref, boardId: widget.boardId);
        _controller.clear();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        friendlyErrorMessage(error, fallback: 'Could not run that AI request.'),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Future<AiTaskCommandResult> _handleCommand(
    AiTaskCommand command,
    List<KanbanTask> tasks,
  ) async {
    if (command.type == AiTaskCommandType.batch) {
      var successCount = 0;
      for (final childCommand in command.commands) {
        final result = await _handleCommand(childCommand, tasks);
        if (!result.success) {
          return AiTaskCommandResult(
            success: false,
            message:
                'Ran $successCount of ${command.commands.length} commands. ${result.message}',
          );
        }
        successCount++;
      }

      return AiTaskCommandResult(
        success: true,
        message:
            command.message ??
            'Ran $successCount command${successCount == 1 ? '' : 's'}.',
      );
    }

    if (command.type == AiTaskCommandType.openBoard) {
      return _openBoard(command);
    }

    if (command.type == AiTaskCommandType.openTask) {
      return _openTask(command, tasks);
    }

    return ref.read(aiTaskCommandExecutorProvider).execute(command);
  }

  Future<AiTaskCommandResult> _openBoard(AiTaskCommand command) async {
    final name = command.title?.trim() ?? '';
    if (name.isEmpty) {
      return const AiTaskCommandResult(
        success: false,
        message: 'Tell me which board to open.',
      );
    }

    final boards = await ref.read(kanbanRepositoryProvider).listBoards();
    final board = _findBoardByName(name, boards);
    if (board == null) {
      return AiTaskCommandResult(
        success: false,
        message: 'I could not find a "$name" board.',
      );
    }

    ref.read(selectedBoardIdProvider.notifier).state = board.id;
    _keepListening = false;
    await _speech.stop();
    return AiTaskCommandResult(
      success: true,
      message: 'Opened board "${board.name}".',
    );
  }

  AiTaskCommandResult _openTask(AiTaskCommand command, List<KanbanTask> tasks) {
    final matchingTasks =
        command.taskId.isEmpty
            ? <KanbanTask>[]
            : tasks.where((task) => task.id == command.taskId).toList();
    final task =
        matchingTasks.isNotEmpty
            ? matchingTasks.first
            : _findTaskByTitle(command.title ?? '', tasks);
    if (task == null) {
      final title = command.title?.trim();
      return AiTaskCommandResult(
        success: false,
        message:
            title == null || title.isEmpty
                ? 'Tell me which task to open.'
                : 'I could not find "$title".',
      );
    }

    _showTaskEditor(task);
    return AiTaskCommandResult(
      success: true,
      message: 'Opened "${task.title}".',
    );
  }

  KanbanBoard? _findBoardByName(String name, List<KanbanBoard> boards) {
    final normalizedName = _normalizeForMatch(name);
    for (final board in boards) {
      if (_normalizeForMatch(board.name) == normalizedName) {
        return board;
      }
    }

    for (final board in boards) {
      final normalizedBoard = _normalizeForMatch(board.name);
      if (normalizedBoard.contains(normalizedName) ||
          normalizedName.contains(normalizedBoard)) {
        return board;
      }
    }

    return null;
  }

  KanbanTask? _findTaskByTitle(String title, List<KanbanTask> tasks) {
    final normalizedTitle = _normalizeForMatch(title);
    if (normalizedTitle.isEmpty) {
      return null;
    }

    for (final task in tasks) {
      if (_normalizeForMatch(task.title) == normalizedTitle) {
        return task;
      }
    }

    for (final task in tasks) {
      final normalizedTask = _normalizeForMatch(task.title);
      if (normalizedTask.contains(normalizedTitle) ||
          normalizedTitle.contains(normalizedTask)) {
        return task;
      }
    }

    return null;
  }

  String _normalizeForMatch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _showTaskEditor(KanbanTask task) {
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
            boardId: task.boardId,
            initialStatus: task.status,
            task: task,
            canEdit:
                ref.read(canEditBoardProvider(task.boardId)).value ?? false,
          ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.black87,
      ),
    );
  }

  void _showCommandHelp() {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Commands'),
            content: const SingleChildScrollView(
              child: Text(
                'Board commands\n'
                '/create Task name\n'
                '/create task Task name\n'
                '/add Task name\n'
                '/new Task name\n'
                '/create tasks Task one, Task two\n'
                '/move Task name to Done\n'
                '/addDescription Task name: Description text\n'
                '/chat Message for collaborators\n'
                '/message Message for collaborators\n'
                '/rename Task name to New name\n'
                '/delete Task name\n'
                '/openTask Task name\n'
                '\nBoard and stage commands\n'
                '/createBoard Board name\n'
                '/renameBoard New board name\n'
                '/openBoard Board name\n'
                '/addStage Stage name\n'
                '\nInside a task editor\n'
                '/description Description text\n'
                '/addDescription Description text\n'
                '/setDescription Description text\n'
                '/clearDescription\n'
                '/move Done\n'
                '/rename New task title\n'
                '/delete',
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

  Future<void> _sendBoardChatCommand(String instruction) async {
    final body = _boardChatCommandBody(instruction);
    if (body.isEmpty) {
      _showMessage('Type a message after /chat.', isError: true);
      return;
    }

    setState(() => _running = true);
    try {
      await ref
          .read(kanbanRepositoryProvider)
          .addBoardMessage(
            boardId: widget.boardId,
            body: body,
            messageId: const Uuid().v4(),
          );
      if (!mounted) {
        return;
      }
      _controller.clear();
      _showMessage('Message sent.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        friendlyErrorMessage(error, fallback: 'Could not send message.'),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Future<void> _installModel() async {
    if (_installingModel || _running) {
      return;
    }
    if (!FeatureFlags.offlineAiEnabled) {
      _showMessage(
        'Offline AI is available only in the mobile and desktop apps.',
        isError: true,
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['task', 'litertlm', 'bin', 'tflite'],
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    setState(() => _installingModel = true);
    try {
      await ref
          .read(onDeviceLlmTaskCommandServiceProvider)
          .installModelFromFile(path: path, modelType: _modelType);
      if (!mounted) {
        return;
      }
      setState(() => _hasModel = true);
      _showMessage('Offline AI model installed.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: 'Model install failed. Try choosing the file again.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _installingModel = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.offlineAiEnabled) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded),
                  const SizedBox(width: 10),
                  Text(
                    'AI Assistant',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Offline AI is available only in the mobile and desktop apps.',
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded),
                const SizedBox(width: 10),
                Text(
                  'AI Assistant',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (!_hasModel) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4D8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Install a .task or .litertlm model to use AI offline.',
                      ),
                      const SizedBox(height: 10),
                      DropdownButton<OfflineModelType>(
                        value: _modelType,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: OfflineModelType.functionGemma,
                            child: Text('FunctionGemma'),
                          ),
                          DropdownMenuItem(
                            value: OfflineModelType.gemmaIt,
                            child: Text('Gemma'),
                          ),
                          DropdownMenuItem(
                            value: OfflineModelType.qwen,
                            child: Text('Qwen'),
                          ),
                          DropdownMenuItem(
                            value: OfflineModelType.deepSeek,
                            child: Text('DeepSeek'),
                          ),
                          DropdownMenuItem(
                            value: OfflineModelType.general,
                            child: Text('General'),
                          ),
                        ],
                        onChanged:
                            _installingModel
                                ? null
                                : (value) {
                                  if (value != null) {
                                    setState(() => _modelType = value);
                                  }
                                },
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _installingModel ? null : _installModel,
                          icon:
                              _installingModel
                                  ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.folder_open_rounded),
                          label: Text(
                            _installingModel
                                ? 'Installing Model'
                                : 'Choose Model File',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SegmentedButton<AiMode>(
              segments: [
                const ButtonSegment<AiMode>(
                  value: AiMode.command,
                  icon: Icon(Icons.bolt_rounded),
                  tooltip: 'Command',
                ),
                ButtonSegment<AiMode>(
                  value: AiMode.analysis,
                  icon: Icon(Icons.query_stats_rounded),
                  tooltip: 'Analyze',
                ),
                ButtonSegment<AiMode>(
                  value: AiMode.chat,
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  tooltip: 'Chat',
                ),
              ],
              selected: {_mode},
              onSelectionChanged:
                  _running
                      ? null
                      : (selection) {
                        setState(() {
                          _mode = selection.first;
                          _analysis = null;
                          _chatResponse = null;
                        });
                      },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText:
                    _mode == AiMode.command
                        ? '/create Task name or /move Task name to Done'
                        : _mode == AiMode.analysis
                        ? 'Noggin, analyze this board and suggest what I should do next'
                        : 'Noggin, what should I work on next?',
                filled: true,
                suffixIcon: IconButton(
                  tooltip:
                      _listening
                          ? 'Stop listening'
                          : 'Listen for Noggin command',
                  icon: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                  onPressed: _running ? null : _toggleListening,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed:
                    _running ||
                            (!_hasModel &&
                                !(_mode == AiMode.command &&
                                    _canRunSlashCommand))
                        ? null
                        : _submit,
                icon:
                    _running
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.send_rounded),
                label: Text(switch (_mode) {
                  AiMode.command => 'Run Command',
                  AiMode.analysis => 'Analyze Board',
                  AiMode.chat => 'Send Chat',
                }),
              ),
            ),
            if (_analysis != null) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Text(_analysis!),
                  ),
                ),
              ),
            ],
            if (_chatResponse != null) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Text(_chatResponse!),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum AiMode { command, analysis, chat }

bool _isSlashCommand(String instruction) {
  return instruction.trimLeft().startsWith('/');
}

bool _isCommandHelpRequest(String instruction) {
  final normalized = instruction.trim().toLowerCase();
  return normalized == '/commands' ||
      normalized == '/help' ||
      normalized == 'commands' ||
      normalized == 'help';
}

bool _isBoardChatCommand(String instruction) {
  final normalized = instruction.trimLeft().toLowerCase();
  return normalized == '/chat' ||
      normalized.startsWith('/chat ') ||
      normalized == '/message' ||
      normalized.startsWith('/message ') ||
      normalized == '/say' ||
      normalized.startsWith('/say ');
}

String _boardChatCommandBody(String instruction) {
  return instruction
      .trim()
      .replaceFirst(
        RegExp(r'^\/(?:chat|message|say)\s*', caseSensitive: false),
        '',
      )
      .trim();
}
