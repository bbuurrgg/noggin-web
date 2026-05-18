import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/feature_flags.dart';
import '../domain/kanban_repository.dart';
import '../domain/kanban_task.dart';

class SupabaseKanbanRepository implements KanbanRepository {
  SupabaseKanbanRepository(
    this._client, {
    bool sentenceCaseFormattingEnabled =
        FeatureFlags.sentenceCaseFormattingEnabled,
  }) : _sentenceCaseFormattingEnabled = sentenceCaseFormattingEnabled;

  final SupabaseClient _client;
  final bool _sentenceCaseFormattingEnabled;

  static final _allTasksBoard = KanbanBoard(
    id: demoBoardId,
    name: 'Dashboard',
    boardType: 'project',
    description: 'Summary of all tasks across boards',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in before managing boards.');
    }
    return id;
  }

  @override
  Stream<List<KanbanBoard>> watchBoards() {
    return _withFreshRealtimeAuth(
      () => _client
          .from('boards')
          .stream(primaryKey: ['id'])
          .order('updated_at', ascending: false)
          .map((rows) => [_allTasksBoard, ...rows.map(_mapBoard)]),
    );
  }

  @override
  Future<List<KanbanBoard>> listBoards() async {
    final rows = await _client
        .from('boards')
        .select()
        .order('updated_at', ascending: false);
    return [_allTasksBoard, ...rows.map(_mapBoard)];
  }

  @override
  Stream<List<KanbanTask>> watchTasks(String boardId) {
    if (boardId != demoBoardId) {
      return _withFreshRealtimeAuth(
        () => _client
            .from('tasks')
            .stream(primaryKey: ['id'])
            .eq('board_id', boardId)
            .order('status')
            .order('updated_at', ascending: false)
            .map((rows) => _sortTasks(rows.map(_mapTask).toList())),
      );
    }

    return _withFreshRealtimeAuth(
      () => _client
          .from('tasks')
          .stream(primaryKey: ['id'])
          .order('status')
          .order('updated_at', ascending: false)
          .map((rows) => _sortTasks(rows.map(_mapTask).toList())),
    );
  }

  @override
  Future<List<KanbanTask>> listTasks(String boardId) async {
    if (boardId != demoBoardId) {
      final rows = await _client
          .from('tasks')
          .select()
          .eq('board_id', boardId)
          .order('status')
          .order('updated_at', ascending: false);
      return _sortTasks(rows.map(_mapTask).toList());
    }

    final rows = await _client
        .from('tasks')
        .select()
        .order('status')
        .order('updated_at', ascending: false);
    return _sortTasks(rows.map(_mapTask).toList());
  }

  @override
  Future<String> createBoard({
    required String name,
    String? description,
    String boardType = 'project',
  }) async {
    final boardId = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final formattedName = _formatName(name);

    await _client.from('boards').insert({
      'id': boardId,
      'owner_id': _userId,
      'name': formattedName,
      'board_type': _normalizeBoardType(boardType),
      'description':
          description == null || description.isEmpty ? null : description,
      'created_at': now,
      'updated_at': now,
    });

    await _client.from('board_members').insert({
      'board_id': boardId,
      'user_id': _userId,
      'role': 'owner',
    });

    await _client.from('stages').insert([
      _stageInsert(boardId: boardId, name: 'To Do', sortOrder: 0),
      _stageInsert(boardId: boardId, name: 'In Progress', sortOrder: 1),
      _stageInsert(boardId: boardId, name: 'Done', sortOrder: 2),
    ]);

    return boardId;
  }

  @override
  Future<void> renameBoard({
    required String boardId,
    required String name,
    String? boardType,
  }) {
    return _client
        .from('boards')
        .update({
          'name': _formatName(name),
          if (boardType != null) 'board_type': _normalizeBoardType(boardType),
        })
        .eq('id', boardId);
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    await _client.rpc<void>(
      'delete_owned_board',
      params: {'target_board_id': boardId},
    );
  }

  @override
  Future<List<KanbanBoardMember>> listBoardMembers(String boardId) async {
    await _ensureFreshRealtimeAuth();
    final rows = await _client.rpc<List<dynamic>>(
      'list_board_members',
      params: {'target_board_id': boardId},
    );
    return rows.cast<Map<String, dynamic>>().map(_mapBoardMember).toList();
  }

  @override
  Future<List<KanbanBoardInvite>> listBoardInvites(String boardId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_board_invites',
      params: {'target_board_id': boardId},
    );
    return rows.cast<Map<String, dynamic>>().map(_mapBoardInvite).toList();
  }

  @override
  Future<List<KanbanPendingBoardInvite>> listPendingInvites() async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_my_pending_board_invites',
    );

    return rows
        .cast<Map<String, dynamic>>()
        .map(_mapPendingBoardInvite)
        .toList();
  }

  @override
  Future<void> inviteBoardMember({
    required String boardId,
    required String email,
    required String role,
  }) {
    return _client.rpc<void>(
      'invite_board_member_by_email',
      params: {
        'target_board_id': boardId,
        'target_email': email,
        'target_role': role,
      },
    );
  }

  @override
  Future<void> removeBoardMember({
    required String boardId,
    required String userId,
  }) {
    return _client.rpc<void>(
      'remove_board_member',
      params: {'target_board_id': boardId, 'target_user_id': userId},
    );
  }

  @override
  Future<void> leaveBoard(String boardId) {
    return _client.rpc<void>(
      'leave_board',
      params: {'target_board_id': boardId},
    );
  }

  @override
  Future<void> cancelBoardInvite({
    required String boardId,
    required String inviteId,
  }) {
    return _client.rpc<void>(
      'cancel_board_invite',
      params: {'target_board_id': boardId, 'target_invite_id': inviteId},
    );
  }

  @override
  Future<String> acceptBoardInvite(String inviteId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'accept_board_invite',
      params: {'target_invite_id': inviteId},
    );
    final first = rows.cast<Map<String, dynamic>>().first;
    return (first['board_id'] ?? first['accepted_board_id']) as String;
  }

  @override
  Future<void> declineBoardInvite(String inviteId) {
    return _client.rpc<void>(
      'decline_board_invite',
      params: {'target_invite_id': inviteId},
    );
  }

  @override
  Future<void> updateBoardMemberRole({
    required String boardId,
    required String userId,
    required String role,
  }) {
    return _client.rpc<void>(
      'update_board_member_role',
      params: {
        'target_board_id': boardId,
        'target_user_id': userId,
        'target_role': role,
      },
    );
  }

  @override
  Future<String> createTask({
    required String boardId,
    required String title,
    String? description,
    required String status,
    String priority = TaskPriority.defaultValue,
    String? assigneeId,
    DateTime? dueAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = const Uuid().v4();
    await _client.from('tasks').insert({
      'id': taskId,
      'board_id': boardId,
      'title': _formatName(title),
      'description':
          description == null || description.isEmpty ? null : description,
      'status': status,
      'priority': TaskPriority.normalize(priority),
      if (assigneeId != null && assigneeId.isNotEmpty)
        'assignee_id': assigneeId,
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
      'sort_order': 0,
      'created_by': _userId,
      'updated_by': _userId,
      'created_at': now,
      'updated_at': now,
    });
    return taskId;
  }

  @override
  Future<void> moveTask({
    required String taskId,
    required String status,
    int? sortOrder,
  }) {
    return _client
        .from('tasks')
        .update({
          'status': status,
          if (sortOrder != null) 'sort_order': sortOrder,
        })
        .eq('id', taskId);
  }

  @override
  Future<KanbanTask?> findTaskBySpokenTitle(
    String boardId,
    String spokenTitle,
  ) async {
    final tasks = await listTasks(boardId);
    final target = _normalize(spokenTitle);
    for (final task in tasks) {
      if (_normalize(task.title) == target) {
        return task;
      }
    }
    for (final task in tasks) {
      final title = _normalize(task.title);
      if (title.contains(target) || target.contains(title)) {
        return task;
      }
    }
    return null;
  }

  @override
  Future<void> updateTaskTitle({
    required String taskId,
    required String title,
  }) {
    return _client
        .from('tasks')
        .update({'title': _formatName(title)})
        .eq('id', taskId);
  }

  @override
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
  }) {
    return _client
        .from('tasks')
        .update({
          if (title != null) 'title': _formatName(title),
          if (description != null)
            'description': description.isEmpty ? null : description,
          if (status != null) 'status': status,
          if (priority != null) 'priority': TaskPriority.normalize(priority),
          if (assigneeId != null)
            'assignee_id': assigneeId.isEmpty ? null : assigneeId,
          if (dueAt != null || clearDueAt)
            'due_at': dueAt?.toUtc().toIso8601String(),
          if (attachmentUrls != null) 'attachment_urls': attachmentUrls,
          'updated_by': _userId,
        })
        .eq('id', taskId);
  }

  @override
  Future<String> uploadTaskAttachment({
    required String boardId,
    required String taskId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final extension = _fileExtension(fileName);
    final path =
        '$boardId/$taskId/${const Uuid().v4()}${extension.isEmpty ? '' : '.$extension'}';
    await _client.storage
        .from('task-attachments')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType ?? 'application/octet-stream',
          ),
        );
    return _client.storage.from('task-attachments').getPublicUrl(path);
  }

  @override
  Future<void> clearTaskDescription(String taskId) {
    return _client.from('tasks').update({'description': null}).eq('id', taskId);
  }

  @override
  Future<void> deleteTask(String taskId) {
    return _client.from('tasks').delete().eq('id', taskId);
  }

  @override
  Stream<List<KanbanStage>> watchStages(String boardId) {
    if (boardId == demoBoardId) {
      return _withFreshRealtimeAuth(
        () => _client
            .from('stages')
            .stream(primaryKey: ['id'])
            .order('sort_order')
            .map(_uniqueStagesSorted),
      );
    }

    return _withFreshRealtimeAuth(
      () => _client
          .from('stages')
          .stream(primaryKey: ['id'])
          .eq('board_id', boardId)
          .order('sort_order')
          .map((rows) => _sortStages(rows.map(_mapStage).toList())),
    );
  }

  @override
  Future<List<KanbanStage>> listStages(String boardId) async {
    if (boardId != demoBoardId) {
      final rows = await _client
          .from('stages')
          .select()
          .eq('board_id', boardId)
          .order('sort_order');
      return _sortStages(rows.map(_mapStage).toList());
    }

    final rows = await _client.from('stages').select().order('sort_order');
    return _uniqueStagesSorted(rows);
  }

  @override
  Future<void> createStage({
    required String boardId,
    required String name,
    int? colorValue,
  }) async {
    final normalizedName = _formatName(name);
    final stages = await listStages(boardId);
    _ensureUniqueStageName(stages, normalizedName);
    await _client
        .from('stages')
        .insert(
          _stageInsert(
            boardId: boardId,
            name: normalizedName,
            sortOrder: stages.length,
            colorValue: colorValue,
          ),
        );
  }

  @override
  Future<void> updateStageName({
    required String stageId,
    required String oldName,
    required String newName,
    required String boardId,
  }) async {
    final normalizedName = _formatName(newName);
    final stages = await listStages(boardId);
    _ensureUniqueStageName(stages, normalizedName, excludingStageId: stageId);
    await _client
        .from('stages')
        .update({'name': normalizedName})
        .eq('id', stageId);
    await _client
        .from('tasks')
        .update({'status': normalizedName})
        .eq('board_id', boardId)
        .eq('status', oldName);
  }

  @override
  Future<void> reorderStages(List<String> stageIds) async {
    for (var i = 0; i < stageIds.length; i++) {
      await _client
          .from('stages')
          .update({'sort_order': i})
          .eq('id', stageIds[i]);
    }
  }

  @override
  Future<void> deleteStage(String stageId) async {
    final stage =
        await _client.from('stages').select().eq('id', stageId).maybeSingle();
    if (stage == null) {
      return;
    }
    await _client
        .from('tasks')
        .delete()
        .eq('board_id', stage['board_id'] as String)
        .eq('status', stage['name'] as String);
    await _client.from('stages').delete().eq('id', stageId);
  }

  @override
  Stream<List<KanbanTaskComment>> watchTaskComments(String taskId) {
    return _withFreshRealtimeAuth(
      () => _client
          .from('task_comments')
          .stream(primaryKey: ['id'])
          .eq('task_id', taskId)
          .order('created_at')
          .map((rows) => rows.map(_mapTaskComment).toList()),
    );
  }

  @override
  Future<void> addTaskComment({
    required String boardId,
    required String taskId,
    required String body,
  }) {
    return _client.from('task_comments').insert({
      'id': const Uuid().v4(),
      'board_id': boardId,
      'task_id': taskId,
      'author_id': _userId,
      'body': body,
    });
  }

  @override
  Future<void> deleteTaskComment(String commentId) {
    return _client.from('task_comments').delete().eq('id', commentId);
  }

  @override
  Stream<List<KanbanBoardMessage>> watchBoardMessages(String boardId) {
    return _withFreshRealtimeAuth(
      () => _client
          .from('board_messages')
          .stream(primaryKey: ['id'])
          .eq('board_id', boardId)
          .order('created_at', ascending: false)
          .limit(50)
          .map(
            (rows) =>
                rows.map(_mapBoardMessage).toList()
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
          ),
    );
  }

  @override
  Future<List<KanbanBoardMessage>> listBoardMessages({
    required String boardId,
    DateTime? before,
    int limit = 50,
  }) async {
    var query = _client.from('board_messages').select().eq('board_id', boardId);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(_mapBoardMessage).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> addBoardMessage({
    required String boardId,
    required String body,
    String? messageId,
    String? replyToMessageId,
  }) {
    return _client
        .from('board_messages')
        .upsert(
          {
            'id': messageId ?? const Uuid().v4(),
            'board_id': boardId,
            'author_id': _userId,
            'body': body,
            'reply_to_message_id': replyToMessageId,
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> deleteBoardMessage(String messageId) {
    return _client.from('board_messages').delete().eq('id', messageId);
  }

  @override
  Stream<List<KanbanMessageReaction>> watchBoardMessageReactions(
    String boardId,
  ) {
    return _withFreshRealtimeAuth(
      () => _client
          .from('board_message_reactions')
          .stream(primaryKey: ['id'])
          .eq('board_id', boardId)
          .order('created_at')
          .map((rows) => rows.map(_mapMessageReaction).toList()),
    );
  }

  @override
  Future<void> toggleBoardMessageReaction({
    required String boardId,
    required String messageId,
    required String emoji,
  }) async {
    final userId = _userId;
    final existing =
        await _client
            .from('board_message_reactions')
            .select('id')
            .eq('message_id', messageId)
            .eq('user_id', userId)
            .eq('emoji', emoji)
            .limit(1)
            .maybeSingle();

    if (existing != null) {
      await _client
          .from('board_message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .eq('emoji', emoji);
      return;
    }

    await _client.from('board_message_reactions').insert({
      'id': const Uuid().v4(),
      'board_id': boardId,
      'message_id': messageId,
      'user_id': userId,
      'emoji': emoji,
    });
  }

  @override
  Stream<List<KanbanNotification>> watchNotifications() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream.value(const []);
    }

    return _withFreshRealtimeAuth(
      () => _client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', userId)
          .order('created_at', ascending: false)
          .limit(50)
          .map(
            (rows) =>
                rows
                    .where((row) => row['read_at'] == null)
                    .map(_mapNotification)
                    .toList(),
          ),
    );
  }

  @override
  Future<void> markNotificationsRead({
    String? boardId,
    String? taskId,
    String? notificationType,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    var query = _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('recipient_id', userId)
        .isFilter('read_at', null);

    if (boardId != null) {
      query = query.eq('board_id', boardId);
    }
    if (taskId != null) {
      query = query.eq('task_id', taskId);
    }
    if (notificationType != null) {
      query = query.eq('notification_type', notificationType);
    }

    await query;
  }

  @override
  Stream<List<KanbanActivityEvent>> watchBoardActivity(String boardId) {
    return _withFreshRealtimeAuth(
      () => _client
          .from('board_activity')
          .stream(primaryKey: ['id'])
          .eq('board_id', boardId)
          .order('created_at', ascending: false)
          .limit(50)
          .map(
            (rows) =>
                rows
                    .where((row) => row['event_type'] != 'message_sent')
                    .map(_mapActivityEvent)
                    .toList(),
          ),
    );
  }

  @override
  Future<List<KanbanActivityEvent>> listBoardActivity({
    required String boardId,
    DateTime? before,
    int limit = 50,
  }) async {
    var query = _client
        .from('board_activity')
        .select()
        .eq('board_id', boardId)
        .neq('event_type', 'message_sent');

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(_mapActivityEvent).toList();
  }

  Stream<T> _withFreshRealtimeAuth<T>(
    Stream<T> Function() createStream,
  ) async* {
    await _ensureFreshRealtimeAuth();
    yield* createStream();
  }

  Future<void> _ensureFreshRealtimeAuth() async {
    var session = _client.auth.currentSession;
    if (session?.isExpired ?? false) {
      final response = await _client.auth.refreshSession();
      session = response.session ?? _client.auth.currentSession;
    }

    await _client.realtime.setAuth(session?.accessToken);
  }

  Map<String, Object?> _stageInsert({
    required String boardId,
    required String name,
    required int sortOrder,
    int? colorValue,
  }) {
    return {
      'id': const Uuid().v4(),
      'board_id': boardId,
      'name': name,
      'sort_order': sortOrder,
      'color_value': colorValue,
    };
  }

  List<KanbanStage> _uniqueStagesSorted(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final stages =
        rows.map(_mapStage).where((stage) => seen.add(stage.name)).toList();
    return _sortStages(stages);
  }

  List<KanbanStage> _sortStages(List<KanbanStage> stages) {
    return List<KanbanStage>.from(stages)..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) {
        return order;
      }
      return a.name.compareTo(b.name);
    });
  }

  List<KanbanTask> _sortTasks(List<KanbanTask> tasks) {
    return List<KanbanTask>.from(tasks)..sort((a, b) {
      final status = a.status.compareTo(b.status);
      if (status != 0) {
        return status;
      }
      return TaskPriority.compareTasks(a, b);
    });
  }

  void _ensureUniqueStageName(
    List<KanbanStage> stages,
    String name, {
    String? excludingStageId,
  }) {
    final normalizedName = name.trim().toLowerCase();
    final duplicate = stages.any(
      (stage) =>
          stage.id != excludingStageId &&
          stage.name.trim().toLowerCase() == normalizedName,
    );
    if (duplicate) {
      throw StateError('A stage with that name already exists in this board.');
    }
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  KanbanBoard _mapBoard(Map<String, dynamic> row) {
    return KanbanBoard(
      id: row['id'] as String,
      name: row['name'] as String,
      boardType: _normalizeBoardType(row['board_type'] as String?),
      description: row['description'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  String _normalizeBoardType(String? value) {
    return value == 'list' ? 'list' : 'project';
  }

  String _formatName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return normalized;
    if (!_sentenceCaseFormattingEnabled) return normalized;

    final lower = normalized.toLowerCase();
    return lower.replaceFirstMapped(
      RegExp(r'[a-z]'),
      (match) => match.group(0)!.toUpperCase(),
    );
  }

  KanbanTask _mapTask(Map<String, dynamic> row) {
    return KanbanTask(
      id: row['id'] as String,
      boardId: row['board_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      status: row['status'] as String,
      priority: TaskPriority.normalize(row['priority'] as String?),
      sortOrder: row['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      assigneeId: row['assignee_id'] as String?,
      createdBy: row['created_by'] as String?,
      updatedBy: row['updated_by'] as String?,
      dueAt:
          row['due_at'] == null
              ? null
              : DateTime.parse(row['due_at'] as String),
      attachmentUrls: _attachmentUrls(row['attachment_urls']),
    );
  }

  List<String> _attachmentUrls(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  String _fileExtension(String fileName) {
    final sanitized = fileName.split(RegExp(r'[\\/]')).last;
    final index = sanitized.lastIndexOf('.');
    if (index < 0 || index == sanitized.length - 1) {
      return '';
    }
    return sanitized.substring(index + 1).toLowerCase();
  }

  KanbanStage _mapStage(Map<String, dynamic> row) {
    return KanbanStage(
      id: row['id'] as String,
      boardId: row['board_id'] as String,
      name: row['name'] as String,
      sortOrder: row['sort_order'] as int? ?? 0,
      colorValue: row['color_value'] as int?,
    );
  }

  KanbanBoardMember _mapBoardMember(Map<String, dynamic> row) {
    return KanbanBoardMember(
      userId: row['user_id'] as String,
      email: row['email'] as String? ?? 'Unknown user',
      username: row['username'] as String?,
      displayName: row['display_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      role: row['role'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      isOwner: row['is_owner'] as bool? ?? false,
    );
  }

  KanbanBoardInvite _mapBoardInvite(Map<String, dynamic> row) {
    final acceptedAt = row['accepted_at'] as String?;
    return KanbanBoardInvite(
      id: row['id'] as String,
      email: row['email'] as String,
      role: row['role'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      acceptedAt: acceptedAt == null ? null : DateTime.parse(acceptedAt),
    );
  }

  KanbanPendingBoardInvite _mapPendingBoardInvite(Map<String, dynamic> row) {
    return KanbanPendingBoardInvite(
      id: row['id'] as String,
      boardId: (row['board_id'] ?? row['project_id']) as String,
      boardName:
          (row['board_name'] ?? row['project_name']) as String? ??
          'Shared board',
      email: row['email'] as String,
      role: row['role'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      inviterEmail: row['inviter_email'] as String?,
    );
  }

  KanbanTaskComment _mapTaskComment(Map<String, dynamic> row) {
    return KanbanTaskComment(
      id: row['id'] as String,
      taskId: row['task_id'] as String,
      boardId: row['board_id'] as String,
      authorId: row['author_id'] as String?,
      body: row['body'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  KanbanBoardMessage _mapBoardMessage(Map<String, dynamic> row) {
    return KanbanBoardMessage(
      id: row['id'] as String,
      boardId: row['board_id'] as String,
      authorId: row['author_id'] as String?,
      body: row['body'] as String,
      replyToMessageId: row['reply_to_message_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  KanbanMessageReaction _mapMessageReaction(Map<String, dynamic> row) {
    return KanbanMessageReaction(
      id: row['id'] as String,
      boardId: row['board_id'] as String,
      messageId: row['message_id'] as String,
      userId: row['user_id'] as String,
      emoji: row['emoji'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  KanbanActivityEvent _mapActivityEvent(Map<String, dynamic> row) {
    return KanbanActivityEvent(
      id: row['id'] as String,
      boardId: row['board_id'] as String,
      actorId: row['actor_id'] as String?,
      eventType: row['event_type'] as String,
      taskId: row['task_id'] as String?,
      stageId: row['stage_id'] as String?,
      subject: row['subject'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  KanbanNotification _mapNotification(Map<String, dynamic> row) {
    final metadata = row['metadata'];
    final actorDisplayName =
        metadata is Map
            ? (metadata['actor_display_name'] as String? ??
                metadata['actor_email'] as String?)
            : null;

    return KanbanNotification(
      id: row['id'] as String,
      recipientId: row['recipient_id'] as String,
      boardId: row['board_id'] as String?,
      actorId: row['actor_id'] as String?,
      actorDisplayName: actorDisplayName,
      notificationType: row['notification_type'] as String,
      taskId: row['task_id'] as String?,
      subject: row['subject'] as String?,
      sourceKey: row['source_key'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
