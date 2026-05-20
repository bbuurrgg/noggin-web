import 'dart:math' show sqrt;

import 'local_hnsw.item.dart';

enum LocalHnswMetric { cosine }

class LocalHNSW<T> {
  LocalHNSW({required this.dim, required this.metric});

  final int dim;
  final LocalHnswMetric metric;
  final Map<T, List<double>> _items = {};

  void add(LocalHnswItem<T> item) {
    if (item.vector.length != dim) {
      throw ArgumentError(
        'Vector dimension mismatch: expected $dim, got ${item.vector.length}',
      );
    }
    _items[item.item] = List<double>.unmodifiable(item.vector);
  }

  void delete(T item) {
    _items.remove(item);
  }

  LocalHnswSearchResult<T> search(List<double> query, int count) {
    if (query.length != dim) {
      throw ArgumentError(
        'Vector dimension mismatch: expected $dim, got ${query.length}',
      );
    }

    final matches =
        _items.entries
            .map(
              (entry) => (
                item: LocalHnswItem<T>(item: entry.key, vector: entry.value),
                score: _similarity(query, entry.value),
              ),
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    return LocalHnswSearchResult<T>(
      items: matches.take(count).map((match) => match.item).toList(),
    );
  }

  double _similarity(List<double> a, List<double> b) {
    return switch (metric) {
      LocalHnswMetric.cosine => _cosineSimilarity(a, b),
    };
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) {
      return 0;
    }
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}

class LocalHnswSearchResult<T> {
  const LocalHnswSearchResult({required this.items});

  final List<LocalHnswItem<T>> items;
}
