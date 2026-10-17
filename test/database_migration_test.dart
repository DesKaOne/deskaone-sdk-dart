import 'dart:io';

import 'package:deskaone_sdk/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('migrations run atomically on SQLite', () async {
    final db = Database.sqlite(':memory:');
    await db.open();
    try {
      await db.migrate([
        'CREATE TABLE test_items (id INTEGER)',
        'INSERT INTO test_items VALUES (1)',
      ]);
      expect(
        (await db.queryOne('SELECT COUNT(*) AS n FROM test_items'))?['n'],
        1,
      );

      await expectLater(
        db.migrate([
          'INSERT INTO test_items VALUES (2)',
          'INSERT INTO nonexistent_table VALUES (3)',
        ]),
        throwsStateError,
      );
      expect(
        (await db.queryOne('SELECT COUNT(*) AS n FROM test_items'))?['n'],
        1,
      );
    } finally {
      await db.close();
    }
  });

  test('SQL file loader follows Go line-based migration format', () async {
    final dir = await Directory.systemTemp.createTemp('sdk_migrate_');
    try {
      final file = File('${dir.path}/001_init.sql');
      await file.writeAsString(
        '-- comment\nCREATE TABLE demo (id INTEGER);\n'
        'INSERT INTO demo (id)\nVALUES (1);\n',
      );
      final statements = await DatabaseMigrations.loadFiles([file.path]);
      expect(statements, [
        'CREATE TABLE demo (id INTEGER)',
        'INSERT INTO demo (id) VALUES (1)',
      ]);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
