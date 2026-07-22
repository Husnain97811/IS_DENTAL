import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'secure_key_store.dart';

bool _debugCheckHasCipher(Database db) =>
    db.select('PRAGMA cipher;').isNotEmpty;

/// Encrypted local DB (source of truth) via SQLite3MultipleCiphers.
/// 256-bit key held in the OS keychain — never hardcoded.
LazyDatabase openEncryptedConnection() => LazyDatabase(() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'dentos.db'));
  final keyHex = await SecureKeyStore.instance.databaseKeyHex();

  return NativeDatabase(
    file,
    setup: (raw) {
      // Fail loudly if the encrypted build isn't linked — otherwise
      // PRAGMA key silently no-ops and we'd write plaintext.
      if (!_debugCheckHasCipher(raw)) {
        throw StateError(
          'Encrypted SQLite (sqlite3mc) not linked — check the "hooks" '
          'block in pubspec.yaml. Refusing to run unencrypted.',
        );
      }
      // Key MUST be set before any other access.
      raw.execute("PRAGMA key = \"x'$keyHex'\";");
      raw.execute('PRAGMA journal_mode = WAL;');
      raw.execute('PRAGMA foreign_keys = ON;');
    },
  );
});
