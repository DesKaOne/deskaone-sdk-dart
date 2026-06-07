import 'package:postgres/postgres.dart' as pg;

import 'database_config.dart';
import 'database_driver.dart';

class PostgresDatabase implements DatabaseDriver {
  final DatabaseConfig config;
  pg.Connection? _connection;
  pg.Session? _session;

  PostgresDatabase(this.config) {
    if (config.dialect != DatabaseDialect.postgres) {
      throw ArgumentError.value(config.dialect, 'dialect', 'must be postgres');
    }
  }

  PostgresDatabase._transaction(this.config, this._session);

  @override
  bool get isOpen => _session?.isOpen ?? _connection?.isOpen ?? false;

  @override
  Future<void> open() async {
    if (_connection != null || _session != null) {
      return;
    }

    final url = config.url;
    _connection = url != null && url.isNotEmpty
        ? await pg.Connection.openFromUrl(url)
        : await pg.Connection.openFromUrl(_connectionUrl(config));
  }

  @override
  Future<void> close() async {
    await _connection?.close();
    _connection = null;
    _session = null;
  }

  @override
  Future<int> execute(String sql, [List<Object?> params = const []]) async {
    final result = await _execute(sql, params, ignoreRows: true);
    return result.affectedRows;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final result = await _execute(sql, params);
    return result.map((row) => row.toColumnMap()).toList();
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
    if (_session != null) {
      return action(this);
    }

    final connection = _connection;
    if (connection == null) {
      throw StateError('database is not open');
    }

    return connection.runTx((session) {
      return action(PostgresDatabase._transaction(config, session));
    });
  }

  Future<pg.Result> _execute(
    String sql,
    List<Object?> params, {
    bool ignoreRows = false,
  }) async {
    final session = _session ?? _connection;
    if (session == null || !session.isOpen) {
      throw StateError('database is not open');
    }

    final converted = convertQuestionMarksToPostgresPlaceholders(sql);
    final parameters = <String, Object?>{};
    for (var i = 0; i < params.length; i++) {
      parameters['p${i + 1}'] = params[i];
    }

    return session.execute(
      pg.Sql.named(converted),
      parameters: parameters,
      ignoreRows: ignoreRows,
    );
  }
}

/// Converts public `?` placeholders into postgres named placeholders.
///
/// For example, `WHERE id = ? AND name = ?` becomes
/// `WHERE id = @p1 AND name = @p2`. Question marks inside quoted strings,
/// quoted identifiers, and SQL comments are left unchanged.
String convertQuestionMarksToPostgresPlaceholders(String sql) {
  final out = StringBuffer();
  var index = 1;
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var inLineComment = false;
  var inBlockComment = false;

  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (inLineComment) {
      out.write(char);
      if (char == '\n') {
        inLineComment = false;
      }
      continue;
    }

    if (inBlockComment) {
      out.write(char);
      if (char == '*' && next == '/') {
        out.write(next);
        i++;
        inBlockComment = false;
      }
      continue;
    }

    if (inSingleQuote) {
      out.write(char);
      if (char == "'" && next == "'") {
        out.write(next);
        i++;
      } else if (char == "'") {
        inSingleQuote = false;
      }
      continue;
    }

    if (inDoubleQuote) {
      out.write(char);
      if (char == '"' && next == '"') {
        out.write(next);
        i++;
      } else if (char == '"') {
        inDoubleQuote = false;
      }
      continue;
    }

    if (char == '-' && next == '-') {
      out.write(char);
      out.write(next);
      i++;
      inLineComment = true;
      continue;
    }

    if (char == '/' && next == '*') {
      out.write(char);
      out.write(next);
      i++;
      inBlockComment = true;
      continue;
    }

    if (char == "'") {
      inSingleQuote = true;
      out.write(char);
      continue;
    }

    if (char == '"') {
      inDoubleQuote = true;
      out.write(char);
      continue;
    }

    if (char == '?') {
      out.write('@p${index++}');
    } else {
      out.write(char);
    }
  }

  return out.toString();
}

String _connectionUrl(DatabaseConfig config) {
  final user = config.username;
  final password = config.password;
  final userInfo = user == null
      ? null
      : password == null
          ? Uri.encodeComponent(user)
          : '${Uri.encodeComponent(user)}:${Uri.encodeComponent(password)}';
  final query = <String, String>{
    ...config.options,
    if (config.ssl) 'sslmode': 'require',
  };
  return Uri(
    scheme: 'postgresql',
    userInfo: userInfo ?? '',
    host: config.host ?? 'localhost',
    port: config.port ?? 5432,
    pathSegments: [config.database],
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
