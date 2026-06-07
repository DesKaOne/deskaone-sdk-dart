import '../bip/bip32.dart';
import '../bip/bip39.dart';
import '../bip/bip44.dart';
import '../bip/bip49.dart';
import '../bip/bip84.dart';
import '../bip/coin.dart';
import '../bip/coin_meta.dart';
import '../bip/crypto_type.dart';
import 'slip39/slip39.dart';
import 'mnemonic_generator.dart';
import 'mnemonic_type.dart';
import 'mnemonic_validator.dart';

class Mnemonic {
  final String mnemonic;
  final String passphrase;
  final MnemonicType type;

  bool get isBip39 => type == MnemonicType.bip39;
  bool get isElectrum =>
      type == MnemonicType.electrumV1 || type == MnemonicType.electrumV2;
  bool get isMonero => type == MnemonicType.monero;
  bool get isSlip39 => type == MnemonicType.slip39;

  Mnemonic._(this.mnemonic, this.passphrase, this.type);

  static final List<MnemonicValidator> _validators = [
    Bip39MnemonicValidator(),
    ElectrumV1MnemonicValidator(),
    ElectrumV2MnemonicValidator(),
    MoneroMnemonicValidator(),
    Slip39MnemonicValidator(),
  ];

  factory Mnemonic.fromString({
    required String mnemonic,
    String passphrase = '',
  }) {
    final normalized = mnemonic.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final candidates = _validators
        .where((v) => v.validateWordsOnly(normalized))
        .toList();

    for (final v in candidates) {
      if (v.validate(normalized)) {
        return Mnemonic._(normalized, passphrase, v.type);
      }
    }

    throw StateError('Unknown or invalid mnemonic');
  }

  factory Mnemonic.fromList({
    required List<String> mnemonic,
    String passphrase = '',
  }) {
    return Mnemonic.fromString(
      mnemonic: mnemonic.join(' '),
      passphrase: passphrase,
    );
  }

  factory Mnemonic.generate({
    MnemonicType type = MnemonicType.bip39,
    String passphrase = '',
    int strength = 128,
  }) {
    late String mnemonic;

    switch (type) {
      // =========================
      // 🔐 BIP39 (AMAN & UMUM)
      // =========================
      case MnemonicType.bip39:
        mnemonic = Bip39MnemonicGenerator().generate(strength: strength);
        break;

      // =========================
      // ⚡ ELECTRUM V2
      // =========================
      case MnemonicType.electrumV2:
        mnemonic = ElectrumV2MnemonicGenerator().generate();
        break;

      // =========================
      // 🧬 MONERO
      // =========================
      case MnemonicType.monero:
        mnemonic = MoneroMnemonicGenerator().generate();
        break;

      // =========================
      // 🧪 SLIP39 (BUTUH PARAMETER)
      // =========================
      case MnemonicType.slip39:
        final slip = Slip39MnemonicGenerator.generate(
          groupThreshold: 2,
          groups: [
            Slip39Group(memberThreshold: 2, memberCount: 3),
            Slip39Group(memberThreshold: 1, memberCount: 2),
          ],
        );

        for (final s in slip.shares) {
          print('[G${s.groupIndex} M${s.memberIndex}] ${s.mnemonic}');
        }

        throw UnsupportedError(
          'SLIP39 mnemonic generation requires Shamir parameters',
        );

      // =========================
      // ❌ TIDAK DIDUKUNG
      // =========================
      case MnemonicType.electrumV1:
      case MnemonicType.unknown:
        throw UnsupportedError(
          'Mnemonic generation not supported for type: $type',
        );
    }

    return Mnemonic.fromString(mnemonic: mnemonic, passphrase: passphrase);
  }

  factory Mnemonic.generateBip39({String passphrase = '', int strength = 128}) {
    return Mnemonic.generate(
      type: MnemonicType.bip39,
      passphrase: passphrase,
      strength: strength,
    );
  }

  factory Mnemonic.generateElectrumV2({String passphrase = ''}) {
    return Mnemonic.generate(type: MnemonicType.bip39, passphrase: passphrase);
  }

  factory Mnemonic.generateMonero({String passphrase = ''}) {
    return Mnemonic.generate(type: MnemonicType.bip39, passphrase: passphrase);
  }

  Bip39 get bip39 => Bip39.fromMnemonic(this);

  Bip32 toBip32({CryptoType type = CryptoType.secp256k1}) {
    return Bip32.fromMnemonic(
      mnemonic: this,
      message: CryptoTypes.getMessage(type),
      type: type,
      depth: 0,
      index: 0,
      parentFingerprint: 0,
    );
  }

  Bip44 toBip44({required Coin coin}) {
    return Bip44.fromMnemonic(this, CoinMeta.meta(coin: coin));
  }

  Bip49 toBip49({required Coin coin}) {
    return Bip49.fromMnemonic(this, CoinMeta.meta(coin: coin));
  }

  Bip84 toBip84({required Coin coin}) {
    return Bip84.fromMnemonic(this, CoinMeta.meta(coin: coin));
  }

  @override
  String toString() {
    return 'Mnemonic     : $mnemonic\n'
        'Passphrase   : $passphrase\n'
        'MnemonicType : $type\n';
  }
}
