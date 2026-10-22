import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The Detailed Reporting Hub PIN.
///
/// Stored as `pbkdf2$<iterations>$<salt>$<hash>` (PBKDF2-HMAC-SHA256, random
/// 16-byte salt) — never the digits. Hashing runs on a background isolate so
/// the screen never freezes while it works.
class HubPin {
  HubPin._();

  static const minLength = 4;
  static const maxLength = 6;
  static const _iterations = 60000;
  static const _scheme = 'pbkdf2';

  /// Why [pin] can't be used, or null when it is fine.
  static String? problem(String pin) {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return 'Use 4 to 6 digits.';
    if (pin.split('').toSet().length == 1) {
      return 'The same digit repeated is too easy to guess.';
    }
    bool run(int step) {
      for (var i = 1; i < pin.length; i++) {
        if (pin.codeUnitAt(i) - pin.codeUnitAt(i - 1) != step) return false;
      }
      return true;
    }

    if (run(1) || run(-1)) return 'A run like 1234 is too easy to guess.';
    return null;
  }

  static Future<String> hash(String pin) {
    final salt = _randomBytes(16);
    return Isolate.run(() => _encode(pin, salt, _iterations));
  }

  static Future<bool> verify(String pin, String stored) =>
      Isolate.run(() => _check(pin, stored));

  // ── internals (top-level-safe: no closures over objects) ──

  static String _encode(String pin, Uint8List salt, int iterations) {
    final key = _derive(pin, salt, iterations);
    return '$_scheme\$$iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  static bool _check(String pin, String stored) {
    final p = stored.split(r'$');
    if (p.length != 4 || p[0] != _scheme) return false;
    final it = int.tryParse(p[1]);
    if (it == null || it < 1000 || it > 2000000) return false;
    try {
      final salt = base64.decode(p[2]);
      final want = base64.decode(p[3]);
      final got = _derive(pin, salt, it);
      if (got.length != want.length) return false;
      var diff = 0; // constant time — no early exit
      for (var i = 0; i < got.length; i++) {
        diff |= got[i] ^ want[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _derive(String pin, Uint8List salt, int iterations) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(pin)));
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}

/// A one-time Hub PIN reset code issued by the vendor licence tool:
///
///   DRH1.<base64url(payload)>.<base64url(RSA-SHA256 signature)>
///
/// payload = {"t":"hub-pin-reset","cid":clinicId,"user":username,
///            "exp":ISO-8601 UTC,"n":nonce}
///
/// Signed with the same private key as licences, so nobody but the vendor
/// can make one. The `t` field means a licence or another vendor code can
/// never stand in for it.
class HubResetCode {
  const HubResetCode({
    required this.clinicId,
    required this.username,
    required this.expiresAt,
    required this.nonce,
  });

  static const prefix = 'DRH1';
  static const type = 'hub-pin-reset';

  final String clinicId, username, nonce;
  final DateTime expiresAt;

  /// Null when [raw] isn't a genuine code. [verify] receives the exact
  /// signed text and the signature in standard base64 — pass
  /// `LicenseVerifier().verifyCanonical`.
  static HubResetCode? parse(
    String raw,
    bool Function(String canonical, String signatureB64) verify,
  ) {
    // People paste codes out of WhatsApp with line breaks and spaces.
    final s = raw.replaceAll(RegExp(r'\s'), '');
    final parts = s.split('.');
    if (parts.length != 3 || parts[0] != prefix) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final sig = base64Url.decode(base64Url.normalize(parts[2]));
      if (!verify(payload, base64.encode(sig))) return null;

      final j = jsonDecode(payload);
      if (j is! Map || j['t'] != type) return null;
      final cid = j['cid'], user = j['user'], exp = j['exp'], n = j['n'];
      if (cid is! String || user is! String || exp is! String || n is! String) {
        return null;
      }
      final at = DateTime.tryParse(exp);
      if (at == null || n.isEmpty) return null;
      return HubResetCode(
        clinicId: cid,
        username: user,
        expiresAt: at,
        nonce: n,
      );
    } catch (_) {
      return null;
    }
  }
}
