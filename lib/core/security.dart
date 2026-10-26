import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted, iterated SHA-256 password hashing (PBKDF2-HMAC-SHA256).
class PasswordHasher {
  PasswordHasher._();

  static const defaultIterations = 20000;

  static String newSalt() {
    final rnd = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static String hash(String password, String salt, {int iterations = defaultIterations}) {
    final hmac = Hmac(sha256, utf8.encode(password));
    // PBKDF2 with a single 32 byte block.
    var u = hmac.convert([...utf8.encode(salt), 0, 0, 0, 1]).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return base64Url.encode(out);
  }

  static bool verify(String password, String salt, String expected, int iterations) {
    final actual = hash(password, salt, iterations: iterations);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Returns an error message, or null when the password is acceptable.
  static String? validateStrength(String? pw) {
    if (pw == null || pw.length < 6) return 'Password must be at least 6 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(pw) || !RegExp(r'\d').hasMatch(pw)) {
      return 'Use letters and numbers';
    }
    return null;
  }
}
