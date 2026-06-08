// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import '../english.dart';

const int SLIP39_WORD_BITS = 10;
const int SLIP39_CRC_BITS = 16;

class Slip39Group {
  final int memberThreshold;
  final int memberCount;

  const Slip39Group({required this.memberThreshold, required this.memberCount});
}

class Slip39Share {
  final int groupIndex;
  final int memberIndex;
  final String mnemonic;

  const Slip39Share({
    required this.groupIndex,
    required this.memberIndex,
    required this.mnemonic,
  });
}

class Slip39Result {
  final Uint8List masterSecret;
  final List<Slip39Share> shares;

  const Slip39Result({required this.masterSecret, required this.shares});
}

int crc16Ccitt(Uint8List data) {
  int crc = 0xFFFF;
  for (final byte in data) {
    crc ^= (byte << 8);
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }
  return crc & 0xFFFF;
}

List<int> bytesToBits(Uint8List bytes) {
  final bits = <int>[];
  for (final b in bytes) {
    for (int i = 7; i >= 0; i--) {
      bits.add((b >> i) & 1);
    }
  }
  return bits;
}

List<int> appendCrcBits(Uint8List payload) {
  final bits = bytesToBits(payload);
  final crc = crc16Ccitt(payload);

  for (int i = 15; i >= 0; i--) {
    bits.add((crc >> i) & 1);
  }

  return bits;
}

List<int> padBits(List<int> bits) {
  while (bits.length % SLIP39_WORD_BITS != 0) {
    bits.add(0);
  }
  return bits;
}

List<int> bitsToBase1024(List<int> bits) {
  final words = <int>[];
  for (int i = 0; i < bits.length; i += SLIP39_WORD_BITS) {
    int value = 0;
    for (int j = 0; j < SLIP39_WORD_BITS; j++) {
      value = (value << 1) | bits[i + j];
    }
    words.add(value);
  }
  return words;
}

String encodeSlip39Words(Uint8List payload, List<String> wordlist) {
  if (wordlist.length != 1024) {
    throw ArgumentError('SLIP39 wordlist must contain 1024 words');
  }

  final bitsWithCrc = appendCrcBits(payload);
  final paddedBits = padBits(bitsWithCrc);
  final indices = bitsToBase1024(paddedBits);

  return indices.map((i) => wordlist[i]).join(' ');
}

void slip39EncodingTest() {
  final payload = Uint8List.fromList(List.generate(16, (i) => i));

  final mnemonic = encodeSlip39Words(payload, englishSlip);

  print(mnemonic);
}

class BitWriter {
  final List<int> _bits = [];

  void write(int value, int bitCount) {
    for (int i = bitCount - 1; i >= 0; i--) {
      _bits.add((value >> i) & 1);
    }
  }

  void writeBytes(Uint8List bytes) {
    for (final b in bytes) {
      write(b, 8);
    }
  }

  Uint8List toBytes() {
    while (_bits.length % 8 != 0) {
      _bits.add(0);
    }

    final bytes = Uint8List(_bits.length ~/ 8);
    for (int i = 0; i < bytes.length; i++) {
      int v = 0;
      for (int j = 0; j < 8; j++) {
        v = (v << 1) | _bits[i * 8 + j];
      }
      bytes[i] = v;
    }
    return bytes;
  }
}

Uint8List buildSlip39Payload({
  required int identifier,
  required int iterationExponent,
  required int groupIndex,
  required int groupThreshold,
  required int groupCount,
  required int memberIndex,
  required int memberThreshold,
  required Uint8List shareValue,
}) {
  final bw = BitWriter();

  bw.write(identifier, 15);
  bw.write(iterationExponent, 5);

  bw.write(groupIndex, 4);
  bw.write(groupThreshold, 4);
  bw.write(groupCount, 4);

  bw.write(memberIndex, 4);
  bw.write(memberThreshold, 4);

  bw.writeBytes(shareValue);

  return bw.toBytes();
}
