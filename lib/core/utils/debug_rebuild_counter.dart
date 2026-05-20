import 'package:flutter/foundation.dart';

class DebugRebuildCounter {
  const DebugRebuildCounter._();

  static const enabled = bool.fromEnvironment('ENABLE_REBUILD_LOGS');
  static final Map<String, int> _counts = {};

  static void mark(String label, {int logEvery = 10}) {
    if (!enabled || kReleaseMode) {
      return;
    }

    assert(() {
      final count = (_counts[label] ?? 0) + 1;
      _counts[label] = count;

      if (count <= 5 || count % logEvery == 0) {
        debugPrint('[rebuild] $label #$count');
      }
      return true;
    }());
  }

  static void reset() {
    if (!enabled || kReleaseMode) {
      return;
    }

    assert(() {
      _counts.clear();
      debugPrint('[rebuild] counters reset');
      return true;
    }());
  }
}
