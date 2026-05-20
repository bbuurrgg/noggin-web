# Performance Optimization Log

Date: 2026-05-21

This log records app performance work already completed, mainly around Kanban board rebuilds, realtime refresh behavior, and web/mobile runtime safety.

Status: Good enough for now. Rebuild profiling can pause unless users report real lag.

## Completed

### Board data streams

- Consolidated per-status task streams into the board task stream.
- `tasksForStatusProvider` now derives status lists from `boardTasksProvider(boardId)` instead of opening separate Supabase streams per column.
- Added stable per-status snapshots so unchanged columns are not notified just because Supabase returns a fresh full-board task list.
- Added `taskByIdProvider(TaskByIdRequest)` so visible task cards can watch their own task by id instead of receiving fresh task objects from the parent list.
- `taskByIdProvider` uses a value-equal task snapshot so fresh Supabase task objects do not notify unchanged cards.
- Card-level task snapshots compare only fields rendered by task cards, while column snapshots still compare ordering/status fields.
- `taskByIdProvider` selects a custom value-equal state object before converting back to `AsyncValue`, avoiding fresh `AsyncValue` wrapper notifications.

Files:

- `lib/features/kanban/data/kanban_providers.dart`
- `lib/features/kanban/presentation/kanban_board.dart`

### Task invalidation scope

- Reduced broad board invalidations after task actions.
- Task create/update/delete/move/attachment flows now use `invalidateBoardTaskSideEffects()` where possible.
- Stage/board structure changes still use full `invalidateBoard()`.

Files:

- `lib/features/kanban/data/kanban_providers.dart`
- `lib/features/kanban/presentation/task_editor_sheet.dart`
- `lib/features/kanban/presentation/kanban_board.dart`

### Auth refresh rebuild isolation

- Added `currentUserIdProvider` so providers can depend on stable user identity instead of the full auth state.
- `CraneTaskApp` now routes based on signed-in user id, reducing rebuilds from token refreshes.
- `canEditBoardProvider` and `boardAccessProvider` now watch stable user id instead of full auth state.
- Drawer auth/profile watches were moved into local `Consumer` widgets so the board body is less likely to rebuild from auth/profile updates.

Files:

- `lib/features/auth/data/auth_providers.dart`
- `lib/features/kanban/data/kanban_providers.dart`
- `lib/src/app.dart`
- `lib/features/dashboard/presentation/dashboard_screen.dart`

### Resume refresh

- Dashboard resume refresh is throttled and guarded against overlapping refreshes.
- On resume, selected board data is invalidated after refreshing Supabase session/realtime auth.

File:

- `lib/features/dashboard/presentation/dashboard_screen.dart`

### Task card rendering

- Added stable task card keys at the direct list child level.
- Wrapped task cards and columns in `RepaintBoundary`.
- Added memoized task card content so unchanged visual card bodies can be reused.
- Main board list now renders task cards by `boardId/taskId`, and the card watches its own task.
- Widget-side task card memoization compares displayed update day instead of exact `updatedAt`.

File:

- `lib/features/kanban/presentation/kanban_board.dart`

### Collaborator filter

- Added board task filtering by collaborator and unassigned.
- Mobile filter UI uses avatar-only collaborator chips and an icon for unassigned.

File:

- `lib/features/kanban/presentation/kanban_board.dart`

### Avatar cache

- Added a shared avatar image cache helper.
- Replaced app `NetworkImage` avatar usage with cached avatar providers.
- Evicts old avatar URL after profile avatar upload.

File:

- `lib/core/utils/avatar_image_cache.dart`

### Web/runtime safety

- Offline AI is disabled on web.
- Added local stubs/overrides to prevent `sqlite3`/`dart:ffi` web build failures from AI dependencies.
- In-app dev tools disable Flutter performance overlay on web because Flutter Web does not support `showPerformanceOverlay`.

Files:

- `lib/core/config/feature_flags.dart`
- `lib/src/app.dart`
- `pubspec.yaml`
- `third_party/local_hnsw`
- `third_party/sqlite3`

### Debug profiling tools

- Added an in-app debug dev tools button with repaint-rainbow toggle.
- Added debug-only rebuild counters for:
  - `KanbanBoardView`
  - `AssigneeFilterBar`
  - `KanbanColumn`
  - `TaskCard`
  - `TaskEditorSheet`
- Dev tools are hidden by default and can be re-enabled with `--dart-define=ENABLE_IN_APP_DEV_TOOLS=true`.
- Rebuild logs are silent by default and can be re-enabled with `--dart-define=ENABLE_REBUILD_LOGS=true`.

Files:

- `lib/src/app.dart`
- `lib/core/utils/debug_rebuild_counter.dart`
- `lib/features/kanban/presentation/kanban_board.dart`
- `lib/features/kanban/presentation/task_editor_sheet.dart`

## Observed Results

- Repaint rainbow showed no major full-screen repaint problem during normal board usage.
- Early logs showed all columns/cards rebuilding heavily after task actions and auth refreshes.
- After stream consolidation, narrowed invalidation, auth isolation, and per-card selection, rebuilds were reduced significantly.
- Final logs still showed some rebuild noise, but mostly around expected initial provider settling, affected-column/task updates, task editor state changes, and realtime refresh behavior.
- No large repaint issue was observed, and there is no current need to keep chasing rebuild counters unless the app feels slow in real use.

## Keep In Mind

- Debug rebuild logging itself adds overhead and should stay debug-only.
- Before production release, consider disabling or hiding the in-app dev tools button behind a compile-time flag.
- If future lag appears, profile the exact action first before adding more abstractions.

## Possible Next Optimizations

Priority: do these only if real lag appears or before production cleanup.

### Saved Backlog

- Keep previous data visible during refetch.
  After resume or invalidation, screens can briefly show loading/error states. Keep the last good board/tasks/messages visible while refresh happens.
- Fix speech-to-text deprecations.
  `flutter analyze` is only failing because of `speech_to_text` deprecation infos. Update usage to `SpeechListenOptions` so analyzer is clean.
- Paginate older chat/activity more deliberately.
  Chat/activity already limit data, but older loading can be made smoother and cheaper.
- Web build cleanup for AI.
  Since AI is mobile/desktop only, fully isolate `flutter_gemma` from web builds instead of relying on package stubs.
- Reduce broad resume invalidation.
  Resume refresh still invalidates several providers. Make it smarter: refresh auth/realtime, then only refetch active board tasks and dashboard essentials.

### Release cleanup

- Debug rebuild counters are gated behind `bool.fromEnvironment('ENABLE_REBUILD_LOGS')`.
- The in-app dev tools button is gated behind `bool.fromEnvironment('ENABLE_IN_APP_DEV_TOOLS')`.
- Keep repaint/dev tools available for debug builds, but avoid shipping visible debug UI.

To re-enable profiling locally:

```powershell
flutter run -d chrome --dart-define=ENABLE_IN_APP_DEV_TOOLS=true --dart-define=ENABLE_REBUILD_LOGS=true
```

Use the same flags with Android/Windows targets if needed.

### Board rebuilds

- Convert more dashboard and board subtrees to smaller `ConsumerWidget`s if broad dashboard rebuilds reappear.
- Consider a stronger normalized task store if task lists grow large:
  - provider for ordered task ids per status
  - provider for task data by id
  - card widgets that only watch task id data
- Add equality/value objects to domain models if provider `select` behavior needs to be stricter across more screens.
- Review whether activity/notification invalidations after task changes can be delayed or batched.

### Task editor

- Investigate `TaskEditorSheet` rebuilds while typing only if the editor starts to feel slow.
- Split editor sections into smaller widgets if text input, comments, attachments, or AI controls start rebuilding each other.
- Consider debouncing expensive provider reads or derived values inside the editor.

### Realtime and resume

- If resume still causes visible loading or stale data warnings, add a short stale-while-revalidate cache around board/member data.
- Consider batching realtime refresh side effects after reconnect/session refresh.
- Add timestamps to resume refresh logs so future testing can separate app lifecycle refresh from user actions.

### Measurement

- Prefer testing real lag first, then logs.
- Use repaint rainbow for paint problems and rebuild counters only for suspected rebuild problems.
- Keep a small before/after log sample when future optimizations are made.
