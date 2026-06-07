// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/ripemd160.dart';

Uint8List pbkdf2HmacSha512(
  Uint8List password,
  Uint8List salt,
  int iterations,
  int dkLen,
) {
  const hLen = 64;
  final l = (dkLen + hLen - 1) ~/ hLen;
  final r = dkLen - (l - 1) * hLen;

  final out = Uint8List(dkLen);
  var outPos = 0;

  for (var i = 1; i <= l; i++) {
    final blockIndex = Uint8List(4);
    blockIndex[0] = (i >> 24) & 0xff;
    blockIndex[1] = (i >> 16) & 0xff;
    blockIndex[2] = (i >> 8) & 0xff;
    blockIndex[3] = i & 0xff;

    var hmac = Hmac(sha512, password);
    var u = hmac.convert(Uint8List.fromList([...salt, ...blockIndex])).bytes;
    final t = Uint8List.fromList(u);

    for (var j = 1; j < iterations; j++) {
      hmac = Hmac(sha512, password);
      u = hmac.convert(u).bytes;
      for (var k = 0; k < hLen; k++) {
        t[k] ^= u[k];
      }
    }

    final toCopy = (i == l) ? r : hLen;
    out.setRange(outPos, outPos + toCopy, t.sublist(0, toCopy));
    outPos += toCopy;
  }

  return out;
}

Uint8List hmacSha512(List<int> key, List<int> data) {
  final h = Hmac(sha512, key);
  final digest = h.convert(data);
  return Uint8List.fromList(digest.bytes);
}

Uint8List hash160(Uint8List data) {
  final sha = sha256.convert(data).bytes;
  final ripe = RIPEMD160Digest().process(Uint8List.fromList(sha));
  return ripe;
}

Uint8List doubleSha256(Uint8List data) {
  final h1 = sha256.convert(data).bytes;
  final h2 = sha256.convert(h1).bytes;
  return Uint8List.fromList(h2);
}

Uint8List Sha256(Uint8List data) {
  final h1 = sha256.convert(data).bytes;
  return Uint8List.fromList(h1);
}

Uint8List Sha512(Uint8List data) {
  final h1 = sha512.convert(data).bytes;
  return Uint8List.fromList(h1);
}

Uint8List base58Decode(String value) {
  return base58.decode(value);
}

String base58Encode(dynamic value) {
  return base58.encode(Uint8List.fromList(value));
}

String base58EncodeCheck(Uint8List payload) {
  final checksum = doubleSha256(payload).sublist(0, 4);
  final full = Uint8List(payload.length + 4)
    ..setRange(0, payload.length, payload)
    ..setRange(payload.length, payload.length + 4, checksum);
  return base58Encode(full);
}
