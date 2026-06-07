import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import 'slip39/shamir.dart';
import 'slip39/slip39.dart';
import 'english.dart';
import 'mnemonic_type.dart';

abstract class MnemonicGenerator {
  MnemonicType get type;

  /// generate mnemonic
  String generate({int strength = 128});
}

enum MnemonicGenerateMode {
  secure, // BIP39 asli (random)
  fixedZero, // DEMO / TEST ONLY
  deterministic, // seeded (testing)
}

class Bip39MnemonicGenerator implements MnemonicGenerator {
  final List<String> wordlist;
  final Random _rng = Random.secure();

  Bip39MnemonicGenerator([this.wordlist = englishBip39]);

  @override
  MnemonicType get type => MnemonicType.bip39;

  @override
  String generate({
    int strength = 128,
    MnemonicGenerateMode mode = MnemonicGenerateMode.secure,
    int counter = 0,
  }) {
    switch (mode) {
      case MnemonicGenerateMode.secure:
        return _generateSecure(strength: strength);
      case MnemonicGenerateMode.fixedZero:
        return _generateSorted(strength: strength);
      case MnemonicGenerateMode.deterministic:
        return generateCounterEntropy(counter: counter, strength: strength);
    }
  }

  String generateCounterEntropy({required int counter, int strength = 128}) {
    final entropy = Uint8List(strength ~/ 8);

    for (int i = entropy.length - 1; i >= 0; i--) {
      entropy[i] = counter & 0xff;
      counter >>= 8;
    }

    return _fromEntropy(entropy);
  }

  // ===============================
  // ✅ BIP39 ASLI (PRODUCTION)
  // ===============================
  String _generateSecure({int strength = 128}) {
    if (![128, 160, 192, 224, 256].contains(strength)) {
      throw ArgumentError('Invalid strength');
    }

    final entropy = Uint8List(strength ~/ 8);
    for (int i = 0; i < entropy.length; i++) {
      entropy[i] = _rng.nextInt(256);
    }
    return _fromEntropy(entropy);
  }
  // ===============================

  // ⚠️ SORT MODE (DEMO / TEST)
  // ===============================
  String _generateSorted({int strength = 128}) {
    // jumlah kata sesuai BIP39
    final wordCount = (strength ~/ 32) * 3;

    // urutkan wordlist
    final sorted = List<String>.from(wordlist)..sort();

    final words = <String>[];
    for (int i = 0; i < wordCount; i++) {
      // mayoritas kata pertama
      words.add(sorted[0]);
    }

    // kata terakhir beda biar mirip contoh BIP39
    if (wordCount > 0) {
      words[wordCount - 1] = sorted[3]; // "about"
    }

    return words.join(' ');
  } // ===============================

  // INTERNAL
  // ===============================
  String _fromEntropy(Uint8List entropy) {
    final checksumBits = _deriveChecksumBits(entropy);
    final entropyBits = _bytesToBinary(entropy);
    final bits = entropyBits + checksumBits;

    final words = <String>[];
    for (int i = 0; i < bits.length; i += 11) {
      final index = int.parse(bits.substring(i, i + 11), radix: 2);
      words.add(wordlist[index]);
    }

    return words.join(' ');
  }

  String _deriveChecksumBits(Uint8List entropy) {
    final hash = SHA256Digest().process(entropy);
    final bits = _bytesToBinary(hash);
    return bits.substring(0, entropy.length * 8 ~/ 32);
  }

  String _bytesToBinary(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(2).padLeft(8, '0')).join();
}

class ElectrumV2MnemonicGenerator implements MnemonicGenerator {
  final List<String> wordlist;
  final Random _rng = Random.secure();

  ElectrumV2MnemonicGenerator([this.wordlist = englishElectrum]);

  @override
  MnemonicType get type => MnemonicType.electrumV2;

  @override
  String generate({int strength = 132}) {
    final byteLen = strength ~/ 8;
    final entropy = Uint8List(byteLen);

    for (int i = 0; i < entropy.length; i++) {
      entropy[i] = _rng.nextInt(256);
    }

    final words = <String>[];
    for (final b in entropy) {
      words.add(wordlist[b % wordlist.length]);
    }

    return words.join(' ');
  }
}

class MoneroMnemonicGenerator implements MnemonicGenerator {
  final List<String> wordlist;
  final Random _rng = Random.secure();

  MoneroMnemonicGenerator([this.wordlist = englishMonero]);

  @override
  MnemonicType get type => MnemonicType.monero;

  @override
  String generate({int strength = 256}) {
    if (strength != 256) {
      throw ArgumentError('Monero strength must be 256 bits');
    }

    final entropy = Uint8List(32);
    for (int i = 0; i < entropy.length; i++) {
      entropy[i] = _rng.nextInt(256);
    }

    final words = <String>[];
    for (int i = 0; i < entropy.length; i += 4) {
      final val = entropy.buffer.asByteData().getUint32(i, Endian.little);
      words.add(wordlist[val % wordlist.length]);
    }

    final checksumIndex =
        _crc32(words.map(wordlist.indexOf).toList()) % wordlist.length;

    words.add(wordlist[checksumIndex]);
    return words.join(' ');
  }

  int _crc32(List<int> data) {
    var crc = 0xffffffff;
    for (final v in data) {
      crc ^= v;
      for (int i = 0; i < 8; i++) {
        final mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xEDB88320 & mask);
      }
    }
    return crc ^ 0xffffffff;
  }
}

class Slip39MnemonicGenerator {
  static Slip39Result generate({
    required int groupThreshold,
    required List<Slip39Group> groups,
    int secretLength = 32, // 256-bit
    int iterationExponent = 0,
  }) {
    // ================= VALIDASI =================
    if (groupThreshold < 1 || groupThreshold > groups.length) {
      throw ArgumentError('Invalid group threshold');
    }

    for (final g in groups) {
      if (g.memberThreshold < 1 || g.memberThreshold > g.memberCount) {
        throw ArgumentError('Invalid member threshold');
      }
    }

    // ================= MASTER SECRET =================
    final rng = Random.secure();
    final secret = Uint8List(secretLength);
    for (int i = 0; i < secret.length; i++) {
      secret[i] = rng.nextInt(256);
    }

    // ================= IDENTIFIER =================
    final identifier = rng.nextInt(1 << 15);

    // ================= GROUP SHAMIR =================
    final groupShares = Shamir.split(
      secret: secret,
      threshold: groupThreshold,
      shareCount: groups.length,
    );

    final allShares = <Slip39Share>[];

    // ================= MEMBER SHAMIR =================
    for (int gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];
      final memberShares = Shamir.split(
        secret: groupShares[gi].y,
        threshold: group.memberThreshold,
        shareCount: group.memberCount,
      );

      for (int mi = 0; mi < memberShares.length; mi++) {
        final payload = buildSlip39Payload(
          identifier: identifier,
          iterationExponent: iterationExponent,
          groupIndex: gi,
          groupThreshold: groupThreshold,
          groupCount: groups.length,
          memberIndex: mi,
          memberThreshold: group.memberThreshold,
          shareValue: memberShares[mi].y,
        );

        final mnemonic = encodeSlip39Words(payload, englishSlip);

        allShares.add(
          Slip39Share(groupIndex: gi, memberIndex: mi, mnemonic: mnemonic),
        );
      }
    }

    return Slip39Result(masterSecret: secret, shares: allShares);
  }
}
