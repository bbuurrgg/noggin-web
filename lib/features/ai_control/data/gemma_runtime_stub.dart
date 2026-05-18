import '../domain/offline_model_type.dart';

class GemmaRuntime {
  const GemmaRuntime._();

  static Future<void> initialize() async {}

  static bool hasActiveModel() => false;

  static Future<List<String>> listInstalledModels() async => const [];

  static Future<void> installModelFromFile({
    required String path,
    required OfflineModelType modelType,
  }) {
    throw StateError('Offline AI models are not available on web.');
  }

  static Future<String> generateText({
    required String prompt,
    required int maxTokens,
  }) {
    throw StateError('Offline AI models are not available on web.');
  }
}
