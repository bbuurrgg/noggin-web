# Noggin

Offline-AI-assisted kanban scaffold built with Flutter, Material 3, Riverpod code generation, Drift, PowerSync, Supabase, and `speech_to_text`.

## `lib/` Structure

```text
lib/
  main.dart
  src/
    app.dart
  core/
    config/
      supabase_config.dart
    database/
      app_database.dart
    sync/
      powersync_schema.dart
    theme/
      app_theme.dart
  features/
    ai_control/
      data/
        ai_control_providers.dart
        on_device_llm_task_command_service.dart
      domain/
        ai_task_command.dart
        ai_task_command_executor.dart
      presentation/
        ai_command_sheet.dart
    dashboard/
      presentation/
        dashboard_screen.dart
    kanban/
      data/
        drift_kanban_repository.dart
        kanban_providers.dart
      domain/
        kanban_task.dart
        kanban_repository.dart
        task_status.dart
      presentation/
        kanban_board.dart
```

## Database Schema

`Boards` and `Tasks` are defined in `lib/core/database/app_database.dart`.
`Tasks.status` stores one of `todo`, `in_progress`, or `done`, displayed as To Do, In Progress, and Done.

## Generate Code

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## Supabase

Supabase is initialized in `lib/main.dart` using `lib/core/config/supabase_config.dart`.
The checked-in defaults point at the provided board URL and publishable key. Override them per environment with:

```sh
flutter run --dart-define=SUPABASE_URL=https://your-board.supabase.co --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

## Offline AI Commands

On-device command planning is available from the sparkle button in the bottom bar.
The first time you open the AI sheet, choose a local `.task` or `.litertlm`
model file. After it is installed, task commands and board analysis run on the
device without an AI server.

```sh
flutter run
```

Recommended starter model: FunctionGemma 270M `.task`, because it is small
enough for phones and good at structured command output.

## Platform Permissions

Android microphone permission is in `android/app/src/main/AndroidManifest.xml`.
iOS microphone and speech-recognition usage descriptions are in `ios/Runner/Info.plist`.
