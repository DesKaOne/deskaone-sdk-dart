import 'dart:convert';
import 'dart:typed_data';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('encodes hex in lower, upper, and 0x forms', () {
    final bytes = Uint8List.fromList([0, 10, 15, 255]);

    expect(bytes.hex(), '000a0fff');
    expect(bytes.hex(lowerCase: false), '000A0FFF');
    expect(bytes.hex0x(), '0x000a0fff');
  });

  test('decodes hex with optional prefix and whitespace', () {
    expect(BytesExt.fromHex('0x00AaFF'), Uint8List.fromList([0, 170, 255]));
    expect(
      BytesExt.fromHex('00 aa FF', allowSpaces: true),
      Uint8List.fromList([0, 170, 255]),
    );
  });

  test('try hex helpers return null on invalid input', () {
    expect(BytesExt.tryFromHex('xyz'), isNull);

    final out = Uint8List(1);
    expect(BytesExt.tryDecodeHexInto('xyz', out), isNull);
  });

  test('decodeHexInto writes at offset and returns byte count', () {
    final out = Uint8List(4);

    final written = BytesExt.decodeHexInto('aabb', out, outOffset: 1);

    expect(written, 2);
    expect(out, Uint8List.fromList([0, 170, 187, 0]));
  });

  test('hexLength validates and counts decoded bytes', () {
    expect(BytesExt.hexLength('0x0011'), 2);
    expect(() => BytesExt.hexLength('abc'), throwsFormatException);
  });

  test('base64, utf8, json decode, zero, and fromInt helpers work', () {
    final jsonBytes = Uint8List.fromList(utf8.encode('{"ok":true}'));

    expect(jsonBytes.b64Encode, base64Encode(jsonBytes));
    expect(jsonBytes.toUtf8String, '{"ok":true}');
    expect(jsonBytes.decode, '{"ok":true}');
    expect(BytesExt.zero, isEmpty);
    expect(BytesExt.fromInt(0x1234), Uint8List.fromList([0x12, 0x34]));
  });

  test('throws clear errors for invalid hex options and output ranges', () {
    expect(() => BytesExt.fromHex('0x00', allow0x: false), throwsFormatException);
    expect(() => BytesExt.fromHex('00 aa'), throwsFormatException);
    expect(
      () => BytesExt.decodeHexInto('aabb', Uint8List(1)),
      throwsRangeError,
    );
    expect(() => BytesExt.fromInt(-1), throwsArgumentError);
  });
}
