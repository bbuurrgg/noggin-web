import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/feature_flags.dart';
import 'core/config/supabase_config.dart';
import 'features/ai_control/data/gemma_runtime.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (FeatureFlags.offlineAiEnabled) {
    await GemmaRuntime.initialize();
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const ProviderScope(child: CraneTaskApp()));
}
