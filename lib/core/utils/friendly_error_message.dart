import 'dart:async';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyErrorMessage(Object error, {String? fallback}) {
  if (error is AuthApiException) {
    return _authMessage(error);
  }

  if (error is AuthException) {
    return _messageFromText(
      error.message,
      fallback: fallback ?? 'Could not complete sign in. Please try again.',
    );
  }

  if (error is PostgrestException) {
    return _databaseMessage(error);
  }

  if (error is StorageException) {
    return _storageMessage(error, fallback: fallback);
  }

  if (error is TimeoutException) {
    return 'The request took too long. Please try again.';
  }

  if (error is PlatformException) {
    return _platformMessage(error, fallback: fallback);
  }

  if (error is UnsupportedError) {
    return error.message ?? fallback ?? 'This action is not available here.';
  }

  if (error is StateError) {
    return _messageFromText(
      error.message,
      fallback: fallback ?? 'This action could not be completed right now.',
    );
  }

  return _messageFromText(
    error.toString(),
    fallback: fallback ?? 'Something went wrong. Please try again.',
  );
}

String detailedErrorMessage(Object error, {String? fallback}) {
  if (error is PostgrestException) {
    final details = error.details?.toString().trim();
    final parts = [
      if (error.code != null && error.code!.trim().isNotEmpty)
        'code: ${error.code}',
      if (error.message.trim().isNotEmpty) 'message: ${error.message}',
      if (details != null && details.isNotEmpty) 'details: $details',
      if (error.hint != null && error.hint!.trim().isNotEmpty)
        'hint: ${error.hint}',
    ];
    return parts.isEmpty
        ? fallback ?? 'Unknown Supabase error.'
        : parts.join('\n');
  }

  if (error is AuthException) {
    return 'message: ${error.message}';
  }

  if (error is StorageException) {
    final parts = [
      if (error.statusCode != null && error.statusCode!.trim().isNotEmpty)
        'status: ${error.statusCode}',
      if (error.message.trim().isNotEmpty) 'message: ${error.message}',
      if (error.error != null && error.error!.trim().isNotEmpty)
        'error: ${error.error}',
    ];
    return parts.isEmpty
        ? fallback ?? 'Unknown storage error.'
        : parts.join('\n');
  }

  if (error is PlatformException) {
    final parts = [
      'code: ${error.code}',
      if (error.message != null) 'message: ${error.message}',
      if (error.details != null) 'details: ${error.details}',
    ];
    return parts.join('\n');
  }

  return error.toString().trim().isEmpty
      ? fallback ?? 'Unknown error.'
      : error.toString();
}

String _authMessage(AuthApiException error) {
  final text = '${error.code ?? ''} ${error.message}'.toLowerCase();

  if (text.contains('invalid_credentials') ||
      text.contains('invalid login credentials') ||
      text.contains('invalid credentials')) {
    return 'The email or password is incorrect.';
  }

  if (text.contains('email_not_confirmed') ||
      text.contains('email not confirmed')) {
    return 'Please confirm your email before signing in.';
  }

  if (text.contains('user_already_exists') ||
      text.contains('already registered') ||
      text.contains('already exists')) {
    return 'An account with this email already exists. Try signing in instead.';
  }

  if (text.contains('weak_password') || text.contains('weak password')) {
    return 'Please choose a stronger password.';
  }

  if (text.contains('rate limit') || text.contains('too many')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }

  return _messageFromText(
    error.message,
    fallback: 'Could not complete sign in. Please try again.',
  );
}

String _databaseMessage(PostgrestException error) {
  final text =
      '${error.code ?? ''} ${error.message} ${error.details ?? ''}'
          .toLowerCase();

  if (text.contains('row-level security') ||
      text.contains('permission denied')) {
    return 'You do not have permission to make that change.';
  }

  if (text.contains('schema cache') ||
      text.contains('could not find the function') ||
      text.contains('function') && text.contains('does not exist')) {
    return 'Supabase is missing the latest app schema. Apply schema.sql, then try again.';
  }

  if (text.contains('only the board owner can invite collaborators')) {
    return 'Only the board owner can invite collaborators.';
  }

  if (text.contains('only the board owner can delete this board')) {
    return 'Only the board owner can delete this board.';
  }

  if (text.contains('already a collaborator')) {
    return 'That user is already a collaborator.';
  }

  if (text.contains('already owns this board')) {
    return 'That user already owns this board.';
  }

  if (text.contains('email is required')) {
    return 'Enter an email address to invite.';
  }

  if (text.contains('invitation not found')) {
    return 'That invitation is no longer available.';
  }

  if (text.contains('user_profiles_username') ||
      text.contains('user_profiles_username_unique')) {
    return 'That username is already taken.';
  }

  if (text.contains('stages_board_id_name_unique') ||
      text.contains('stage with that name already exists')) {
    return 'A stage with that name already exists in this board.';
  }

  if (text.contains('duplicate key') || text.contains('unique constraint')) {
    return 'That item already exists.';
  }

  if (text.contains('foreign key')) {
    return 'That item is linked to something that no longer exists. Refresh and try again.';
  }

  if (text.contains('check constraint') || text.contains('violates check')) {
    return 'One of the fields has an invalid value.';
  }

  if (text.contains('invalid input syntax')) {
    return 'One of the fields is not in the expected format.';
  }

  final detailed = detailedErrorMessage(error).trim();
  if (detailed.isNotEmpty) {
    return detailed;
  }

  return _messageFromText(
    error.message,
    fallback:
        'The database rejected that change. Please refresh and try again.',
  );
}

String _storageMessage(StorageException error, {String? fallback}) {
  final text =
      '${error.statusCode ?? ''} ${error.message} ${error.error ?? ''}'
          .toLowerCase();

  if (text.contains('bucket not found') ||
      text.contains('not found') && text.contains('bucket') ||
      text.contains('404')) {
    return 'Supabase is missing the avatars storage bucket. Apply the latest schema.sql, then try again.';
  }

  if (text.contains('row-level security') ||
      text.contains('permission') ||
      text.contains('unauthorized') ||
      text.contains('403')) {
    return 'Avatar upload is blocked by Supabase storage policies. Apply the latest schema.sql, then try again.';
  }

  if (text.contains('payload too large') ||
      text.contains('too large') ||
      text.contains('exceeded')) {
    return 'That profile photo is too large. Try a smaller image.';
  }

  final detailed = detailedErrorMessage(error).trim();
  if (detailed.isNotEmpty) {
    return detailed;
  }

  return _messageFromText(
    error.message,
    fallback: fallback ?? 'Could not upload that file.',
  );
}

String _platformMessage(PlatformException error, {String? fallback}) {
  final text = '${error.code} ${error.message ?? ''}'.toLowerCase();

  if (text.contains('speech') || text.contains('recognition')) {
    return 'Speech recognition is not available right now.';
  }

  if (text.contains('microphone') || text.contains('permission')) {
    return 'Microphone permission is required for voice commands.';
  }

  if (text.contains('file') || text.contains('picker')) {
    return 'Could not open that file. Try choosing it again.';
  }

  return fallback ?? 'This device could not complete that action.';
}

String _messageFromText(String text, {required String fallback}) {
  final normalized = text.toLowerCase();

  if (normalized.contains('jwt') && normalized.contains('expired')) {
    return 'Your session expired. Please sign in again.';
  }

  if (normalized.contains('network') ||
      normalized.contains('socket') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('connection')) {
    return 'Could not connect. Check your internet connection and try again.';
  }

  if (normalized.contains('permission') || normalized.contains('not allowed')) {
    return 'You do not have permission to do that.';
  }

  if (normalized.contains('stage with that name already exists')) {
    return 'A stage with that name already exists in this board.';
  }

  if (normalized.contains('sign in')) {
    return 'Please sign in to continue.';
  }

  if (normalized.contains('offline ai') ||
      normalized.contains('model') ||
      normalized.contains('gemma')) {
    return 'The offline AI model could not finish that request.';
  }

  return fallback;
}
