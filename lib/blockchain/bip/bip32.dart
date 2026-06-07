import 'dart:convert';
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:crypto/crypto.dart';

import '../mnemonic/mnemonic.dart';
import '../secp256k1/lib_secp256k1.dart';
import '../utils/hex.dart';
import '../utils/sha.dart';
import 'bip39.dart';
import 'crypto_type.dart';

class Bip32 {
  final Uint8List privateKey; // 32-byte priv
  final Uint8List chainCode;
  final Bip39 seed;
  final CryptoType type;
  final int depth;
  final int index;
  final int parentFingerprint;

  Bip32._({
    required this.privateKey,
    required this.chainCode,
    required this.seed,
    required this.type,
    required this.depth,
    required this.index,
    required this.parentFingerprint,
  });

  factory Bip32.fromBip39({
    required Bip39 seed,
    required CryptoTypes message,
    required CryptoType type,
    required int depth,
    required int index,
    required int parentFingerprint,
  }) {
    final i = hmacSha512(utf8.encode(message.message), seed.bytes);
    final il = Uint8List.fromList(i.sublist(0, 32));
    final ir = Uint8List.fromList(i.sublist(32));

    if (type == CryptoType.secp256k1) {
      final curve = Curve.secp256k1;
      final n = curve.n;
      final ilInt = bytesToBigInt(il);

      if (ilInt == BigInt.zero || ilInt >= n) {
        throw StateError('Invalid BIP32 master key (IL == 0 or >= n)');
      }
    }

    return Bip32._(
      privateKey: il,
      chainCode: ir,
      seed: seed,
      type: type,
      depth: depth,
      index: index,
      parentFingerprint: parentFingerprint,
    );
  }

  factory Bip32.fromMnemonic({
    required Mnemonic mnemonic,
    required CryptoTypes message,
    required CryptoType type,
    required int depth,
    required int index,
    required int parentFingerprint,
  }) {
    final seed = Bip39.fromMnemonic(mnemonic);
    return Bip32.fromBip39(
      seed: seed,
      message: message,
      type: type,
      depth: depth,
      index: index,
      parentFingerprint: parentFingerprint,
    );
  }

  void _writeUint32Be(int value, Uint8List buf, int offset) {
    buf[offset] = (value >> 24) & 0xff;
    buf[offset + 1] = (value >> 16) & 0xff;
    buf[offset + 2] = (value >> 8) & 0xff;
    buf[offset + 3] = value & 0xff;
  }

  Uint8List _privateKeyToCompressedPub(Uint8List sk) {
    final d = bytesToBigInt(sk);
    final priv = PrivateKey(d);
    // ignore: unused_local_variable
    final pub = priv.getPublicKey();

    final xHex = priv.affinePoint.x.toRadixString(16).padLeft(64, '0');
    final xBytes = hexToBytes(xHex);

    final prefix = priv.affinePoint.y.isEven ? 0x02 : 0x03;
    final out = Uint8List(33);
    out[0] = prefix;
    out.setRange(1, 33, xBytes);
    return out;
  }

  String _base58Check(Uint8List payload) {
    final checksum = _doubleSha256(payload).sublist(0, 4);
    final full = Uint8List(payload.length + 4)
      ..setRange(0, payload.length, payload)
      ..setRange(payload.length, payload.length + 4, checksum);
    return _base58Encode(full);
  }

  Uint8List _doubleSha256(Uint8List data) {
    final h1 = sha256.convert(data).bytes;
    final h2 = sha256.convert(h1).bytes;
    return Uint8List.fromList(h2);
  }

  String _base58Encode(dynamic value) {
    return base58.encode(Uint8List.fromList(value));
  }

  String xprv({int versionOverride = 0x0488ade4}) {
    if (type != CryptoType.secp256k1) {
      throw UnsupportedError(
        'Extended private key hanya untuk secp256k1/BIP32 (bukan Ed25519)',
      );
    }

    final v = versionOverride;
    final payload = Uint8List(78);
    _writeUint32Be(v, payload, 0);
    payload[4] = depth;
    _writeUint32Be(parentFingerprint, payload, 5);
    _writeUint32Be(index, payload, 9);
    payload.setRange(13, 45, chainCode);
    payload[45] = 0x00;
    payload.setRange(46, 78, privateKey);
    return _base58Check(payload);
  }

  String xpub({int versionOverride = 0x0488b21e}) {
    if (type != CryptoType.secp256k1) {
      throw UnsupportedError(
        'Extended public key hanya untuk secp256k1/BIP32 (bukan Ed25519)',
      );
    }
    final v = versionOverride;
    final payload = Uint8List(78);
    _writeUint32Be(v, payload, 0);
    payload[4] = depth;
    _writeUint32Be(parentFingerprint, payload, 5);
    _writeUint32Be(index, payload, 9);
    payload.setRange(13, 45, chainCode);
    final pub = _privateKeyToCompressedPub(privateKey);
    payload.setRange(45, 78, pub);
    return _base58Check(payload);
  }

  int get fingerprint {
    if (type != CryptoType.secp256k1) {
      throw UnsupportedError(
        'Fingerprint hanya didefinisikan untuk secp256k1/BIP32',
      );
    }

    final pub = _privateKeyToCompressedPub(privateKey);
    final h160 = hash160(pub);
    return (h160[0] << 24) | (h160[1] << 16) | (h160[2] << 8) | (h160[3]);
  }

  final Curve _curve = Curve.secp256k1;

  // ======================
  // DERIVASI SECP256K1
  // ======================
  (Uint8List, Uint8List, int) _secp256k1Derive(
    int index, {
    required bool hardened,
  }) {
    final childNum = hardened ? (index | 0x80000000) : index;
    late Uint8List data;

    if (hardened) {
      data = Uint8List(1 + 32 + 4);
      data[0] = 0x00;
      data.setRange(1, 33, privateKey);
      _writeUint32Be(childNum, data, 33);
    } else {
      final pub = _privateKeyToCompressedPub(privateKey);
      data = Uint8List(pub.length + 4);
      data.setRange(0, pub.length, pub);
      _writeUint32Be(childNum, data, pub.length);
    }

    final i = hmacSha512(chainCode, data);
    final il = Uint8List.fromList(i.sublist(0, 32));
    final ir = Uint8List.fromList(i.sublist(32));

    final ilInt = bytesToBigInt(il);
    if (ilInt >= _curve.n) {
      throw StateError('BIP32 IL >= n');
    }

    final kInt = bytesToBigInt(privateKey);
    final childInt = (ilInt + kInt) % _curve.n;
    if (childInt == BigInt.zero) {
      throw StateError('Derived child key == 0');
    }

    final childKey = bigIntToBytes(childInt, length: 32);
    return (childKey, ir, childNum);
  }

  // ======================
  // DERIVASI ED25519 (SLIP-0010 style – selalu hardened)
  // ======================
  (Uint8List, Uint8List, int) ed25519Derive(int index) {
    final childNum = index | 0x80000000; // always hardened

    final data = Uint8List(1 + 32 + 4);
    data[0] = 0x00;
    data.setRange(1, 33, privateKey); // parent private seed
    _writeUint32Be(childNum, data, 33);

    final i = hmacSha512(chainCode, data);
    final il = Uint8List.fromList(i.sublist(0, 32));
    final ir = Uint8List.fromList(i.sublist(32));

    return (il, ir, childNum);
  }

  Bip32 deriveChild(int index, {bool hardened = false}) {
    if (index < 0 || index > 0x7fffffff) {
      throw ArgumentError('Child index out of range: $index');
    }

    Uint8List childKey, childChainCode;
    int childNum;

    switch (type) {
      case CryptoType.secp256k1:
        (childKey, childChainCode, childNum) = _secp256k1Derive(
          index,
          hardened: hardened,
        );
        break;

      case CryptoType.ed25519:
        if (!hardened) {
          throw ArgumentError('Ed25519 only supports hardened derivation');
        }
        (childKey, childChainCode, childNum) = ed25519Derive(index);
        break;
    }

    // Fingerprint hanya relevan buat BIP32/secp256k1.
    final parentFp = type == CryptoType.secp256k1 ? fingerprint : 0;

    return Bip32._(
      type: type,
      seed: seed,
      privateKey: childKey,
      chainCode: childChainCode,
      depth: depth + 1,
      index: childNum,
      parentFingerprint: parentFp,
    );
  }

  Bip32 derivePath(String path) {
    if (!path.startsWith('m')) {
      throw ArgumentError('Path must start with "m": $path');
    }

    var node = this;
    final parts = path.split('/');

    for (var i = 1; i < parts.length; i++) {
      var p = parts[i].trim();
      if (p.isEmpty) continue;

      var hardened = false;
      if (p.endsWith("'") || p.endsWith('h') || p.endsWith('H')) {
        hardened = true;
        p = p.substring(0, p.length - 1);
      }

      final index = int.parse(p);

      if (type == CryptoType.ed25519 && !hardened) {
        throw ArgumentError(
          "Ed25519 only supports hardened path segments (pakai ' di $p)",
        );
      }

      node = node.deriveChild(index, hardened: hardened);
    }

    return node;
  }

  @override
  String toString() {
    final isRoot = depth == 0 && index == 0 && parentFingerprint == 0;
    if (type != CryptoType.secp256k1) {
      return '${isRoot ? 'Root ' : ''}Private Key : ${bytesToHex(privateKey)}\n';
    }
    return 'Bip32${isRoot ? ' Root' : ''} Extended Private Key : ${xprv()}\n'
        'Bip32${isRoot ? ' Root' : ''} Extended Public Key  : ${xpub()}\n'
        '${isRoot ? 'Root ' : ''}Private Key                : ${bytesToHex(privateKey)}\n';
  }
}
