import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:is_dental/licensing/data/license_verifier.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import 'xray_crypto.dart';
import 'xray_vault.dart';

/// `.dentosx` — an encrypted X-ray transfer file. NOT a zip: there is
/// nothing for Windows or macOS to open.
///
///   "DXB1" | u32 headerLen | header (JSON)
///          | u32 manifestLen | manifest (sealed with the bundle key)
///          | entries: u16 idLen | uuid | u32 len | .dxr bytes
///
/// The header holds the bundle key twice, locked two ways:
///   wrap   — with a random secret held by the cloud, released only to a
///            signed-in computer of the same clinic with the right code
///   escrow — with the Inover Studio public key, for vendor recovery
/// The .dxr entries are the files exactly as stored — never decrypted on
/// the way out.
class XrayTransfer {
  XrayTransfer(this._db, this._vault);
  final AppDatabase _db;
  final XrayVault _vault;

  static const _magic = [0x44, 0x58, 0x42, 0x31]; // "DXB1"

  // ── planning ─────────────────────────────────────────────────────────────
  Future<List<XrayRow>> _candidates(String? forDevice) async {
    final rows =
        await (_db.select(_db.patientXrays)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.isLocal.equals(true) &
                  t.isEncrypted.equals(true),
            ))
            .get();
    final present = rows.where((r) => File(r.filePath).existsSync()).toList();
    if (forDevice == null) return present;

    final inv = await (_db.select(
      _db.deviceInventories,
    )..where((t) => t.deviceUuid.equals(forDevice))).getSingleOrNull();
    final has = inv == null
        ? <String>{}
        : (jsonDecode(inv.xrayUuids) as List).cast<String>().toSet();
    return present.where((r) => !has.contains(r.uuid)).toList();
  }

  /// What a transfer would contain. forDevice null = everything.
  Future<({int count, int bytes})> plan({String? forDevice}) async {
    final c = await _candidates(forDevice);
    return (count: c.length, bytes: c.fold<int>(0, (s, r) => s + r.byteSize));
  }

  // ── export ───────────────────────────────────────────────────────────────
  Future<
    ({int count, int bytes, String? code, DateTime? expiresAt, String? error})
  >
  export({
    required String savePath,
    String? forDevice,
    required String by,
    required bool cloud,
  }) async {
    final rows = await _candidates(forDevice);
    if (rows.isEmpty) {
      return (
        count: 0,
        bytes: 0,
        code: null,
        expiresAt: null,
        error: 'Nothing to transfer — that computer already has every X-ray.',
      );
    }

    final clinicId = await _db.currentClinicId() ?? '';
    final me = await _db.localDevice();
    final bundleId = Uuids.v4();
    final bundleKey = XrayCrypto.newKey();

    // Only the keys these files need.
    final ring = await _vault.allKeys();
    final keys = <String, String>{
      for (final r in rows)
        if (r.keyId != null && ring.containsKey(r.keyId))
          r.keyId!: base64.encode(ring[r.keyId]!),
    };

    final manifest = utf8.encode(
      jsonEncode({
        'keys': keys,
        'entries': [
          for (final r in rows)
            {
              'uuid': r.uuid,
              'patientUuid': r.patientUuid,
              'branchId': r.branchId,
              'fileName': r.fileName,
              'fileType': r.fileType,
              'caption': r.caption,
              'takenAt': r.takenAt.toUtc().toIso8601String(),
              'createdAt': r.createdAt.toUtc().toIso8601String(),
              'updatedAt': (r.updatedAt ?? r.createdAt)
                  .toUtc()
                  .toIso8601String(),
              'sha256': r.sha256,
              'byteSize': r.byteSize,
              'keyId': r.keyId,
              'originDevice': r.originDevice,
            },
        ],
      }),
    );
    final sealedManifest = _seal(bundleKey, manifest, bundleId);

    final secret = cloud ? XrayCrypto.randomBytes(32) : null;
    final header = utf8.encode(
      jsonEncode({
        'format': 'dentos-xray-transfer',
        'version': 1,
        'clinicId': clinicId,
        'bundleId': bundleId,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'count': rows.length,
        'fromDevice': me.uuid,
        'forDevice': forDevice,
        'wrap': secret == null
            ? null
            : base64.encode(_seal(secret, bundleKey, '$clinicId|$bundleId')),
        'escrow': base64.encode(_escrow(bundleKey)),
      }),
    );

    final files = [for (final r in rows) (r.uuid, r.filePath)];
    final sha = await Isolate.run(
      () => _writeBundle(
        savePath,
        Uint8List.fromList(header),
        sealedManifest,
        files,
      ),
    );
    final bytes = rows.fold<int>(0, (s, r) => s + r.byteSize);

    if (!cloud) {
      return (
        count: rows.length,
        bytes: bytes,
        code: null,
        expiresAt: null,
        error: null,
      );
    }

    try {
      final res = await _call('create-xray-transfer', {
        'bundleId': bundleId,
        'bundleSha256': sha,
        'secret': base64.encode(secret!),
        'fromDevice': me.uuid,
        'toDevice': forDevice,
        'createdBy': by,
      });
      return (
        count: rows.length,
        bytes: bytes,
        code: res['code'] as String,
        expiresAt: DateTime.parse(res['expiresAt'] as String).toLocal(),
        error: null,
      );
    } catch (e) {
      // A file with no registered code is useless — don't leave it lying
      // around looking like a valid transfer.
      try {
        await File(savePath).delete();
      } catch (_) {}
      return (count: 0, bytes: 0, code: null, expiresAt: null, error: '$e');
    }
  }

  // ── receive ──────────────────────────────────────────────────────────────
  Future<({int added, int already, int noPatient, int damaged, String? error})>
  receive({
    required String path,
    String? code,
    String? vendorToken,
    void Function(int done, int total)? onProgress,
  }) async {
    ({int added, int already, int noPatient, int damaged, String? error}) fail(
      String m,
    ) => (added: 0, already: 0, noPatient: 0, damaged: 0, error: m);

    final clinicId = await _db.currentClinicId() ?? '';
    final reader = await _Reader.open(path);
    try {
      final magic = await reader.take(4);
      if (!_eq(magic, _magic)) {
        return fail('This is not a DentOS X-ray transfer file.');
      }
      final header =
          jsonDecode(utf8.decode(await reader.take(await reader.u32())))
              as Map<String, dynamic>;
      final sealedManifest = await reader.take(await reader.u32());
      final bundleId = header['bundleId'] as String;

      // ── get the bundle key ──
      Uint8List bundleKey;
      if (vendorToken != null) {
        final t = jsonDecode(vendorToken.trim()) as Map<String, dynamic>;
        final canonical = jsonEncode({
          'action': t['action'],
          'clinicId': t['clinicId'],
          'bundleId': t['bundleId'],
          'bundleKey': t['bundleKey'],
          'issuedAt': t['issuedAt'],
          'expiresAt': t['expiresAt'],
        });
        if (!LicenseVerifier().verifyCanonical(canonical, t['signature'])) {
          return fail('This recovery code is not valid.');
        }
        if (t['action'] != 'xrayRecover') {
          return fail('That is not an X-ray recovery code.');
        }
        if (t['clinicId'] != clinicId) {
          return fail('This recovery code was issued for a different clinic.');
        }
        if (t['bundleId'] != bundleId) {
          return fail('This recovery code is for a different transfer file.');
        }
        if (DateTime.parse(t['expiresAt']).isBefore(DateTime.now())) {
          return fail('This recovery code has expired.');
        }
        bundleKey = base64.decode(t['bundleKey']);
      } else {
        if (header['clinicId'] != clinicId) {
          return fail('This file belongs to a different clinic.');
        }
        if (header['wrap'] == null) {
          return fail(
            'This is a backup file. It can only be opened with a recovery '
            'code from Inover Studio.',
          );
        }
        final sha = await Isolate.run(() => _fileSha256(path));
        final me = await _db.localDevice();
        final res = await _call('redeem-xray-transfer', {
          'code': (code ?? '').trim().toUpperCase(),
          'bundleSha256': sha,
          'deviceUuid': me.uuid,
        });
        final secret = base64.decode(res['secret'] as String);
        bundleKey = _open(
          secret,
          base64.decode(header['wrap'] as String),
          '${header['clinicId']}|$bundleId',
        );
      }

      // ── manifest ──
      final manifest =
          jsonDecode(utf8.decode(_open(bundleKey, sealedManifest, bundleId)))
              as Map<String, dynamic>;
      final keys = <String, Uint8List>{};
      for (final e in (manifest['keys'] as Map).entries) {
        final k = base64.decode(e.value as String);
        keys[e.key as String] = k;
        await _vault.addKey(k);
      }
      final meta = {
        for (final e in (manifest['entries'] as List))
          (e as Map)['uuid'] as String: e.cast<String, dynamic>(),
      };

      // ── entries ──
      var added = 0, already = 0, noPatient = 0, damaged = 0;
      final total = header['count'] as int;
      for (var i = 0; i < total; i++) {
        final uuid = utf8.decode(await reader.take(await reader.u16()));
        final dxr = await reader.take(await reader.u32());
        onProgress?.call(i + 1, total);
        final m = meta[uuid];
        if (m == null) {
          damaged++;
          continue;
        }

        final existing = await (_db.select(
          _db.patientXrays,
        )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        if (existing != null &&
            existing.isLocal &&
            existing.filePath.isNotEmpty &&
            await File(existing.filePath).exists()) {
          already++;
          continue;
        }

        final patient = await (_db.select(
          _db.patients,
        )..where((t) => t.uuid.equals(m['patientUuid']))).getSingleOrNull();
        if (patient == null) {
          noPatient++;
          continue;
        }

        // Verify before trusting it: right key, unaltered, and the bytes
        // inside are exactly the original image.
        final key = keys[XrayCrypto.keyIdOf(dxr)];
        if (key == null) {
          damaged++;
          continue;
        }
        try {
          final plain = await XrayCrypto.decryptAsync(dxr, key, uuid);
          if (m['sha256'] != null &&
              await XrayCrypto.sha256Async(plain) != m['sha256']) {
            damaged++;
            continue;
          }
        } catch (_) {
          damaged++;
          continue;
        }

        final stored = await _vault.storeReceived(
          patientUuid: patient.uuid,
          uuid: uuid,
          dxr: dxr,
        );

        if (existing == null) {
          await _db
              .into(_db.patientXrays)
              .insert(
                PatientXraysCompanion.insert(
                  uuid: uuid,
                  clinicId: clinicId,
                  branchId: Value(m['branchId'] as String?),
                  patientId: patient.id,
                  patientUuid: patient.uuid,
                  filePath: stored,
                  fileName: (m['fileName'] ?? '') as String,
                  fileType: Value((m['fileType'] ?? 'image') as String),
                  caption: Value((m['caption'] ?? '') as String),
                  takenAt: Value(DateTime.parse(m['takenAt']).toLocal()),
                  createdAt: Value(DateTime.parse(m['createdAt']).toLocal()),
                  isEncrypted: const Value(true),
                  sha256: Value(m['sha256'] as String?),
                  byteSize: Value((m['byteSize'] as num?)?.toInt() ?? 0),
                  keyId: Value(m['keyId'] as String?),
                  isLocal: const Value(true),
                  originDevice: Value(m['originDevice'] as String?),
                  updatedAt: Value(DateTime.parse(m['updatedAt']).toLocal()),
                ),
              );
        } else {
          // The placeholder from the synced list becomes the real thing.
          await (_db.update(
            _db.patientXrays,
          )..where((t) => t.id.equals(existing.id))).write(
            PatientXraysCompanion(
              patientId: Value(patient.id),
              filePath: Value(stored),
              isLocal: const Value(true),
              isEncrypted: const Value(true),
              keyId: Value(m['keyId'] as String?),
              sha256: Value(m['sha256'] as String?),
              byteSize: Value((m['byteSize'] as num?)?.toInt() ?? 0),
            ),
          );
        }
        _vault.forget(uuid);
        added++;
      }

      return (
        added: added,
        already: already,
        noPatient: noPatient,
        damaged: damaged,
        error: null,
      );
    } on FormatException {
      return fail('This file is damaged or incomplete.');
    } on InvalidCipherTextException {
      return fail('The file could not be unlocked — it may have been altered.');
    } catch (e) {
      return fail('$e'.replaceFirst('Exception: ', ''));
    } finally {
      await reader.close();
    }
  }

  /// What the clinic sends Inover Studio when the code is lost or the
  /// clinic ID changed. Contains only the vendor-locked key.
  Future<String> recoveryRequest(String path) async {
    final reader = await _Reader.open(path);
    try {
      if (!_eq(await reader.take(4), _magic)) {
        throw const FormatException('Not a DentOS X-ray transfer file.');
      }
      final header =
          jsonDecode(utf8.decode(await reader.take(await reader.u32())))
              as Map<String, dynamic>;
      return base64Url.encode(
        utf8.encode(
          jsonEncode({
            'bundleId': header['bundleId'],
            'sourceClinicId': header['clinicId'],
            'escrow': header['escrow'],
          }),
        ),
      );
    } finally {
      await reader.close();
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _call(
    String fn,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        fn,
        body: body,
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return data.cast<String, dynamic>();
      }
      throw Exception(
        (data is Map ? data['error']?.toString() : null) ?? 'Request failed.',
      );
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(
        (d is Map ? d['error']?.toString() : null) ??
            'Request failed (${e.status}).',
      );
    }
  }

  static Uint8List _seal(Uint8List key, List<int> plain, String aad) {
    final nonce = XrayCrypto.randomBytes(12);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(aad)),
        ),
      );
    final ct = gcm.process(Uint8List.fromList(plain));
    return (BytesBuilder(copy: false)
          ..add(nonce)
          ..add(ct))
        .takeBytes();
  }

  static Uint8List _open(Uint8List key, Uint8List sealed, String aad) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          Uint8List.sublistView(sealed, 0, 12),
          Uint8List.fromList(utf8.encode(aad)),
        ),
      );
    return gcm.process(Uint8List.sublistView(sealed, 12));
  }

  static Uint8List _escrow(Uint8List bundleKey) {
    final rsa = OAEPEncoding(RSAEngine())
      ..init(
        true,
        PublicKeyParameter<RSAPublicKey>(LicenseVerifier.vendorPublicKey),
      );
    return rsa.process(bundleKey);
  }

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── isolate workers ─────────────────────────────────────────────────────────
Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
Uint8List _u16(int v) => (ByteData(2)..setUint16(0, v)).buffer.asUint8List();

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Streams the bundle to disk and hashes it on the way — no file is ever
/// fully loaded alongside the others, and no second pass is needed.
String _writeBundle(
  String outPath,
  Uint8List header,
  Uint8List manifest,
  List<(String, String)> files,
) {
  final tmp = File('$outPath.part');
  final raf = tmp.openSync(mode: FileMode.write);
  final d = SHA256Digest();
  void put(Uint8List b) {
    raf.writeFromSync(b);
    d.update(b, 0, b.length);
  }

  put(Uint8List.fromList(const [0x44, 0x58, 0x42, 0x31]));
  put(_u32(header.length));
  put(header);
  put(_u32(manifest.length));
  put(manifest);
  for (final (id, p) in files) {
    final idb = Uint8List.fromList(utf8.encode(id));
    final data = File(p).readAsBytesSync();
    put(_u16(idb.length));
    put(idb);
    put(_u32(data.length));
    put(data);
  }
  raf.flushSync();
  raf.closeSync();

  final out = File(outPath);
  if (out.existsSync()) out.deleteSync();
  tmp.renameSync(outPath);

  final h = Uint8List(32);
  d.doFinal(h, 0);
  return _hex(h);
}

String _fileSha256(String path) {
  final d = SHA256Digest();
  final raf = File(path).openSync();
  final buf = Uint8List(1 << 20);
  while (true) {
    final n = raf.readIntoSync(buf);
    if (n <= 0) break;
    d.update(buf, 0, n);
  }
  raf.closeSync();
  final h = Uint8List(32);
  d.doFinal(h, 0);
  return _hex(h);
}

/// Sequential reader — the bundle is read once, front to back.
class _Reader {
  _Reader(this._raf);
  final RandomAccessFile _raf;

  static Future<_Reader> open(String path) async =>
      _Reader(await File(path).open());

  Future<Uint8List> take(int n) async {
    final b = await _raf.read(n);
    if (b.length != n) throw const FormatException('Truncated file.');
    return b;
  }

  Future<int> u32() async => ByteData.sublistView(await take(4)).getUint32(0);
  Future<int> u16() async => ByteData.sublistView(await take(2)).getUint16(0);
  Future<void> close() => _raf.close();
}

final xrayTransferProvider = Provider((ref) {
  final db = ref.watch(appDatabaseProvider);
  return XrayTransfer(db, XrayVault(db));
});
