import '../mnemonic/mnemonic_type.dart';
import 'coin.dart';
import 'coin_family.dart';
import 'crypto_type.dart';

class CoinMeta {
  final Coin coin;
  final CoinFamily family;
  final CryptoType cryptoType;
  final int slip44;
  final Set<MnemonicType> mnemonicTypes;

  const CoinMeta._({
    required this.family,
    required this.cryptoType,
    required this.slip44,
    required this.mnemonicTypes,
    required this.coin,
  });

  factory CoinMeta.meta({required Coin coin}) {
    switch (coin) {
      case Coin.btc:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 0,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.ltc:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 2,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.bch:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 145,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.doge:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 3,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.zec:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 133,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.evm:
        return CoinMeta._(
          family: CoinFamily.evm,
          cryptoType: CryptoType.secp256k1,
          slip44: 60,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.trx:
        return CoinMeta._(
          family: CoinFamily.tvm,
          cryptoType: CryptoType.secp256k1,
          slip44: 195,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.svm:
        return CoinMeta._(
          family: CoinFamily.solana,
          cryptoType: CryptoType.ed25519,
          slip44: 501,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.monero:
        return CoinMeta._(
          family: CoinFamily.monero,
          cryptoType: CryptoType.ed25519,
          mnemonicTypes: {MnemonicType.monero},
          coin: coin,
          slip44: 10000,
        );
      case Coin.cardano:
        return CoinMeta._(
          family: CoinFamily.cardano,
          cryptoType: CryptoType.ed25519,
          mnemonicTypes: {MnemonicType.bip39, MnemonicType.slip39},
          coin: coin,
          slip44: 1815,
        );
      case Coin.bsv:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 236,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.btg:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 156,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.dash:
        return CoinMeta._(
          family: CoinFamily.utxo,
          cryptoType: CryptoType.secp256k1,
          slip44: 5,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.etc:
        return CoinMeta._(
          family: CoinFamily.evm,
          cryptoType: CryptoType.secp256k1,
          slip44: 61,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
      case Coin.xrp:
        return CoinMeta._(
          family: CoinFamily.ripple,
          cryptoType: CryptoType.secp256k1,
          slip44: 144,
          mnemonicTypes: {MnemonicType.bip39},
          coin: coin,
        );
    }
  }
}
