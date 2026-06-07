import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final envKey = Platform.environment['SECURE_STORAGE_KEY_HEX'];
  final keyHex = envKey == null || envKey.trim().isEmpty
      ? secureStorageDevKeyHex
      : envKey.trim();

  if (envKey == null || envKey.trim().isEmpty) {
    print('Using dev key. Do not use this in production.');
  }

  final storage = SecureStorage(
    filePath: 'example_secure_storage.bin',
    keyHex: keyHex,
  );

  await storage.initialize();
  await storage.setString('username', 'deskaone-user');
  await storage.setInt('counter', (storage.getInt('counter') ?? 0) + 1);
  await storage.setJson('settings', {'theme': 'dark', 'notifications': true});

  print('username: ${storage.getString('username')}');
  print('counter: ${storage.getInt('counter')}');
  print('settings: ${storage.getJson('settings')}');
}
