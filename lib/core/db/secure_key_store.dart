import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the SQLCipher passphrase and the install fingerprint.
/// The key is generated once per install and held in DPAPI (Windows) /
/// Keychain (macOS) / libsecret (Linux) — never hardcoded.
class SecureKeyStore {
  SecureKeyStore._();
  static final instance = SecureKeyStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kDbKey = 'dentos_db_key_v1';
  static const _kFingerprint = 'dentos_machine_fp_v1';

  Future<String> databaseKeyHex() async {
    var key = await _storage.read(key: _kDbKey);
    if (key == null) {
      key = _randomHex(32); // 256-bit
      await _storage.write(key: _kDbKey, value: key);
    }
    return key;
  }

  /// Stable per-install identifier used as the machine fingerprint.
  /// Swap for a hardware-bound value later without touching callers.
  Future<String> machineFingerprint() async {
    var fp = await _storage.read(key: _kFingerprint);
    if (fp == null) {
      fp = _randomHex(16);
      await _storage.write(key: _kFingerprint, value: fp);
    }
    return fp;
  }

  String _randomHex(int bytes) {
    final r = Random.secure();
    return List.generate(
      bytes,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
