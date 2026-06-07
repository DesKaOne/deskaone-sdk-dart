import 'dart:convert';
import 'dart:typed_data';

extension BytesExt on Uint8List {
  static Uint8List get zero => Uint8List(0);

  static Uint8List fromInt(int input) {
    if (input < 0) {
      throw ArgumentError.value(input, 'input', 'must be non-negative');
    }
    if (input == 0) {
      return Uint8List.fromList([0]);
    }

    final bytes = <int>[];
    var value = input;
    while (value > 0) {
      bytes.add(value & 0xff);
      value >>= 8;
    }
    return Uint8List.fromList(bytes.reversed.toList());
  }

  static Uint8List fromHex(
    String hex, {
    bool allow0x = true,
    bool allowSpaces = false,
  }) {
    final normalized = _normalizeHex(
      hex,
      allow0x: allow0x,
      allowSpaces: allowSpaces,
    );
    if (normalized.length.isOdd) {
      throw FormatException('hex string must contain an even number of digits', hex);
    }

    final out = Uint8List(normalized.length ~/ 2);
    decodeHexInto(normalized, out, allow0x: false);
    return out;
  }

  static Uint8List? tryFromHex(String hex, {bool allow0x = true}) {
    try {
      return fromHex(hex, allow0x: allow0x);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on RangeError {
      return null;
    }
  }

  static int decodeHexInto(
    String hex,
    Uint8List out, {
    int outOffset = 0,
    bool allow0x = true,
  }) {
    final normalized = _normalizeHex(hex, allow0x: allow0x);
    if (normalized.length.isOdd) {
      throw FormatException('hex string must contain an even number of digits', hex);
    }
    if (outOffset < 0 || outOffset > out.length) {
      throw RangeError.range(outOffset, 0, out.length, 'outOffset');
    }

    final byteLength = normalized.length ~/ 2;
    if (outOffset + byteLength > out.length) {
      throw RangeError.range(
        outOffset + byteLength,
        0,
        out.length,
        'outOffset + decoded length',
      );
    }

    for (var i = 0; i < byteLength; i++) {
      final high = _hexNibble(normalized.codeUnitAt(i * 2), hex);
      final low = _hexNibble(normalized.codeUnitAt(i * 2 + 1), hex);
      out[outOffset + i] = (high << 4) | low;
    }
    return byteLength;
  }

  static int? tryDecodeHexInto(
    String hex,
    Uint8List out, {
    int outOffset = 0,
    bool allow0x = true,
  }) {
    try {
      return decodeHexInto(hex, out, outOffset: outOffset, allow0x: allow0x);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on RangeError {
      return null;
    }
  }

  static int hexLength(String hex, {bool allow0x = true}) {
    final normalized = _normalizeHex(hex, allow0x: allow0x);
    if (normalized.length.isOdd) {
      throw FormatException('hex string must contain an even number of digits', hex);
    }
    for (var i = 0; i < normalized.length; i++) {
      _hexNibble(normalized.codeUnitAt(i), hex);
    }
    return normalized.length ~/ 2;
  }

  String hex({bool lowerCase = true}) {
    final alphabet = lowerCase ? _lowerHex : _upperHex;
    final chars = StringBuffer();
    for (final byte in this) {
      chars
        ..write(alphabet[(byte >> 4) & 0x0f])
        ..write(alphabet[byte & 0x0f]);
    }
    return chars.toString();
  }

  String hex0x({bool lowerCase = true}) => '0x${hex(lowerCase: lowerCase)}';

  String get b64Encode => base64Encode(this);

  String get toUtf8String => utf8.decode(this);

  String get decode => toUtf8String;
}

const _lowerHex = '0123456789abcdef';
const _upperHex = '0123456789ABCDEF';

String _normalizeHex(
  String hex, {
  required bool allow0x,
  bool allowSpaces = false,
}) {
  var value = hex;
  if (allowSpaces) {
    value = value.replaceAll(RegExp(r'\s+'), '');
  } else if (value.contains(RegExp(r'\s'))) {
    throw FormatException('hex string must not contain whitespace', hex);
  }
  if (value.startsWith('0x') || value.startsWith('0X')) {
    if (!allow0x) {
      throw FormatException('0x prefix is not allowed', hex);
    }
    value = value.substring(2);
  }
  return value;
}

int _hexNibble(int codeUnit, String source) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) {
    return codeUnit - 0x30;
  }
  if (codeUnit >= 0x61 && codeUnit <= 0x66) {
    return codeUnit - 0x61 + 10;
  }
  if (codeUnit >= 0x41 && codeUnit <= 0x46) {
    return codeUnit - 0x41 + 10;
  }
  throw FormatException('invalid hex digit', source);
}
