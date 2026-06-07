import 'dart:typed_data';

import '../secp256k1/lib_secp256k1.dart';
import '../utils/hex.dart';
import 'base.dart';

class Address extends BaseAddress {
  final String _address;

  // ignore: unused_element
  Address._(this._address);

  @override
  String get address => _address;

  @override
  // TODO: implement toBytes
  Uint8List get toBytes => throw UnimplementedError();

  @override
  // TODO: implement toEip55
  String get toEip55 => throw UnimplementedError();

  factory Address.fromPrivateKey(Account account) {
    throw UnimplementedError();
  }
}

class Account extends PrivateKey implements BasePrivateKey<PublicKey, Address> {
  Account._(super.privateKey);

  @override
  Address get toAddress => Address.fromPrivateKey(this);

  @override
  Uint8List get toBytes => bigIntToBytes(privateKey);

  @override
  String get toHex => bigIntToHex(privateKey);

  @override
  PublicKey get toPubKey => getPublicKey(false);
}
