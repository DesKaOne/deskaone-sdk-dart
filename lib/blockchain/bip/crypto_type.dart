enum CryptoType { secp256k1, ed25519 }

class CryptoTypes {
  late String message;

  CryptoTypes._(String m) : message = m;

  factory CryptoTypes.getMessage(CryptoType type) {
    switch (type) {
      case CryptoType.secp256k1:
        return CryptoTypes._('Bitcoin seed');
      case CryptoType.ed25519:
        return CryptoTypes._('ed25519 seed');
    }
  }
}
