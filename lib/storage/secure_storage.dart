import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import '../utils/bytes_ext.dart';
import '../utils/logger.dart';

/// Development-only AES key for examples and tests.
///
/// Do not use this key in production. Set your own random key through an
/// environment variable or secret manager instead.
const String secureStorageDevKeyHex =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

class SecureStorageException implements Exception {
  final String message;

  const SecureStorageException(this.message);

  @override
  String toString() => message;
}

class SecureStorage {
  static const List<int> _magic = [0x44, 0x53, 0x4b, 0x53]; // DSKS.
  static const int _version = 1;
  static const int _ivLength = 16;
  static const int _hmacLength = 32;

  final bool debug;
  final Logger? logger;
  final String filePath;
  final Uint8List _aesKey;
  final Uint8List _hmacKey;
  final Random _random = Random.secure();

  Map<String, dynamic> _data = <String, dynamic>{};
  bool _initialized = false;

  SecureStorage({
    this.debug = false,
    this.logger,
    this.filePath = 'secure_storage.bin',
    required String keyHex,
  }) : _aesKey = _decodeKeyHex(keyHex),
       _hmacKey = _deriveHmacKey(_decodeKeyHex(keyHex));

  String get backupFilePath => _backupPath(filePath);
  String get debugFilePath => _debugPath(filePath);

  Future<void> initialize() async {
    try {
      _data = await _readStore(File(filePath));
    } catch (_) {
      if (!await restoreFromBackup()) {
        _data = <String, dynamic>{};
        await _save();
      }
    }
    _initialized = true;
  }

  dynamic get(String key) {
    _ensureInitialized();
    return _data[key];
  }

  String? getString(String key) => get(key) as String?;
  int? getInt(String key) => get(key) as int?;

  double? getDouble(String key) {
    final value = get(key);
    return value is num ? value.toDouble() : null;
  }

  bool? getBoolOrNull(String key) => get(key) as bool?;

  bool getBool(String key, {bool defaultValue = false}) {
    return getBoolOrNull(key) ?? defaultValue;
  }

  Map<String, dynamic> getJson(String key) {
    final value = get(key);
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<String> getStringList(String key) {
    final value = get(key);
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return <String>[];
  }

  List<dynamic> getListData(String key) {
    final value = get(key);
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[];
  }

  bool containsKey(String key) {
    _ensureInitialized();
    return _data.containsKey(key);
  }

  Set<String> getKeys() {
    _ensureInitialized();
    return Set<String>.from(_data.keys);
  }

  Future<void> set(String key, dynamic value) async {
    _ensureInitialized();
    jsonEncode(value);
    _data[key] = value;
    await _save();
  }

  Future<void> setString(String key, String value) => set(key, value);
  Future<void> setInt(String key, int value) => set(key, value);
  Future<void> setDouble(String key, double value) => set(key, value);
  Future<void> setBool(String key, bool value) => set(key, value);
  Future<void> setJson(String key, Map<String, dynamic> value) => set(key, value);
  Future<void> setStringList(String key, List<String> value) => set(key, value);

  Future<void> delete(String key) async {
    _ensureInitialized();
    _data.remove(key);
    await _save();
  }

  Future<void> clear() async {
    _ensureInitialized();
    _data.clear();
    await _save();
  }

  Future<bool> restoreFromBackup() async {
    final backup = File(backupFilePath);
    try {
      final recovered = await _readStore(backup);
      _data = recovered;
      await _writeAtomic(File(filePath), _encodeStore(_data));
      if (debug) {
        await _writeDebugDump();
      }
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> reload() async {
    _ensureInitialized();
    try {
      _data = await _readStore(File(filePath));
    } catch (_) {
      if (!await restoreFromBackup()) {
        _data = <String, dynamic>{};
        await _save();
      }
    }
  }

  Future<void> _save() async {
    final main = File(filePath);
    if (await main.exists()) {
      await _ensureParentDirectory(backupFilePath);
      await main.copy(backupFilePath);
    }
    await _writeAtomic(main, _encodeStore(_data));
    if (debug) {
      await _writeDebugDump();
    }
  }

  Future<Map<String, dynamic>> _readStore(File file) async {
    if (!await file.exists()) {
      throw const SecureStorageException('secure storage file does not exist');
    }
    final encoded = await file.readAsBytes();
    final plainText = utf8.decode(_decryptFile(Uint8List.fromList(encoded)));
    final decoded = jsonDecode(plainText);
    if (decoded is! Map) {
      throw const SecureStorageException('secure storage JSON root must be an object');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Uint8List _encodeStore(Map<String, dynamic> data) {
    final jsonText = jsonEncode(data);
    final plain = Uint8List.fromList(utf8.encode(jsonText));
    final iv = Uint8List.fromList(List<int>.generate(_ivLength, (_) => _random.nextInt(256)));
    final ciphertext = _cryptPadded(encrypt: true, input: plain, iv: iv);

    final body = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..addByte(iv.length)
      ..add(iv)
      ..add(_uint32(ciphertext.length))
      ..add(ciphertext);
    final bytesWithoutHmac = body.takeBytes();
    final hmac = _hmac(bytesWithoutHmac);
    return (BytesBuilder(copy: false)
          ..add(bytesWithoutHmac)
          ..add(hmac))
        .takeBytes();
  }

  Uint8List _decryptFile(Uint8List bytes) {
    final minLength = _magic.length + 1 + 1 + _ivLength + 4 + _hmacLength;
    if (bytes.length < minLength) {
      throw const SecureStorageException('secure storage file is too short');
    }

    final bodyLength = bytes.length - _hmacLength;
    final body = Uint8List.sublistView(bytes, 0, bodyLength);
    final actualHmac = Uint8List.sublistView(bytes, bodyLength);
    final expectedHmac = _hmac(body);
    if (!_constantTimeEquals(actualHmac, expectedHmac)) {
      throw const SecureStorageException('secure storage HMAC verification failed');
    }

    var offset = 0;
    for (final expected in _magic) {
      if (bytes[offset++] != expected) {
        throw const SecureStorageException('invalid secure storage magic');
      }
    }
    if (bytes[offset++] != _version) {
      throw const SecureStorageException('unsupported secure storage version');
    }

    final ivLength = bytes[offset++];
    if (ivLength != _ivLength) {
      throw const SecureStorageException('invalid secure storage IV length');
    }
    final iv = Uint8List.sublistView(bytes, offset, offset + ivLength);
    offset += ivLength;

    final ciphertextLength = _readUint32(bytes, offset);
    offset += 4;
    if (offset + ciphertextLength != bodyLength) {
      throw const SecureStorageException('invalid secure storage ciphertext length');
    }
    final ciphertext = Uint8List.sublistView(bytes, offset, offset + ciphertextLength);
    return _cryptPadded(encrypt: false, input: ciphertext, iv: iv);
  }

  Uint8List _cryptPadded({
    required bool encrypt,
    required Uint8List input,
    required Uint8List iv,
  }) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      encrypt,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(_aesKey), iv),
        null,
      ),
    );
    return cipher.process(input);
  }

  Uint8List _hmac(Uint8List input) {
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(_hmacKey));
    return hmac.process(input);
  }

  Future<void> _writeAtomic(File file, Uint8List bytes) async {
    await _ensureParentDirectory(file.path);
    final temp = File('${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await temp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Future<void> _writeDebugDump() async {
    final dump = const JsonEncoder.withIndent('  ').convert(_data);
    await _writeAtomic(File(debugFilePath), Uint8List.fromList(utf8.encode(dump)));
    logger?.warn('SecureStorage debug JSON dump is enabled; plaintext data is exposed.');
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('SecureStorage.initialize() must be called first');
    }
  }
}

Uint8List _decodeKeyHex(String keyHex) {
  final Uint8List key;
  try {
    key = BytesExt.fromHex(keyHex, allowSpaces: true);
  } on FormatException catch (error) {
    throw FormatException('invalid keyHex: ${error.message}');
  }
  if (key.length != 16 && key.length != 24 && key.length != 32) {
    throw ArgumentError('keyHex must decode to 16, 24, or 32 bytes');
  }
  return key;
}

Uint8List _deriveHmacKey(Uint8List aesKey) {
  final input = Uint8List.fromList([...utf8.encode('hmac:'), ...aesKey]);
  return SHA256Digest().process(input);
}

Uint8List _uint32(int value) {
  if (value < 0 || value > 0xffffffff) {
    throw RangeError.range(value, 0, 0xffffffff, 'value');
  }
  return Uint8List(4)
    ..[0] = (value >> 24) & 0xff
    ..[1] = (value >> 16) & 0xff
    ..[2] = (value >> 8) & 0xff
    ..[3] = value & 0xff;
}

int _readUint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Future<void> _ensureParentDirectory(String filePath) async {
  final parent = File(filePath).parent;
  if (parent.path == '.' || await parent.exists()) {
    return;
  }
  await parent.create(recursive: true);
}

String _backupPath(String filePath) {
  final directory = p.dirname(filePath);
  final extension = p.extension(filePath);
  final basename = p.basenameWithoutExtension(filePath);
  return p.join(directory, '$basename.backup$extension');
}

String _debugPath(String filePath) {
  final directory = p.dirname(filePath);
  final extension = p.extension(filePath);
  final basename = p.basenameWithoutExtension(filePath);
  return p.join(directory, '$basename.debug$extension.json');
}
