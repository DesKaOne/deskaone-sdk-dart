part of '../lib_secp256k1.dart';

Uint8List hmacSha256(Uint8List hmacKey, Uint8List data) {
  // HMAC SHA-256: block must be 64 bytes
  final hmacResult = hmac.HMac(sha.SHA256Digest(), 64)
    ..init(pointy.KeyParameter(hmacKey));
  return hmacResult.process(data);
}
