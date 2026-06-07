import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final dbPath = '${Directory.systemTemp.path}/deskaone_sdk_example.db';
  final db = Database.sqlite(dbPath);

  await db.open();
  try {
    await db.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute('DELETE FROM users');
    await db.execute('INSERT INTO users (name) VALUES (?)', ['Alice']);
    await db.execute('INSERT INTO users (name) VALUES (?)', ['Bob']);

    final rows = await db.query('SELECT id, name FROM users ORDER BY id');
    for (final row in rows) {
      print(row);
    }
  } finally {
    await db.close();
  }
}
