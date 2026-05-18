import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/drive_file_link.dart';
import 'supabase_drive_link_repository.dart';

final driveLinkRepositoryProvider = Provider<SupabaseDriveLinkRepository>((
  ref,
) {
  return SupabaseDriveLinkRepository(ref.watch(supabaseClientProvider));
});

final driveLinksForTaskProvider = StreamProvider.autoDispose
    .family<List<DriveFileLink>, String>((ref, taskId) {
      return ref.watch(driveLinkRepositoryProvider).watchTaskLinks(taskId);
    });

final driveLinksForMessageProvider = StreamProvider.autoDispose
    .family<List<DriveFileLink>, String>((ref, messageId) {
      return ref
          .watch(driveLinkRepositoryProvider)
          .watchMessageLinks(messageId);
    });
