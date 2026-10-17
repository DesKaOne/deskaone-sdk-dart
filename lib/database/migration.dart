import 'dart:io';

import 'database_driver.dart';

/// Go DatabaseEngine.Migrate equivalent: apply ordered statements atomically.
///
/// Migrations are not version-tracked, matching the Go SDK. Callers should
/// supply idempotent statements (CREATE TABLE IF NOT EXISTS, etc).
class DatabaseMigrations {
  const DatabaseMigrations._();

  static Future<void> run(
    DatabaseDriver database,
    Iterable<String> migrations,
  ) async {
    final statements = migrations
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (statements.isEmpty) return;

    await database.transaction<void>((tx) async {
      for (var i = 0; i < statements.length; i++) {
        try {
          await tx.execute(statements[i]);
        } catch (error) {
          throw StateError('migration $i failed: $error');
        }
      }
    });
  }

  /// Loads Go-style SQL files in order. Statements are ended by a semicolon
  /// at the end of a non-comment line, like Go's loadSQLFiles helper.
  ///
  /// SQL routines / trigger bodies with inner semicolons should be provided
  /// directly to [run] as individual full statement strings instead.
  static Future<List<String>> loadFiles(Iterable<String> paths) async {
    final result = <String>[];
    final buffer = StringBuffer();

    for (final path in paths) {
      final content = await File(path).readAsString();
      for (final line in content.split('\n')) {
        final current = line.trim();
        if (current.isEmpty || current.startsWith('--')) continue;
        if (current.endsWith(';')) {
          buffer.write(current.substring(0, current.length - 1));
          final statement = buffer.toString().trim();
          if (statement.isNotEmpty) result.add(statement);
          buffer.clear();
        } else {
          buffer.write(current);
          buffer.write(' ');
        }
      }
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) result.add(tail);
    return result;
  }

  static Future<void> runFiles(
    DatabaseDriver database,
    Iterable<String> paths,
  ) async {
    await run(database, await loadFiles(paths));
  }
}
