import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import 'english.dart';
import 'mnemonic_type.dart';

abstract class MnemonicValidator {
  MnemonicType get type;

  /// validasi struktur & checksum (jika ada)
  bool validate(String mnemonic);

  /// validasi kata saja (tanpa checksum)
  bool validateWordsOnly(String mnemonic);
}

class Bip39MnemonicValidator implements MnemonicValidator {
  final List<String> wordlist;

  Bip39MnemonicValidator([this.wordlist = englishBip39]);

  @override
  MnemonicType get type => MnemonicType.bip39;

  @override
  bool validate(String mnemonic) {
    try {
      mnemonicToEntropy(_split(mnemonic));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool validateWordsOnly(String mnemonic) =>
      _split(mnemonic).every(wordlist.contains);

  Uint8List mnemonicToEntropy(List<String> words) {
    if (words.length % 3 != 0) {
      throw ArgumentError('Invalid mnemonic length');
    }

    final bits = words.map((word) {
      final index = wordlist.indexOf(word);
      if (index == -1) throw ArgumentError('Invalid word');
      return index.toRadixString(2).padLeft(11, '0');
    }).join();

    final dividerIndex = (bits.length ~/ 33) * 32;
    final entropyBits = bits.substring(0, dividerIndex);
    final checksumBits = bits.substring(dividerIndex);

    final entropy = Uint8List.fromList(
      RegExp(r'.{1,8}')
          .allMatches(entropyBits)
          .map((m) => int.parse(m.group(0)!, radix: 2))
          .toList(),
    );

    final checksum = _deriveChecksumBits(entropy);
    if (checksum != checksumBits) {
      throw StateError('Invalid checksum');
    }

    return entropy;
  }

  String _deriveChecksumBits(Uint8List entropy) {
    final hash = SHA256Digest().process(entropy);
    return hash
        .map((b) => b.toRadixString(2).padLeft(8, '0'))
        .join()
        .substring(0, entropy.length * 8 ~/ 32);
  }

  List<String> _split(String m) => m.trim().toLowerCase().split(RegExp(r'\s+'));
}

class ElectrumV1MnemonicValidator implements MnemonicValidator {
  final List<String> wordlist;

  ElectrumV1MnemonicValidator([this.wordlist = englishElectrum]);

  @override
  MnemonicType get type => MnemonicType.electrumV1;

  @override
  bool validate(String mnemonic) {
    final words = _split(mnemonic);
    return words.length == 12 && words.every(wordlist.contains);
  }

  @override
  bool validateWordsOnly(String mnemonic) =>
      _split(mnemonic).every(wordlist.contains);

  List<String> _split(String m) => m.trim().toLowerCase().split(RegExp(r'\s+'));
}

class ElectrumV2MnemonicValidator implements MnemonicValidator {
  final List<String> wordlist;

  ElectrumV2MnemonicValidator([this.wordlist = englishElectrum]);

  @override
  MnemonicType get type => MnemonicType.electrumV2;

  @override
  bool validate(String mnemonic) {
    final words = _split(mnemonic);
    return [12, 18, 24].contains(words.length) &&
        words.every(wordlist.contains);
  }

  @override
  bool validateWordsOnly(String mnemonic) =>
      _split(mnemonic).every(wordlist.contains);

  List<String> _split(String m) => m.trim().toLowerCase().split(RegExp(r'\s+'));
}

class MoneroMnemonicValidator implements MnemonicValidator {
  final List<String> wordlist;

  MoneroMnemonicValidator([this.wordlist = englishMonero]);

  @override
  MnemonicType get type => MnemonicType.monero;

  @override
  bool validate(String mnemonic) {
    final words = _split(mnemonic);
    if (words.length != 25) return false;
    if (!words.every(wordlist.contains)) return false;
    return _validateChecksum(words);
  }

  @override
  bool validateWordsOnly(String mnemonic) =>
      _split(mnemonic).every(wordlist.contains);

  bool _validateChecksum(List<String> words) {
    final indices = words.sublist(0, 24).map(wordlist.indexOf).toList();
    final checksumIndex = _crc32(indices) % wordlist.length;
    return wordlist[checksumIndex] == words.last;
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

  List<String> _split(String m) => m.trim().toLowerCase().split(RegExp(r'\s+'));
}

class Slip39MnemonicValidator implements MnemonicValidator {
  final List<String> wordlist;

  Slip39MnemonicValidator([this.wordlist = englishSlip]);

  @override
  MnemonicType get type => MnemonicType.slip39;

  @override
  bool validate(String mnemonic) {
    throw UnimplementedError(
      'SLIP39 validation requires Shamir reconstruction',
    );
  }

  @override
  bool validateWordsOnly(String mnemonic) => mnemonic
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .every(wordlist.contains);
}
