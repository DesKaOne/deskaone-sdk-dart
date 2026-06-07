import '../mnemonic/mnemonic.dart';
import 'base.dart';
import 'bip32.dart';
import 'coin.dart';
import 'coin_meta.dart';
import 'crypto_type.dart';

/// BIP44 HD Wallet Node
///
/// Path (secp256k1):
/// m / 44' / coin_type' / account' / change / address_index
///
/// Path (ed25519 - Solana):
/// m / 44' / coin_type' / account' / change'
final class Bip44 extends BipBase<Bip44> {
  static const int _purpose = 44;

  final Bip32 _root;
  final CoinMeta _meta;

  Bip44._(super.node, this._meta, this._root);

  /// Create BIP44 root at:
  /// m / 44' / coin_type'
  factory Bip44.fromMnemonic(Mnemonic mnemonic, CoinMeta meta) {
    final root = Bip32.fromMnemonic(
      mnemonic: mnemonic,
      message: CryptoTypes.getMessage(meta.cryptoType),
      type: meta.cryptoType,
      depth: 0,
      index: 0,
      parentFingerprint: 0,
    );

    final purposeNode = root.deriveChild(_purpose, hardened: true);
    final coinNode = purposeNode.deriveChild(meta.slip44, hardened: true);

    return Bip44._(coinNode, meta, root);
  }

  /// Default path:
  /// m / 44' / coin_type' / 0' / 0 / 0
  /// (Solana: m / 44' / 501' / 0' / 0')
  @override
  Bip32 get defaultPath {
    if (_meta.coin == Coin.svm) {
      return node
          .deriveChild(0, hardened: true) // account'
          .deriveChild(0, hardened: true); // change'
    }

    return node
        .deriveChild(0, hardened: true) // account'
        .deriveChild(0, hardened: false) // change
        .deriveChild(0, hardened: false); // address
  }

  /// m / 44' / coin_type' / account'
  @override
  Bip44 account([int index = 0]) {
    return Bip44._(node.deriveChild(index, hardened: true), _meta, _root);
  }

  /// Raw account node (hardened)
  @override
  Bip32 accountIndexHardened([int index = 0]) {
    return node.deriveChild(index, hardened: true);
  }

  /// m / 44' / coin_type' / account' / change
  @override
  Bip44 change([int index = 0]) {
    final hardened = _meta.cryptoType == CryptoType.ed25519;
    return Bip44._(node.deriveChild(index, hardened: hardened), _meta, _root);
  }

  /// Raw change node
  @override
  Bip32 changeIndex([int index = 0]) {
    final hardened = _meta.cryptoType == CryptoType.ed25519;
    return node.deriveChild(index, hardened: hardened);
  }

  /// m / 44' / coin_type' / account' / change / address_index
  @override
  Bip44 address([int index = 0]) {
    final hardened = _meta.cryptoType == CryptoType.ed25519;
    return Bip44._(node.deriveChild(index, hardened: hardened), _meta, _root);
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
    return "m/44'/${_meta.slip44}'/0'/0/0:\n$p";
  }
}
