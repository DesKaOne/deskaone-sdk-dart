import 'dart:typed_data';

abstract class BasePrivateKey<PUBKEY, ADDRS> {
  Uint8List get toBytes;

  String get toHex;

  ADDRS get toAddress;
  PUBKEY get toPubKey;
}

abstract class BaseAddress {
  String get address;
  String get toEip55;
  Uint8List get toBytes;
}
