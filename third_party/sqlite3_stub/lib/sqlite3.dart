final sqlite3 = Sqlite3();

class Sqlite3 {
  const Sqlite3();

  Database open(String path) {
    throw UnsupportedError('Native sqlite3 is not available on this platform.');
  }
}

abstract class Database {
  void execute(String sql, [List<Object?> parameters = const []]);

  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]);

  void close();
}
