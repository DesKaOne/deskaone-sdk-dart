import 'dart:typed_data';

/// GF(256) arithmetic for SLIP39 / Shamir
/// Irreducible polynomial: x^8 + x^4 + x^3 + x + 1 (0x11B)
class GF256 {
  static const int _poly = 0x11B;

  static final List<int> _exp = List.filled(512, 0);
  static final List<int> _log = List.filled(256, 0);

  static bool _initialized = false;

  static void _init() {
    if (_initialized) return;

    int x = 1;
    for (int i = 0; i < 255; i++) {
      _exp[i] = x;
      _log[x] = i;
      x <<= 1;
      if (x & 0x100 != 0) {
        x ^= _poly;
      }
    }

    // duplicate exp table to avoid mod 255
    for (int i = 255; i < 512; i++) {
      _exp[i] = _exp[i - 255];
    }

    _initialized = true;
  }

  /// a + b (XOR)
  static int add(int a, int b) => a ^ b;

  /// a - b (same as add)
  static int sub(int a, int b) => a ^ b;

  /// a * b
  static int mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    _init();
    return _exp[_log[a] + _log[b]];
  }

  /// a / b
  static int div(int a, int b) {
    if (b == 0) {
      throw ArgumentError('Division by zero in GF(256)');
    }
    if (a == 0) return 0;
    _init();
    return _exp[(_log[a] - _log[b] + 255) % 255];
  }

  /// a⁻¹
  static int inv(int a) {
    if (a == 0) {
      throw ArgumentError('Zero has no inverse in GF(256)');
    }
    _init();
    return _exp[255 - _log[a]];
  }
}

Uint8List gf256AddVec(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    throw ArgumentError('Vector length mismatch');
  }
  final out = Uint8List(a.length);
  for (int i = 0; i < a.length; i++) {
    out[i] = GF256.add(a[i], b[i]);
  }
  return out;
}

Uint8List gf256MulScalar(Uint8List a, int scalar) {
  final out = Uint8List(a.length);
  for (int i = 0; i < a.length; i++) {
    out[i] = GF256.mul(a[i], scalar);
  }
  return out;
}

int gf256EvalPoly(List<int> coeffs, int x) {
  int y = 0;
  for (int i = coeffs.length - 1; i >= 0; i--) {
    y = GF256.mul(y, x);
    y = GF256.add(y, coeffs[i]);
  }
  return y;
}

void gf256SelfTest() {
  assert(GF256.add(0x57, 0x83) == 0xd4);
  assert(GF256.mul(0x57, 0x13) == 0xfe);
  assert(GF256.div(0xfe, 0x13) == 0x57);
  assert(GF256.mul(0x53, GF256.inv(0x53)) == 1);
}
