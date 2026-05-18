import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../domain/offline_model_type.dart';

class GemmaRuntime {
  const GemmaRuntime._();

  static Future<void> initialize() {
    return FlutterGemma.initialize(maxDownloadRetries: 3);
  }

  static bool hasActiveModel() => FlutterGemma.hasActiveModel();

  static Future<List<String>> listInstalledModels() {
    return FlutterGemma.listInstalledModels();
  }

  static Future<void> installModelFromFile({
    required String path,
    required OfflineModelType modelType,
  }) async {
    await FlutterGemma.installModel(
      modelType: _toGemmaModelType(modelType),
      fileType: _fileTypeForPath(path),
    ).fromFile(path).install();
  }

  static Future<String> generateText({
    required String prompt,
    required int maxTokens,
  }) async {
    if (!FlutterGemma.hasActiveModel()) {
      throw StateError('No offline AI model is installed.');
    }

    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.cpu,
    );

    try {
      final chat = await model.createChat();
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await chat.generateChatResponse();
      return _responseToText(response).trim();
    } finally {
      await model.close();
    }
  }

  static ModelFileType _fileTypeForPath(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.bin') || lowerPath.endsWith('.tflite')) {
      return ModelFileType.binary;
    }
    return ModelFileType.task;
  }

  static ModelType _toGemmaModelType(OfflineModelType modelType) {
    return switch (modelType) {
      OfflineModelType.functionGemma => ModelType.functionGemma,
      OfflineModelType.gemmaIt => ModelType.gemmaIt,
      OfflineModelType.qwen => ModelType.qwen,
      OfflineModelType.deepSeek => ModelType.deepSeek,
      OfflineModelType.general => ModelType.general,
    };
  }

  static String _responseToText(ModelResponse response) {
    return switch (response) {
      TextResponse(:final token) => token,
      FunctionCallResponse(:final args) => jsonEncode(args),
      ThinkingResponse(:final content) => content,
    };
  }
}
