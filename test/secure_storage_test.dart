import 'dart:convert';
import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String filePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('secure-storage-test-');
    filePath = '${tempDir.path}/secure_storage.bin';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  SecureStorage storage({bool debug = false}) {
    return SecureStorage(
      filePath: filePath,
      keyHex: secureStorageDevKeyHex,
      debug: debug,
    );
  }

  test('initialize creates encrypted file', () async {
    final store = storage();

    await store.initialize();

    expect(await File(filePath).exists(), isTrue);
  });

  test('set/get typed values', () async {
    final store = storage();
    await store.initialize();

    await store.setString('name', 'deskaone');
    await store.setInt('count', 7);
    await store.setDouble('ratio', 1.5);
    await store.setBool('enabled', true);
    await store.setJson('settings', {'theme': 'dark'});
    await store.setStringList('items', ['a', 'b']);
    await store.set('rawList', [1, true, 'x']);

    expect(store.getString('name'), 'deskaone');
    expect(store.getInt('count'), 7);
    expect(store.getDouble('ratio'), 1.5);
    expect(store.getBoolOrNull('enabled'), isTrue);
    expect(store.getBool('missing', defaultValue: true), isTrue);
    expect(store.getJson('settings'), {'theme': 'dark'});
    expect(store.getStringList('items'), ['a', 'b']);
    expect(store.getListData('rawList'), [1, true, 'x']);
  });

  test('containsKey, getKeys, delete, and clear work', () async {
    final store = storage();
    await store.initialize();

    await store.setString('a', 'one');
    await store.setString('b', 'two');

    expect(store.containsKey('a'), isTrue);
    expect(store.getKeys(), containsAll(['a', 'b']));

    await store.delete('a');
    expect(store.containsKey('a'), isFalse);

    await store.clear();
    expect(store.getKeys(), isEmpty);
  });

  test('reload reads values from file', () async {
    final first = storage();
    await first.initialize();
    await first.setString('name', 'persisted');

    final second = storage();
    await second.initialize();

    expect(second.getString('name'), 'persisted');
  });

  test('restoreFromBackup restores backup data', () async {
    final store = storage();
    await store.initialize();
    await store.setString('version', 'one');
    await File(filePath).copy(store.backupFilePath);
    await store.setString('version', 'two');

    final restored = await store.restoreFromBackup();

    expect(restored, isTrue);
    expect(store.getString('version'), 'one');
  });

  test('corrupted main file falls back to backup on initialize', () async {
    final first = storage();
    await first.initialize();
    await first.setString('version', 'backup');
    await File(filePath).copy(first.backupFilePath);
    await File(filePath).writeAsString('corrupted', flush: true);

    final second = storage();
    await second.initialize();

    expect(second.getString('version'), 'backup');
  });

  test('corrupted HMAC fails and falls back to backup', () async {
    final first = storage();
    await first.initialize();
    await first.setString('version', 'backup');
    await File(filePath).copy(first.backupFilePath);

    final bytes = await File(filePath).readAsBytes();
    bytes[bytes.length - 1] ^= 0xff;
    await File(filePath).writeAsBytes(bytes, flush: true);

    final second = storage();
    await second.initialize();

    expect(second.getString('version'), 'backup');
  });

  test('invalid key length throws', () {
    expect(
      () => SecureStorage(filePath: filePath, keyHex: '0011'),
      throwsArgumentError,
    );
  });

  test('debug JSON dump is created only when debug is true', () async {
    final normal = storage();
    await normal.initialize();
    await normal.setString('name', 'hidden');

    expect(await File(normal.debugFilePath).exists(), isFalse);

    final debugStore = storage(debug: true);
    await debugStore.initialize();
    await debugStore.setString('name', 'visible-in-debug');

    final debugFile = File(debugStore.debugFilePath);
    expect(await debugFile.exists(), isTrue);
    final decoded = jsonDecode(await debugFile.readAsString());
    expect(decoded['name'], 'visible-in-debug');
  });
}
