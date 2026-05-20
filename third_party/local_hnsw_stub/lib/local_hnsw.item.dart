class LocalHnswItem<T> {
  const LocalHnswItem({required this.item, required this.vector});

  final T item;
  final List<double> vector;
}
