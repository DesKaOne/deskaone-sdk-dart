import 'dart:convert';
import 'dart:typed_data';

import '../mnemonic/mnemonic.dart';
import '../utils/hex.dart';
import '../utils/sha.dart';
import 'bip32.dart';
import 'crypto_type.dart';

class Bip39 {
  late final Uint8List _value;

  Uint8List get bytes => _value;

  String get toHex => bytesToHex(bytes);

  Bip39._(Uint8List value) : _value = value;

  factory Bip39.fromMnemonic(Mnemonic mnemonic) {
    final pwBytes = Uint8List.fromList(utf8.encode(mnemonic.mnemonic));
    final saltBytes = Uint8List.fromList(
      utf8.encode('mnemonic${mnemonic.passphrase}'),
    );
    return Bip39._(pbkdf2HmacSha512(pwBytes, saltBytes, 2048, 64));
  }

  factory Bip39.fromBip39Bytes(Uint8List seed) {
    return Bip39._(seed);
  }

  factory Bip39.fromBip39Hex(String seed) {
    return Bip39._(hexToBytes(strip0x(seed)));
  }

  Bip32 bip32({CryptoType type = CryptoType.secp256k1}) {
    return Bip32.fromBip39(
      seed: this,
      message: CryptoTypes.getMessage(type),
      type: type,
      depth: 0,
      index: 0,
      parentFingerprint: 0,
    );
  }

  @override
  String toString() => 'Seed (BIP39) : $toHex\n';
}
