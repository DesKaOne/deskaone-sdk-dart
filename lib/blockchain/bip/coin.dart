enum Coin {
  // ===== BIP COINS =====
  btc,
  bch,
  bsv,
  btg,
  ltc,
  dash,
  doge,
  zec,
  etc,
  evm,
  trx,
  svm,
  xrp,

  // ===== NON-BIP =====
  monero,
  cardano;

  /// WIF prefix mainnet
  int get wifPrefix {
    switch (this) {
      case Coin.btc:
      case Coin.bch:
      case Coin.bsv:
      case Coin.btg:
      case Coin.dash:
      case Coin.zec:
        return 0x80;

      case Coin.ltc:
        return 0xB0; // Litecoin mainnet WIF

      case Coin.doge:
        return 0x9E; // Dogecoin mainnet WIF
      default:
        throw UnsupportedError('wif not supported for $this');
    }
  }

  /// testnet WIF prefix (hampir semua sama)
  int get wifTestnetPrefix => 0xEF;

  /// Default compressed key
  bool get defaultCompressed => true;

  /// Nama coin (debug / display)
  String get symbol {
    switch (this) {
      case Coin.btc:
        return 'BTC';
      case Coin.bch:
        return 'BCH';
      case Coin.bsv:
        return 'BSV';
      case Coin.btg:
        return 'BTG';
      case Coin.ltc:
        return 'LTC';
      case Coin.dash:
        return 'DASH';
      case Coin.doge:
        return 'DOGE';
      case Coin.zec:
        return 'ZEC';
      default:
        throw UnsupportedError('symbol not supported for $this');
    }
  }

  int get p2pkhPrefix {
    switch (this) {
      case Coin.btc:
      case Coin.bch:
      case Coin.bsv:
      case Coin.btg:
      case Coin.dash:
      case Coin.zec:
        return 0x00; // 1...

      case Coin.ltc:
        return 0x30; // L...

      case Coin.doge:
        return 0x1E; // D...
      default:
        throw UnsupportedError('p2pkh not supported for $this');
    }
  }

  int get p2shPrefix {
    switch (this) {
      case Coin.btc:
      case Coin.bch:
      case Coin.bsv:
      case Coin.btg:
      case Coin.dash:
      case Coin.zec:
        return 0x05; // 3...

      case Coin.ltc:
        return 0x32; // M...

      case Coin.doge:
        return 0x16;
      default:
        throw UnsupportedError('p2sh not supported for $this');
    }
  }

  String get bech32Hrp {
    switch (this) {
      case Coin.btc:
        return 'bc';
      case Coin.ltc:
        return 'ltc';
      default:
        throw UnsupportedError('Bech32 not supported for $this');
    }
  }
}
