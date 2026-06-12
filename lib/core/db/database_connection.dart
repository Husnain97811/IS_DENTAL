import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'secure_key_store.dart';

/// Opens the local DB (source of truth). WAL + FK enforcement on.
/// 🔒 Encryption is wired in a dedicated step before release — see note below.
// LazyDatabase openEncryptedConnection() => LazyDatabase(() async {
//   final dir = await getApplicationSupportDirectory();
//   final file = File(p.join(dir.path, 'dentos.db'));
//   // Reserved for SQLCipher; harmless to read now.
//   // ignore: unused_local_variable
//   final keyHex = await SecureKeyStore.instance.databaseKeyHex();

//   return NativeDatabase(
//     file,
//     setup: (raw) {
//       raw.execute('PRAGMA journal_mode = WAL;');
//       raw.execute('PRAGMA foreign_keys = ON;');
//       // When SQLCipher is enabled, add as the FIRST statement:
//       // raw.execute('PRAGMA key = "x\'$keyHex\'";');
//     },
//   );
// });

LazyDatabase openEncryptedConnection() => LazyDatabase(() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'dentos.db'));
  return NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('PRAGMA journal_mode = WAL;');
      raw.execute('PRAGMA foreign_keys = ON;');
    },
  );
});
