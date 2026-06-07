import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'database_config.dart';
import 'database_driver.dart';

class SQLiteDatabase implements DatabaseDriver {
  final DatabaseConfig config;
  sqlite.Database? _db;
  bool _inTransaction = false;

  SQLiteDatabase(this.config) {
    if (config.dialect != DatabaseDialect.sqlite) {
      throw ArgumentError.value(config.dialect, 'dialect', 'must be sqlite');
    }
  }

  @override
  bool get isOpen => _db != null;

  @override
  Future<void> open() async {
    if (_db != null) {
      return;
    }
    _db = sqlite.sqlite3.open(config.database);
  }

  @override
  Future<void> close() async {
    _db?.dispose();
    _db = null;
  }

  @override
  Future<int> execute(String sql, [List<Object?> params = const []]) async {
    final db = _requireOpen();
    final statement = db.prepare(sql);
    try {
      statement.execute(params);
      return db.getUpdatedRows();
    } finally {
      statement.dispose();
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final db = _requireOpen();
    final resultSet = db.select(sql, params);
    return resultSet.map((row) => Map<String, Object?>.from(row)).toList();
  }

  @override
  Future<Map<String, Object?>?> queryOne(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final rows = await query(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(DatabaseDriver tx) action) async {
    if (_inTransaction) {
      return action(this);
    }

    _inTransaction = true;
    await execute('BEGIN');
    try {
      final result = await action(this);
      await execute('COMMIT');
      return result;
    } catch (_) {
      await execute('ROLLBACK');
      rethrow;
    } finally {
      _inTransaction = false;
    }
  }

  sqlite.Database _requireOpen() {
    final db = _db;
    if (db == null) {
      throw StateError('database is not open');
    }
    return db;
  }
}
