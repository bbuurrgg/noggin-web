import 'package:flutter/foundation.dart';

class FeatureFlags {
  static const sentenceCaseFormattingEnabled = bool.fromEnvironment(
    'FEATURE_SENTENCE_CASE_FORMATTING',
    defaultValue: false,
  );

  static const offlineAiEnabled = !kIsWeb;
}
