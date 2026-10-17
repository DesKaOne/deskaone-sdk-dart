import 'database_config.dart';
import 'database_driver.dart';

/// Go SDK's InsertReplace, InsertIgnore and ModeUpsert equivalents.
enum InsertMode { insert, replace, ignore, upsert }

/// A typed mapping between a Dart model and a SQL table.
abstract interface class EngineSpec<Entity, Key> {
  String get table;
  List<String> get columns;
  List<Object?> values(Entity entity);
  List<String> get conflictColumns;
  Entity fromRow(Map<String, Object?> row);
  List<String> get keyColumns;
  List<Object?> keyArgs(Key key);

  /// An integer primary key column if keyset pagination is supported.
  String? get intPrimaryKey;
}

/// Cross-database query builder, with the same public '?' parameter syntax
/// already supported by SQLiteDatabase and PostgresDatabase.
class SqlDialect {
  final DatabaseDialect database;
  const SqlDialect(this.database);

  static final RegExp _identifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  String quote(String name) {
    if (!_identifier.hasMatch(name)) {
      throw ArgumentError.value(name, 'identifier', 'invalid SQL identifier');
    }
    return '"$name"';
  }

  String quoted(List<String> names) => names.map(quote).join(', ');

  String placeholders(int count) => List<String>.filled(count, '?').join(', ');

  String insert(
    String table,
    List<String> columns, {
    InsertMode mode = InsertMode.insert,
    List<String> conflictColumns = const [],
    List<String> updateColumns = const [],
  }) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'must not be empty');
    }
    final tableName = quote(table);
    final fieldNames = quoted(columns);
    final values = placeholders(columns.length);

    final base = 'INSERT INTO $tableName ($fieldNames) VALUES ($values)';

    if (mode == InsertMode.insert) return base;
    if (mode == InsertMode.ignore) {
      if (database == DatabaseDialect.sqlite) {
        return 'INSERT OR IGNORE INTO $tableName ($fieldNames) VALUES ($values)';
      }
      return '$base ON CONFLICT DO NOTHING';
    }

    if (mode == InsertMode.replace && database == DatabaseDialect.sqlite) {
      return 'INSERT OR REPLACE INTO $tableName ($fieldNames) VALUES ($values)';
    }

    if (conflictColumns.isEmpty) {
      throw ArgumentError('conflictColumns must not be empty for upsert');
    }
    // Every conflict column must actually be in the inserted column set.
    if (!conflictColumns.every(columns.contains)) {
      throw ArgumentError('conflictColumns must be present in columns');
    }

    final updates = updateColumns.isNotEmpty
        ? updateColumns
        : columns.where((column) => !conflictColumns.contains(column)).toList();

    if (!updates.every(columns.contains)) {
      throw ArgumentError('updateColumns must be present in columns');
    }

    final target = '(${quoted(conflictColumns)})';
    if (updates.isEmpty) return '$base ON CONFLICT $target DO NOTHING';

    final assignments = updates
        .map((column) => '${quote(column)} = EXCLUDED.${quote(column)}')
        .join(', ');
    return '$base ON CONFLICT $target DO UPDATE SET $assignments';
  }

  String whereKey(List<String> keyColumns) {
    if (keyColumns.isEmpty) {
      throw ArgumentError('keyColumns must not be empty');
    }
    return keyColumns.map((column) => '${quote(column)} = ?').join(' AND ');
  }
}

/// Strongly typed CRUD helper mirroring Go's `BaseEngine<E, K>`.
///
/// The same API works on SQLite and PostgreSQL; transactions are delegated to
/// each database driver. Identifiers are validated; values use bound params.
class BaseEngine<Entity, Key> {
  final DatabaseDriver driver;
  final EngineSpec<Entity, Key> spec;
  final SqlDialect sql;

  BaseEngine({
    required this.driver,
    required DatabaseDialect dialect,
    required this.spec,
  }) : sql = SqlDialect(dialect) {
    sql.quote(spec.table);
    sql.quoted(spec.columns);
    sql.quoted(spec.keyColumns);
  }

  String get _table => sql.quote(spec.table);

  List<Object?> _values(Entity entity) {
    final values = spec.values(entity);
    if (values.length != spec.columns.length) {
      throw StateError('values count must match columns count');
    }
    return values;
  }

  Future<int> save(Entity entity, {InsertMode mode = InsertMode.insert}) {
    final query = sql.insert(
      spec.table,
      spec.columns,
      mode: mode,
      conflictColumns: spec.conflictColumns,
    );
    return driver.execute(query, _values(entity));
  }

  Future<void> saveBatch(
    Iterable<Entity> entities, {
    InsertMode mode = InsertMode.insert,
  }) async {
    final list = entities.toList();
    if (list.isEmpty) return;
    final query = sql.insert(
      spec.table,
      spec.columns,
      mode: mode,
      conflictColumns: spec.conflictColumns,
    );
    await driver.transaction((tx) async {
      for (final item in list) {
        await tx.execute(query, _values(item));
      }
    });
  }

  Future<int> upsert(Entity entity, {List<String> updateColumns = const []}) {
    final query = sql.insert(
      spec.table,
      spec.columns,
      mode: InsertMode.upsert,
      conflictColumns: spec.conflictColumns,
      updateColumns: updateColumns,
    );
    return driver.execute(query, _values(entity));
  }

  Future<void> upsertBatch(
    Iterable<Entity> entities, {
    List<String> updateColumns = const [],
  }) async {
    final list = entities.toList();
    if (list.isEmpty) return;
    final query = sql.insert(
      spec.table,
      spec.columns,
      mode: InsertMode.upsert,
      conflictColumns: spec.conflictColumns,
      updateColumns: updateColumns,
    );
    await driver.transaction((tx) async {
      for (final item in list) {
        await tx.execute(query, _values(item));
      }
    });
  }

  Future<Entity?> find(Key key) async {
    final query =
        'SELECT ${sql.quoted(spec.columns)} FROM $_table '
        'WHERE ${sql.whereKey(spec.keyColumns)} LIMIT 1';
    final row = await driver.queryOne(query, spec.keyArgs(key));
    return row == null ? null : spec.fromRow(row);
  }

  Future<List<Entity>> loadOffset({required int limit, int offset = 0}) async {
    if (limit <= 0 || offset < 0) {
      throw RangeError('limit must be positive; offset non-negative');
    }
    final rows = await driver.query(
      'SELECT ${sql.quoted(spec.columns)} FROM $_table LIMIT ? OFFSET ?',
      [limit, offset],
    );
    return rows.map(spec.fromRow).toList();
  }

  Future<List<Entity>> loadKeyset({
    required int lastId,
    required int limit,
  }) async {
    if (limit <= 0) throw RangeError.value(limit, 'limit');
    final pk = spec.intPrimaryKey;
    if (pk == null || !spec.columns.contains(pk)) {
      throw StateError('keyset pagination not supported by this spec');
    }
    final key = sql.quote(pk);
    final rows = await driver.query(
      'SELECT ${sql.quoted(spec.columns)} FROM $_table '
      'WHERE $key > ? ORDER BY $key LIMIT ?',
      [lastId, limit],
    );
    return rows.map(spec.fromRow).toList();
  }

  Future<int> delete(Key key) {
    return driver.execute(
      'DELETE FROM $_table WHERE ${sql.whereKey(spec.keyColumns)}',
      spec.keyArgs(key),
    );
  }

  Future<int> deleteAll() => driver.execute('DELETE FROM $_table');

  Future<int> count() async {
    final row = await driver.queryOne('SELECT COUNT(*) AS total FROM $_table');
    return (row?['total'] as num?)?.toInt() ?? 0;
  }

  Future<bool> isEmptyFast() async {
    final row = await driver.queryOne('SELECT 1 AS found FROM $_table LIMIT 1');
    return row == null;
  }
}
