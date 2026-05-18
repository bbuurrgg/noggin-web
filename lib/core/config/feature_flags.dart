class FeatureFlags {
  static const sentenceCaseFormattingEnabled = bool.fromEnvironment(
    'FEATURE_SENTENCE_CASE_FORMATTING',
    defaultValue: false,
  );
}
