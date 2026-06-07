import 'dart:typed_data';

import 'package:convert/convert.dart';

/// strip0x input [String] -> ouput [String]
String strip0x(String value) {
  if (value.startsWith('0x') || value.startsWith('0X')) {
    return value.substring(2);
  }
  return value;
}

/// strip0x input [String] -> ouput [String]
String ensure0x(String v) =>
    (v.startsWith('0x') || v.startsWith('0X')) ? v : '0x$v';
String bigIntToHex(BigInt value) {
  if (value == BigInt.zero) return '0x0';
  return '0x${value.toRadixString(16)}';
}

BigInt hexToBigInt(String value) {
  if (value.startsWith('0x')) {
    value = value.substring(2);
  }
  if (value.isEmpty) return BigInt.zero;
  return BigInt.parse(value, radix: 16);
}

Uint8List hexToBytes(String value) {
  return Uint8List.fromList(hex.decode(strip0x(value)));
}

String bytesToHex(Uint8List value) {
  return hex.encode(value);
}

Uint8List bigIntToBytes(BigInt v, {int length = 32}) {
  if (v < BigInt.zero) {
    throw ArgumentError('Negative BigInt not supported');
  }

  final bytes = Uint8List(length);
  var temp = v;

  for (int i = length - 1; i >= 0; i--) {
    bytes[i] = (temp & BigInt.from(0xff)).toInt();
    temp >>= 8;
  }

  if (temp != BigInt.zero) {
    throw ArgumentError('BigInt too large to fit in $length bytes');
  }

  return bytes;
}

BigInt bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List intToBytes(int value) {
  if (value == 0) return Uint8List.fromList([]);

  final hexValue = value.toRadixString(16);
  final paddedHex = hexValue.length.isOdd ? '0$hexValue' : hexValue;
  return Uint8List.fromList(hex.decode(paddedHex));
}

int bytesToInt(Uint8List bytes) {
  int result = 0;
  for (final b in bytes) {
    result = (result << 8) | b;
  }
  return result;
}

int hexToInt(String value) {
  if (value.startsWith('0x')) {
    value = value.substring(2);
  }
  if (value.isEmpty) return 0;
  return int.parse(value, radix: 16);
}

String intToHex(int value) {
  if (value == 0) return '0x0';
  return '0x${value.toRadixString(16)}';
}
