import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlite-db-test-');
    db = Database.sqlite('${tempDir.path}/test.db');
    await db.open();
    await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('create table, insert, query, queryOne, update, and delete', () async {
    await db.execute('INSERT INTO users (name, age) VALUES (?, ?)', ['Alice', 30]);
    await db.execute('INSERT INTO users (name, age) VALUES (?, ?)', ['Bob', 25]);

    final rows = await db.query('SELECT name, age FROM users ORDER BY age');
    expect(rows, [
      {'name': 'Bob', 'age': 25},
      {'name': 'Alice', 'age': 30},
    ]);

    final one = await db.queryOne('SELECT name, age FROM users WHERE name = ?', ['Alice']);
    expect(one, {'name': 'Alice', 'age': 30});

    final updated = await db.execute('UPDATE users SET age = ? WHERE name = ?', [31, 'Alice']);
    expect(updated, 1);
    expect((await db.queryOne('SELECT age FROM users WHERE name = ?', ['Alice']))?['age'], 31);

    final deleted = await db.execute('DELETE FROM users WHERE name = ?', ['Bob']);
    expect(deleted, 1);
    expect(await db.query('SELECT * FROM users'), hasLength(1));
  });

  test('transaction commit persists changes', () async {
    await db.transaction((tx) async {
      await tx.execute('INSERT INTO users (name, age) VALUES (?, ?)', ['Carol', 40]);
    });

    expect(await db.query('SELECT * FROM users WHERE name = ?', ['Carol']), hasLength(1));
  });

  test('transaction rollback discards changes', () async {
    await expectLater(
      db.transaction((tx) async {
        await tx.execute('INSERT INTO users (name, age) VALUES (?, ?)', ['Dave', 20]);
        throw StateError('rollback');
      }),
      throwsStateError,
    );

    expect(await db.query('SELECT * FROM users WHERE name = ?', ['Dave']), isEmpty);
  });
}
