import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/db/app_database.dart';
import 'xray_crypto.dart';

/// Owns the X-ray keys and every read and write of X-ray bytes.
///
/// Keys live in the app settings table, which sits inside the SQLCipher
/// database — so they are encrypted at rest too, and never in a loose file.
/// A KEYRING rather than one key: files encrypted on another computer bring
/// that computer's key along (Phase 3), and old files never need
/// re-encrypting.
class XrayVault {
  XrayVault(this._db);
  final AppDatabase _db;

  static const _kRing = 'xray_keyring'; // {keyIdHex: base64 key}
  static const _kActive = 'xray_active_key'; // keyIdHex used for new files

  // Small in-memory cache of DECRYPTED bytes. Memory only — never disk.
  static const _cacheLimit = 40 * 1024 * 1024;
  final _cache = <String, Uint8List>{};
  int _cacheBytes = 0;

  bool _migrating = false;

  // ── keys ─────────────────────────────────────────────────────────────────
  Future<Map<String, Uint8List>> _ring() async {
    final raw = await _db.getSetting(_kRing);
    if (raw == null || raw.isEmpty) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in m.entries) e.key: base64.decode(e.value as String)};
  }

  Future<void> _saveRing(Map<String, Uint8List> ring) => _db.setSetting(
    _kRing,
    jsonEncode({for (final e in ring.entries) e.key: base64.encode(e.value)}),
  );

  /// The key new X-rays are encrypted with. Created on first use.
  Future<Uint8List> activeKey() async {
    final ring = await _ring();
    final id = await _db.getSetting(_kActive);
    if (id != null && ring.containsKey(id)) return ring[id]!;

    final key = XrayCrypto.newKey();
    final newId = XrayCrypto.keyIdHex(key);
    ring[newId] = key;
    await _saveRing(ring);
    await _db.setSetting(_kActive, newId);
    return key;
  }

  /// Adds a key received from another computer (Phase 3) or a vendor
  /// recovery (Phase 5). Idempotent.
  Future<void> addKey(Uint8List key) async {
    final ring = await _ring();
    ring[XrayCrypto.keyIdHex(key)] = key;
    await _saveRing(ring);
  }

  Future<Map<String, Uint8List>> allKeys() => _ring();

  // ── store ────────────────────────────────────────────────────────────────
  /// Where a patient's encrypted X-rays live on this computer.
  Future<Directory> patientDir(String patientUuid) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/DentOS/xrays/$patientUuid');
    await dir.create(recursive: true);
    return dir;
  }

  /// Reads the picked file and writes ONLY the encrypted copy — no readable
  /// version is ever placed in DentOS's folders.
  Future<({String path, String sha, int size, String keyId})> storeNew({
    required String patientUuid,
    required String uuid,
    required String sourcePath,
  }) async {
    final plain = await File(sourcePath).readAsBytes();
    final key = await activeKey();
    final sha = await XrayCrypto.sha256Async(plain);
    final enc = await XrayCrypto.encryptAsync(plain, key, uuid);

    final dir = await patientDir(patientUuid);
    final target = File('${dir.path}/$uuid.dxr');
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(enc, flush: true);
    await tmp.rename(target.path);

    return (
      path: target.path,
      sha: sha,
      size: plain.length,
      keyId: XrayCrypto.keyIdHex(key),
    );
  }

  /// Writes a .dxr that arrived in a transfer. Bytes are already encrypted.
  Future<String> storeReceived({
    required String patientUuid,
    required String uuid,
    required Uint8List dxr,
  }) async {
    final dir = await patientDir(patientUuid);
    final target = File('${dir.path}/$uuid.dxr');
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(dxr, flush: true);
    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
    return target.path;
  }

  // ── read ─────────────────────────────────────────────────────────────────
  /// Decrypted bytes of an X-ray, for display only.
  Future<Uint8List> read(XrayRow x) async {
    final hit = _cache.remove(x.uuid);
    if (hit != null) {
      _cache[x.uuid] = hit; // most recently used goes to the end
      return hit;
    }

    final file = File(x.filePath);
    if (!await file.exists()) {
      throw const FileSystemException('X-ray file is not on this computer.');
    }
    final raw = await file.readAsBytes();

    final Uint8List plain;
    if (!x.isEncrypted) {
      plain = raw; // legacy file, about to be migrated
    } else {
      final key = (await _ring())[XrayCrypto.keyIdOf(raw)];
      if (key == null) {
        throw StateError(
          'The key for this X-ray is not on this computer. Receive X-rays '
          'from the computer that took it.',
        );
      }
      plain = await XrayCrypto.decryptAsync(raw, key, x.uuid);
    }

    _remember(x.uuid, plain);
    return plain;
  }

  void _remember(String uuid, Uint8List bytes) {
    if (bytes.length > _cacheLimit ~/ 4) return; // don't cache giants
    _cache[uuid] = bytes;
    _cacheBytes += bytes.length;
    while (_cacheBytes > _cacheLimit && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _cacheBytes -= _cache.remove(oldest)!.length;
    }
  }

  void forget(String uuid) {
    final b = _cache.remove(uuid);
    if (b != null) _cacheBytes -= b.length;
  }

  // ── migrate ──────────────────────────────────────────────────────────────
  /// Encrypts every X-ray still stored as a plain file.
  ///
  /// Per file: encrypt → write to a temp name → read back and verify it
  /// decrypts to the same bytes → rename → update the row → only THEN delete
  /// the original. A crash at any point leaves either the original or a
  /// verified encrypted copy, never neither.
  ///
  /// Safe to call repeatedly; runs one batch at a time.
  Future<int> encryptPending() async {
    if (_migrating) return 0;
    _migrating = true;
    var done = 0;
    try {
      final key = await activeKey();
      final rows =
          await (_db.select(_db.patientXrays)..where(
                (t) => t.isEncrypted.equals(false) & t.isDeleted.equals(false),
              ))
              .get();

      for (final x in rows) {
        try {
          final src = File(x.filePath);
          if (!await src.exists()) continue;

          final plain = await src.readAsBytes();
          final sha = await XrayCrypto.sha256Async(plain);
          final enc = await XrayCrypto.encryptAsync(plain, key, x.uuid);

          final target = File('${src.parent.path}/${x.uuid}.dxr');
          final tmp = File('${target.path}.tmp');
          await tmp.writeAsBytes(enc, flush: true);

          // Verify before trusting it with the only copy.
          final check = await XrayCrypto.decryptAsync(
            await tmp.readAsBytes(),
            key,
            x.uuid,
          );
          if (await XrayCrypto.sha256Async(check) != sha) {
            await tmp.delete();
            continue;
          }

          if (await target.exists()) await target.delete();
          await tmp.rename(target.path);

          await (_db.update(
            _db.patientXrays,
          )..where((t) => t.id.equals(x.id))).write(
            PatientXraysCompanion(
              filePath: Value(target.path),
              isEncrypted: const Value(true),
              sha256: Value(sha),
              keyId: Value(XrayCrypto.keyIdHex(key)),
              byteSize: Value(plain.length),
              updatedAt: Value(DateTime.now()),
            ),
          );

          if (src.path != target.path) await src.delete();
          forget(x.uuid);
          done++;
        } catch (e) {
          debugPrint('XRAY encrypt failed for ${x.uuid}: $e');
        }
      }
    } finally {
      _migrating = false;
    }
    return done;
  }
}

final xrayVaultProvider = Provider(
  (ref) => XrayVault(ref.watch(appDatabaseProvider)),
);

/// Decrypted bytes for one X-ray. Keyed by uuid + path so it refreshes the
/// moment the background migration moves the file.
final xrayBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String uuid, String path, bool enc})>((ref, k) async {
      final db = ref.watch(appDatabaseProvider);
      final row = await (db.select(
        db.patientXrays,
      )..where((t) => t.uuid.equals(k.uuid))).getSingle();
      return ref.read(xrayVaultProvider).read(row);
    });
