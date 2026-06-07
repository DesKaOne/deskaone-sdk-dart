import 'dart:typed_data';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('reads and writes all primitive types in little endian order', () {
    final stream = NetworkStream()
      ..writeByte(0x7f)
      ..writeBool(true)
      ..writeBool(false)
      ..writeInt16(-1234)
      ..writeInt32(-12345678)
      ..writeInt64(-1234567890123)
      ..writeFloat32(1.5)
      ..writeFloat64(2.25)
      ..writeDouble(3.5)
      ..writeBytes([1, 2, 3])
      ..writeString('hello 😄');

    expect(stream.length, greaterThan(0));
    expect(stream.position, stream.length);

    stream.setPosition(0);
    expect(stream.readByte(), 0x7f);
    expect(stream.readBool(), isTrue);
    expect(stream.readBool(), isFalse);
    expect(stream.readInt16(), -1234);
    expect(stream.readInt32(), -12345678);
    expect(stream.readInt64(), -1234567890123);
    expect(stream.readFloat32(), closeTo(1.5, 0.00001));
    expect(stream.readFloat64(), closeTo(2.25, 0.00001));
    expect(stream.readDouble(), closeTo(3.5, 0.00001));
    expect(stream.readBytes(3), Uint8List.fromList([1, 2, 3]));
    expect(stream.readString(), 'hello 😄');
    expect(stream.remaining, 0);
  });

  test('string is encoded as int32 byte length followed by utf8 bytes', () {
    final stream = NetworkStream()..writeString('é');

    expect(stream.toBytes(), Uint8List.fromList([2, 0, 0, 0, 0xc3, 0xa9]));
    stream.setPosition(0);
    expect(stream.readString(), 'é');
  });

  test('position helpers support reset, setPosition, and seek', () {
    final stream = NetworkStream([1, 2, 3, 4]);

    stream.setPosition(2);
    expect(stream.position, 2);
    stream.seek(-1, SeekOrigin.current);
    expect(stream.readByte(), 2);
    stream.seek(-1, SeekOrigin.end);
    expect(stream.readByte(), 4);
    stream.reset();
    expect(stream.position, 0);
    expect(stream.length, 0);
  });

  test('readBytes validates max frame size and remaining data', () {
    final stream = NetworkStream([1, 2]);

    expect(() => stream.readBytes(maxFrameSize + 1), throwsRangeError);
    expect(() => stream.readBytes(3), throwsStateError);
  });

  test('readString validates encoded length', () {
    final stream = NetworkStream()..writeInt32(maxFrameSize + 1);

    stream.setPosition(0);
    expect(() => stream.readString(), throwsRangeError);
  });
}
