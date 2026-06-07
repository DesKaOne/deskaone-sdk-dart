import '../mnemonic/mnemonic.dart';
import 'base.dart';
import 'bip32.dart';
import 'coin_meta.dart';
import 'crypto_type.dart';

/// BIP44 HD Wallet Node
///
/// Path (secp256k1):
/// m / 84' / coin_type' / account' / change / address_index
///
/// Path (ed25519 - Solana):
/// m / 84' / coin_type' / account' / change'
final class Bip84 extends BipBase<Bip84> {
  static const int _purpose = 84;

  final Bip32 _root;
  final CoinMeta _meta;

  Bip84._(super.node, this._meta, this._root);

  /// Create BIP44 root at:
  /// m / 84' / coin_type'
  factory Bip84.fromMnemonic(Mnemonic mnemonic, CoinMeta meta) {
    BipBase.assertSupported(meta);

    final root = Bip32.fromMnemonic(
      mnemonic: mnemonic,
      message: CryptoTypes.getMessage(CryptoType.secp256k1),
      type: CryptoType.secp256k1,
      depth: 0,
      index: 0,
      parentFingerprint: 0,
    );

    final node = root
        .deriveChild(_purpose, hardened: true)
        .deriveChild(meta.slip44, hardened: true);

    return Bip84._(node, meta, root);
  }

  @override
  Bip32 get defaultPath => node
      .deriveChild(0, hardened: true)
      .deriveChild(0, hardened: false)
      .deriveChild(0, hardened: false);

  /// m / 84' / coin_type' / account'
  @override
  Bip84 account([int index = 0]) {
    return Bip84._(node.deriveChild(index, hardened: true), _meta, _root);
  }

  /// Raw account node (hardened)
  @override
  Bip32 accountIndexHardened([int index = 0]) {
    return node.deriveChild(index, hardened: true);
  }

  /// m / 84' / coin_type' / account' / change
  @override
  Bip84 change([int index = 0]) {
    final hardened = _meta.cryptoType == CryptoType.ed25519;
    return Bip84._(node.deriveChild(index, hardened: hardened), _meta, _root);
  }

  /// Raw change node
  @override
  Bip32 changeIndex([int index = 0]) {
    final hardened = _meta.cryptoType == CryptoType.ed25519;
    return node.deriveChild(index, hardened: hardened);
  }

  /// m / 84' / coin_type' / account' / change / address_index
  @override
  Bip84 address([int index = 0]) {
    final hardened = _meta.cryptoType == CryptoType.ed25519;
    return Bip84._(node.deriveChild(index, hardened: hardened), _meta, _root);
  }

  /// Raw address node
  @override
  Bip32 addressIndex([int index = 0]) {
    final hardened = _meta.cryptoType == CryptoType.ed25519;
    return node.deriveChild(index, hardened: hardened);
  }

  @override
  String toString() {
    final p = defaultPath;
    return "m/84'/${_meta.slip44}'/0'/0/0:\n$p";
  }
}
