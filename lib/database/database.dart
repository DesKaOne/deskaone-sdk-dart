import 'database_config.dart';
import 'database_driver.dart';
import 'postgres_database.dart';
import 'sqlite_database.dart';

class Database implements DatabaseDriver {
  final DatabaseDriver _driver;

  factory Database(DatabaseConfig config) {
    return switch (config.dialect) {
      DatabaseDialect.sqlite => Database._(SQLiteDatabase(config)),
      DatabaseDialect.postgres => Database._(PostgresDatabase(config)),
    };
  }

  Database._(this._driver);

  static Database sqlite(String path) => Database(DatabaseConfig.sqlite(path));

  static Database postgres({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    required String password,
    bool ssl = false,
  }) {
    return Database(
      DatabaseConfig.postgres(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        ssl: ssl,
      ),
    );
  }

  static Database fromUrl(String url) => Database(DatabaseConfig.fromUrl(url));

  @override
  bool get isOpen => _driver.isOpen;

  @override
  Future<void> open() => _driver.open();

  @override
  Future<void> close() => _driver.close();

  @override
  Future<int> execute(String sql, [List<Object?> params = const []]) {
    return _driver.execute(sql, params);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> params = const [],
  ]) {
    return _driver.query(sql, params);
  }

  @override
  Future<Map<String, Object?>?> queryOne(
    String sql, [
    List<Object?> params = const [],
  ]) {
    return _driver.queryOne(sql, params);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(DatabaseDriver tx) action) {
    return _driver.transaction(action);
  }
}
