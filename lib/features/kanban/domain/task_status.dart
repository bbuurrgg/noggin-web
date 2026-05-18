enum TaskStatus {
  todo('todo', 'To Do'),
  inProgress('in_progress', 'In Progress'),
  done('done', 'Done');

  const TaskStatus(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static TaskStatus fromTranscript(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ');
    if (normalized.contains('progress') || normalized.contains('doing')) {
      return TaskStatus.inProgress;
    }
    if (normalized.contains('done') ||
        normalized.contains('complete') ||
        normalized.contains('finished')) {
      return TaskStatus.done;
    }
    return TaskStatus.todo;
  }

  static TaskStatus fromStorage(String value) {
    return TaskStatus.values.firstWhere(
      (status) => status.storageValue == value,
      orElse: () => TaskStatus.todo,
    );
  }
}
