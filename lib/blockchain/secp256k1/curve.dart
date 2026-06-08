part of 'lib_secp256k1.dart';

/// exported variables incl. a, b
class Curve {
  final BigInt p;
  final BigInt n;
  final BigInt a;
  final BigInt b;
  final BigInt gx;
  final BigInt gy;
  const Curve({
    required this.p,
    required this.n,
    required this.a,
    required this.b,
    required this.gx,
    required this.gy,
  });

  static final secp256k1 = Curve(
    p: P,
    n: N,
    a: BigInt.zero,
    b: BigInt.from(7),
    gx: Gx,
    gy: Gy,
  );
}
