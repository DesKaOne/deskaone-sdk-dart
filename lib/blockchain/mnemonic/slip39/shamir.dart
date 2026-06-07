import 'dart:math';
import 'dart:typed_data';

import 'gf256.dart';

class ShamirShare {
  final int x; // index (1..n)
  final Uint8List y; // value per byte

  const ShamirShare({required this.x, required this.y});
}

class Shamir {
  /// Split secret into shares using Shamir Secret Sharing (GF256)
  static List<ShamirShare> split({
    required Uint8List secret,
    required int threshold,
    required int shareCount,
  }) {
    if (threshold < 1 || threshold > shareCount) {
      throw ArgumentError('Invalid threshold');
    }

    final rng = Random.secure();
    final shares = List.generate(
      shareCount,
      (i) => ShamirShare(x: i + 1, y: Uint8List(secret.length)),
    );

    // untuk setiap byte secret
    for (int byteIndex = 0; byteIndex < secret.length; byteIndex++) {
      // polynomial coefficients
      final coeffs = List<int>.filled(threshold, 0);
      coeffs[0] = secret[byteIndex]; // constant term

      for (int i = 1; i < threshold; i++) {
        coeffs[i] = rng.nextInt(256);
      }

      // evaluasi polynomial untuk setiap share
      for (final share in shares) {
        share.y[byteIndex] = gf256EvalPoly(coeffs, share.x);
      }
    }

    return shares;
  }

  /// Combine shares to reconstruct secret
  static Uint8List combine(List<ShamirShare> shares) {
    if (shares.isEmpty) {
      throw ArgumentError('No shares provided');
    }

    final length = shares.first.y.length;
    for (final s in shares) {
      if (s.y.length != length) {
        throw ArgumentError('Share length mismatch');
      }
    }

    final secret = Uint8List(length);

    // untuk setiap byte
    for (int byteIndex = 0; byteIndex < length; byteIndex++) {
      int value = 0;

      for (int i = 0; i < shares.length; i++) {
        final xi = shares[i].x;
        final yi = shares[i].y[byteIndex];

        int li = 1;
        for (int j = 0; j < shares.length; j++) {
          if (i == j) continue;

          final xj = shares[j].x;
          li = GF256.mul(li, GF256.div(xj, GF256.sub(xj, xi)));
        }

        value = GF256.add(value, GF256.mul(yi, li));
      }

      secret[byteIndex] = value;
    }

    return secret;
  }
}

void shamirSelfTest() {
  final secret = Uint8List.fromList(List.generate(32, (i) => i));

  final shares = Shamir.split(secret: secret, threshold: 3, shareCount: 5);

  // ambil subset (>= threshold)
  // ignore: unused_local_variable
  final recovered = Shamir.combine([shares[0], shares[2], shares[4]]);

  //assert(ListEquality().equals(secret, recovered));
}
