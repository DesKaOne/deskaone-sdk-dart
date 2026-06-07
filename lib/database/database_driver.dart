abstract interface class DatabaseDriver {
  Future<void> open();
  Future<void> close();
  Future<int> execute(String sql, [List<Object?> params = const []]);
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> params = const []]);
  Future<Map<String, Object?>?> queryOne(String sql, [List<Object?> params = const []]);
  Future<T> transaction<T>(Future<T> Function(DatabaseDriver tx) action);
  bool get isOpen;
}
