import 'package:flutter/widgets.dart';

class AvatarImageCache {
  AvatarImageCache._();

  static final Map<String, ImageProvider<Object>> _providers = {};

  static ImageProvider<Object>? provider(String? url) {
    final normalized = url?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return _providers.putIfAbsent(normalized, () => NetworkImage(normalized));
  }

  static void evict(String? url) {
    final normalized = url?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    final provider = _providers.remove(normalized);
    provider?.evict();
  }
}
