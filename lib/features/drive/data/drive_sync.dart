import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show ClientException;
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/hub/data/activity_log.dart';
import 'package:is_dental/features/patients/data/xray_crypto.dart';
import 'package:is_dental/features/patients/data/xray_vault.dart';

import 'drive_client.dart';
import 'drive_config.dart';

/// What one run has to do. Pure — unit-tested on its own.
///
/// - upload:   on this computer, not on Drive yet (first connect = backfill
///             of everything already saved)
/// - download: listed here (synced from another computer) but the file is
///             missing, and Drive has it
/// - remove:   deleted in DentOS, still on Drive
class DrivePlan {
  const DrivePlan(this.upload, this.download, this.remove);
  final List<XrayRow> upload, download;
  final List<String> remove; // Drive file ids
  bool get isEmpty => upload.isEmpty && download.isEmpty && remove.isEmpty;
}

DrivePlan planDriveSync({
  required List<XrayRow> rows,
  required Map<String, String> remote, // xray uuid → Drive file id
  required bool Function(XrayRow) fileHere,
}) {
  final up = <XrayRow>[], down = <XrayRow>[], gone = <String>[];
  for (final r in rows) {
    final onDrive = remote[r.uuid];
    if (r.isDeleted) {
      if (onDrive != null) gone.add(onDrive);
      continue;
    }
    if (!r.isEncrypted) continue; // waits for the encryption migration
    final here = r.isLocal && fileHere(r);
    if (here && onDrive == null) up.add(r);
    if (!here && onDrive != null) down.add(r);
  }
  return DrivePlan(up, down, gone);
}

/// Locks an X-ray key for the cloud with the clinic's Drive secret.
/// AES-256-GCM, the key id + clinic as associated data, so a sealed key
/// can't be swapped onto another id or clinic.
String sealKey(Uint8List secret, Uint8List key, String aad) {
  final nonce = XrayCrypto.randomBytes(12);
  final gcm = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(secret),
        128,
        nonce,
        Uint8List.fromList(utf8.encode(aad)),
      ),
    );
  final ct = gcm.process(key);
  return base64.encode(
    (BytesBuilder(copy: false)
          ..add(nonce)
          ..add(ct))
        .takeBytes(),
  );
}

Uint8List openKey(Uint8List secret, String sealed, String aad) {
  final b = base64.decode(sealed);
  final gcm = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(secret),
        128,
        Uint8List.sublistView(b, 0, 12),
        Uint8List.fromList(utf8.encode(aad)),
      ),
    );
  return gcm.process(Uint8List.sublistView(b, 12));
}

class DriveSyncState {
  const DriveSyncState({
    this.connected = false,
    this.email = '',
    this.busy = false,
    this.stage = '',
    this.done = 0,
    this.total = 0,
    this.lastSync,
    this.lastUp = 0,
    this.lastDown = 0,
    this.failed = 0,
    this.error,
  });

  final bool connected, busy;
  final String email, stage;
  final int done, total, lastUp, lastDown, failed;
  final DateTime? lastSync;
  final String? error;

  DriveSyncState copyWith({
    bool? connected,
    String? email,
    bool? busy,
    String? stage,
    int? done,
    int? total,
    DateTime? lastSync,
    int? lastUp,
    int? lastDown,
    int? failed,
    String? error,
    bool clearError = false,
  }) => DriveSyncState(
    connected: connected ?? this.connected,
    email: email ?? this.email,
    busy: busy ?? this.busy,
    stage: stage ?? this.stage,
    done: done ?? this.done,
    total: total ?? this.total,
    lastSync: lastSync ?? this.lastSync,
    lastUp: lastUp ?? this.lastUp,
    lastDown: lastDown ?? this.lastDown,
    failed: failed ?? this.failed,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Keeps X-rays and photos in step through the clinic's Google Drive.
///
/// Each computer signs in to the SAME Google account once. DentOS then:
///  • uploads every X-ray / photo on this computer that isn't on Drive yet
///    (the first run uploads everything already saved),
///  • downloads every one listed in DentOS but missing here,
///  • removes from Drive what was deleted in DentOS,
/// every 10 minutes and shortly after a new one is added or synced.
///
/// What Drive holds is the already-encrypted .dxr file. The keys travel
/// through DentOS cloud, locked with a secret that lives only on Drive —
/// Google alone can't open a file, and DentOS cloud alone can't either.
class DriveSyncController extends Notifier<DriveSyncState> {
  late DriveClient _client;
  Timer? _timer, _debounce;
  StreamSubscription<Object?>? _watch;
  bool _running = false;
  int _gen = 0;

  static const _kLast = 'gdrive_last_sync';

  @override
  DriveSyncState build() {
    final g = ++_gen;
    _client = DriveClient(ref.watch(appDatabaseProvider));
    ref.onDispose(() {
      if (g == _gen) _gen++;
      _timer?.cancel();
      _debounce?.cancel();
      _watch?.cancel();
    });
    Future.microtask(() => _init(g));
    return const DriveSyncState();
  }

  bool _alive(int g) => g == _gen;

  /// Applies [f] to the state only while this generation is alive — a
  /// disposed controller is never touched.
  void _set(int g, DriveSyncState Function(DriveSyncState s) f) {
    if (_alive(g)) state = f(state);
  }

  Future<void> _init(int g) async {
    final t = await _client.tokens();
    final db = ref.read(appDatabaseProvider);
    final last = DateTime.tryParse(await db.getSetting(_kLast) ?? '');
    if (!_alive(g)) return;
    _set(
      g,
      (s) => s.copyWith(
        connected: t != null,
        email: t?.email ?? '',
        lastSync: last,
      ),
    );
    if (t != null) _startAuto(g);
  }

  void _startAuto(int g) {
    final db = ref.read(appDatabaseProvider);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => run());
    // A new X-ray here, or a new listing from another computer → run soon.
    _watch?.cancel();
    _watch = db
        .customSelect(
          'SELECT COUNT(*) AS n, COALESCE(SUM(is_local), 0) AS l, '
          'COALESCE(SUM(is_deleted), 0) AS d FROM patient_xrays',
          readsFrom: {db.patientXrays},
        )
        .watchSingle()
        .map((r) => '${r.data['n']}:${r.data['l']}:${r.data['d']}')
        .distinct()
        .skip(1)
        .listen((_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 15), run);
        });
    Future.delayed(const Duration(seconds: 20), () {
      if (_alive(g)) run();
    });
  }

  /// Settings → Connect Google Drive.
  Future<String?> connect() async {
    final g = _gen;
    try {
      final t = await _client.connect();
      final db = ref.read(appDatabaseProvider);
      unawaited(
        logActivity(
          db,
          'drive_connected',
          session: ref.read(authControllerProvider),
          detail: t.email,
        ),
      );
      _set(
        g,
        (s) => s.copyWith(connected: true, email: t.email, clearError: true),
      );
      _startAuto(g);
      unawaited(run());
      return null;
    } on DriveException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not connect Google Drive: $e';
    }
  }

  Future<void> disconnect() async {
    final g = _gen;
    _timer?.cancel();
    _debounce?.cancel();
    await _watch?.cancel();
    _watch = null;
    await _client.disconnect();
    unawaited(
      logActivity(
        ref.read(appDatabaseProvider),
        'drive_disconnected',
        session: ref.read(authControllerProvider),
      ),
    );
    _set(g, (_) => const DriveSyncState());
  }

  /// One full pass. Safe to call any time; a second call while one is
  /// running does nothing.
  Future<void> run() async {
    if (_running) return;
    final g = _gen;
    if (!state.connected) return;
    _running = true;
    final db = ref.read(appDatabaseProvider);
    final vault = ref.read(xrayVaultProvider);
    final cloud = ref.read(cloudServiceProvider);
    var up = 0, down = 0, failed = 0;
    void stage(String text, [int done = 0, int total = 0]) => _set(
      g,
      (s) => s.copyWith(busy: true, stage: text, done: done, total: total),
    );

    try {
      stage('Checking Google Drive…');
      final cid = await db.currentClinicId();
      if (cid == null) return;
      final clinic = await db.clinicName() ?? 'Clinic';

      final folder = await _folder(cid, clinic);
      final secret = await _secret(folder, cid);

      stage('Sharing keys…');
      await cloud.ensureSignedIn();
      await _syncKeys(cid, secret, vault);

      stage('Comparing…');
      final remote = <String, String>{};
      for (final f in await _client.list(
        "'$folder' in parents and trashed = false",
      )) {
        final u = f.props['xrayUuid'];
        if (u != null && f.props['dentosKind'] == 'dxr') remote[u] = f.id;
      }
      final rows = await db.select(db.patientXrays).get();
      final plan = planDriveSync(
        rows: rows,
        remote: remote,
        fileHere: (r) => r.filePath.isNotEmpty && File(r.filePath).existsSync(),
      );

      // ── upload (first run: everything already saved) ──
      for (var i = 0; i < plan.upload.length; i++) {
        if (!_alive(g)) return;
        final r = plan.upload[i];
        stage('Uploading', i + 1, plan.upload.length);
        try {
          await _client.upload(
            folderId: folder,
            name: '${r.uuid}.dxr',
            bytes: await File(r.filePath).readAsBytes(),
            props: {
              'dentosClinic': cid,
              'dentosKind': 'dxr',
              'xrayUuid': r.uuid,
              if (r.keyId != null) 'keyId': r.keyId!,
            },
          );
          up++;
        } catch (e) {
          failed++;
          debugPrint('DRIVE upload ${r.uuid} failed: $e');
          if (e is DriveException && e.status == 401) rethrow;
        }
      }

      // ── download what this computer is missing ──
      final ring = await vault.allKeys();
      for (var i = 0; i < plan.download.length; i++) {
        if (!_alive(g)) return;
        final r = plan.download[i];
        stage('Downloading', i + 1, plan.download.length);
        try {
          if (await _receive(db, vault, ring, r, remote[r.uuid]!)) {
            down++;
          } else {
            failed++;
          }
        } catch (e) {
          failed++;
          debugPrint('DRIVE download ${r.uuid} failed: $e');
          if (e is DriveException && e.status == 401) rethrow;
        }
      }

      // ── deleted in DentOS → off Drive too ──
      for (final id in plan.remove) {
        try {
          await _client.delete(id);
        } catch (_) {}
      }

      final now = DateTime.now();
      await db.setSetting(_kLast, now.toIso8601String());
      _set(
        g,
        (s) => s.copyWith(
          busy: false,
          stage: '',
          done: 0,
          total: 0,
          lastSync: now,
          lastUp: up,
          lastDown: down,
          failed: failed,
          clearError: true,
        ),
      );
    } on DriveException catch (e) {
      final signedOut = e.status == 401 && await _client.tokens() == null;
      _set(
        g,
        (s) => s.copyWith(
          busy: false,
          stage: '',
          connected: !signedOut,
          error: e.message,
          lastUp: up,
          lastDown: down,
          failed: failed,
        ),
      );
    } catch (e) {
      _set(
        g,
        (s) => s.copyWith(
          busy: false,
          stage: '',
          error:
              e is SocketException ||
                  e is TimeoutException ||
                  e is ClientException
              ? 'No internet — Google Drive will catch up when the '
                    'connection is back.'
              : 'Google Drive sync stopped: $e',
          lastUp: up,
          lastDown: down,
          failed: failed,
        ),
      );
    } finally {
      _running = false;
      _set(g, (s) => s.busy ? s.copyWith(busy: false, stage: '') : s);
    }
  }

  /// The clinic's DentOS folder on Drive — found by its tag, created once.
  /// Two computers creating it at the same moment both end up using the
  /// oldest one.
  Future<String> _folder(String cid, String clinic) async {
    final db = ref.read(appDatabaseProvider);
    final cacheKey = 'gdrive_folder:$cid';
    final q =
        "mimeType = '${DriveClient.folderMime}' and trashed = false and "
        "appProperties has { key='dentosClinic' and value='$cid' }";
    var found = await _client.list(q);
    if (found.isEmpty) {
      await _client.createFolder('DentOS — $clinic (do not edit)', {
        'dentosClinic': cid,
        'dentosKind': 'root',
      });
      found = await _client.list(q);
    }
    if (found.isEmpty) throw DriveException('Could not create the folder.');
    await db.setSetting(cacheKey, found.first.id);
    return found.first.id;
  }

  /// The clinic's Drive secret (32 random bytes) — a small file in the
  /// folder. Created by the first computer; every computer then uses the
  /// oldest one.
  Future<Uint8List> _secret(String folder, String cid) async {
    final q =
        "'$folder' in parents and trashed = false and "
        "appProperties has { key='dentosKind' and value='secret' }";
    var found = await _client.list(q);
    if (found.isEmpty) {
      await _client.upload(
        folderId: folder,
        name: 'dentos-key (do not delete)',
        bytes: Uint8List.fromList(
          utf8.encode(base64.encode(XrayCrypto.randomBytes(32))),
        ),
        props: {'dentosClinic': cid, 'dentosKind': 'secret'},
      );
      found = await _client.list(q);
    }
    if (found.isEmpty) throw DriveException('Could not create the key file.');
    final raw = await _client.download(found.first.id);
    final secret = base64.decode(utf8.decode(raw).trim());
    if (secret.length != 32) throw DriveException('The key file is damaged.');
    return secret;
  }

  /// Every X-ray key on this computer goes up (sealed); every key another
  /// computer sealed comes down into the keyring.
  Future<void> _syncKeys(String cid, Uint8List secret, XrayVault vault) async {
    final sb = Supabase.instance.client;
    final cloudRows =
        (await sb
                    .from('xray_keys')
                    .select('key_id, sealed')
                    .eq('clinic_id', cid)
                    .timeout(const Duration(seconds: 15))
                as List)
            .cast<Map<String, dynamic>>();
    final inCloud = {for (final r in cloudRows) '${r['key_id']}': r};
    final ring = await vault.allKeys();

    final missing = [
      for (final e in ring.entries)
        if (!inCloud.containsKey(e.key))
          {
            'clinic_id': cid,
            'key_id': e.key,
            'sealed': sealKey(secret, e.value, '$cid|${e.key}'),
          },
    ];
    if (missing.isNotEmpty) {
      await sb
          .from('xray_keys')
          .upsert(
            missing,
            onConflict: 'clinic_id,key_id',
            ignoreDuplicates: true,
          )
          .timeout(const Duration(seconds: 15));
    }

    for (final e in inCloud.entries) {
      if (ring.containsKey(e.key)) continue;
      try {
        final key = openKey(secret, '${e.value['sealed']}', '$cid|${e.key}');
        if (XrayCrypto.keyIdHex(key) == e.key) await vault.addKey(key);
      } catch (_) {
        // sealed with another Drive secret — skip
      }
    }
  }

  /// Downloads one file, checks it opens and matches, stores it.
  Future<bool> _receive(
    AppDatabase db,
    XrayVault vault,
    Map<String, Uint8List> ring,
    XrayRow r,
    String fileId,
  ) async {
    final dxr = await _client.download(fileId);
    final keyId = XrayCrypto.keyIdOf(dxr);
    final key = ring[keyId];
    if (key == null) return false; // its key hasn't reached the cloud yet
    final plain = await XrayCrypto.decryptAsync(dxr, key, r.uuid);
    if (r.sha256 != null && await XrayCrypto.sha256Async(plain) != r.sha256) {
      return false; // damaged or not this X-ray
    }
    final path = await vault.storeReceived(
      patientUuid: r.patientUuid,
      uuid: r.uuid,
      dxr: dxr,
    );
    // updatedAt is left alone on purpose — this computer only gained the
    // file, nothing about the X-ray changed, so nothing must sync back.
    await (db.update(db.patientXrays)..where((t) => t.id.equals(r.id))).write(
      PatientXraysCompanion(
        filePath: Value(path),
        isLocal: const Value(true),
        isEncrypted: const Value(true),
        keyId: Value(keyId),
        byteSize: Value(plain.length),
      ),
    );
    vault.forget(r.uuid);
    return true;
  }
}

final driveSyncProvider = NotifierProvider<DriveSyncController, DriveSyncState>(
  DriveSyncController.new,
);

/// Drive is available on cloud plans (the keys travel through DentOS
/// cloud) when this DentOS build has Google sign-in set up.
final driveAvailableProvider = Provider<bool>(
  (ref) =>
      DriveConfig.configured &&
      ref.watch(entitlementsProvider.select((e) => e.sync)),
);
