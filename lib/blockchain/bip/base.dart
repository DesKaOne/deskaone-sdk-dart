import 'bip32.dart';
import 'coin.dart';
import 'coin_meta.dart';
import 'crypto_type.dart';

abstract class BipBase<M> {
  static void assertSupported(CoinMeta meta) {
    if (meta.cryptoType != CryptoType.secp256k1) {
      throw UnsupportedError('BIP49/BIP84 only support secp256k1');
    }

    if (meta.coin != Coin.btc && meta.coin != Coin.ltc) {
      throw UnsupportedError('BIP49/BIP84 only supported for BTC/LTC');
    }
  }

  final Bip32 _node;

  BipBase(this._node);

  Bip32 get node => _node;

  M account([int index = 0]);

  Bip32 accountIndexHardened([int index = 0]);

  M change([int index = 0]);

  Bip32 changeIndex([int index = 0]);

  M address([int index = 0]);

  Bip32 addressIndex([int index = 0]);

  Bip32 get defaultPath;
}
