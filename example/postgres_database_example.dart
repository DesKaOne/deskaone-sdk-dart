import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final databaseUrl = Platform.environment['DATABASE_URL'];
  if (databaseUrl == null || databaseUrl.trim().isEmpty) {
    print('Set DATABASE_URL to run the PostgreSQL example.');
    return;
  }

  final db = Database.fromUrl(databaseUrl);
  await db.open();
  try {
    final row = await db.queryOne('SELECT 1 AS value');
    print(row);
  } finally {
    await db.close();
  }
}
