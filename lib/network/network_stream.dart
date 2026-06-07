import 'dart:convert';
import 'dart:typed_data';

const int maxFrameSize = 256 * 1024;

enum SeekOrigin { begin, current, end }

class NetworkStream {
  final List<int> _buffer = <int>[];
  int _position = 0;
  int _length = 0;

  NetworkStream([List<int>? bytes]) {
    if (bytes != null) {
      _buffer.addAll(bytes);
      _length = bytes.length;
    }
  }

  int get position => _position;
  int get length => _length;
  int get remaining => _length - _position;

  Uint8List toBytes() => Uint8List.fromList(_buffer.take(_length).toList());

  void reset() {
    _position = 0;
    _length = 0;
    _buffer.clear();
  }

  void setPosition(int position) {
    if (position < 0 || position > _length) {
      throw RangeError.range(position, 0, _length, 'position');
    }
    _position = position;
  }

  void seek(int offset, SeekOrigin origin) {
    final base = switch (origin) {
      SeekOrigin.begin => 0,
      SeekOrigin.current => _position,
      SeekOrigin.end => _length,
    };
    setPosition(base + offset);
  }

  int readByte() {
    _ensureReadable(1);
    return _buffer[_position++];
  }

  bool readBool() => readByte() != 0;

  int readInt16() => _readData(2).getInt16(0, Endian.little);
  int readInt32() => _readData(4).getInt32(0, Endian.little);
  int readInt64() => _readData(8).getInt64(0, Endian.little);
  double readFloat32() => _readData(4).getFloat32(0, Endian.little);
  double readFloat64() => _readData(8).getFloat64(0, Endian.little);
  double readDouble() => readFloat64();

  Uint8List readBytes(int length) {
    if (length < 0 || length > maxFrameSize) {
      throw RangeError.range(length, 0, maxFrameSize, 'length');
    }
    _ensureReadable(length);
    final bytes = Uint8List.fromList(
      _buffer.sublist(_position, _position + length),
    );
    _position += length;
    return bytes;
  }

  String readString() {
    final byteLength = readInt32();
    if (byteLength < 0 || byteLength > maxFrameSize) {
      throw RangeError.range(byteLength, 0, maxFrameSize, 'byteLength');
    }
    return utf8.decode(readBytes(byteLength));
  }

  void writeByte(int value) {
    RangeError.checkValueInInterval(value, 0, 255, 'value');
    _writeBytes([value]);
  }

  void writeBool(bool value) => writeByte(value ? 1 : 0);

  void writeInt16(int value) =>
      _writeData(2, (data) => data.setInt16(0, value, Endian.little));
  void writeInt32(int value) =>
      _writeData(4, (data) => data.setInt32(0, value, Endian.little));
  void writeInt64(int value) =>
      _writeData(8, (data) => data.setInt64(0, value, Endian.little));
  void writeFloat32(double value) =>
      _writeData(4, (data) => data.setFloat32(0, value, Endian.little));
  void writeFloat64(double value) =>
      _writeData(8, (data) => data.setFloat64(0, value, Endian.little));
  void writeDouble(double value) => writeFloat64(value);

  void writeBytes(List<int> bytes) {
    if (bytes.length > maxFrameSize) {
      throw RangeError.range(bytes.length, 0, maxFrameSize, 'bytes.length');
    }
    _writeBytes(bytes);
  }

  void writeString(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > maxFrameSize) {
      throw RangeError.range(
        bytes.length,
        0,
        maxFrameSize,
        'value byte length',
      );
    }
    writeInt32(bytes.length);
    writeBytes(bytes);
  }

  ByteData _readData(int byteLength) {
    final bytes = readBytes(byteLength);
    return ByteData.sublistView(bytes);
  }

  void _writeData(int byteLength, void Function(ByteData data) write) {
    final bytes = Uint8List(byteLength);
    final data = ByteData.sublistView(bytes);
    write(data);
    _writeBytes(bytes);
  }

  void _writeBytes(List<int> bytes) {
    final requiredLength = _position + bytes.length;
    while (_buffer.length < requiredLength) {
      _buffer.add(0);
    }

    for (var i = 0; i < bytes.length; i++) {
      _buffer[_position + i] = bytes[i];
    }

    _position = requiredLength;
    if (_position > _length) {
      _length = _position;
    }
  }

  void _ensureReadable(int byteLength) {
    if (byteLength < 0 || byteLength > maxFrameSize) {
      throw RangeError.range(byteLength, 0, maxFrameSize, 'byteLength');
    }
    if (_position + byteLength > _length) {
      throw StateError('not enough bytes remaining');
    }
  }
}
