import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import 'xray_vault.dart';

/// Basic tier: max this many X-rays stored per SUBSCRIPTION year.
const int kBasicXrayYearlyLimit = 100;

/// Basic tier: max this many before/after photos per subscription year.
/// Counted separately — photos never use up X-ray space.
const int kBasicPhotoYearlyLimit = 100;

/// Photo kinds. Everything else in the table is an X-ray.
const kPhotoKinds = ['before', 'after', 'progress'];

/// The clinic's current subscription period, derived from license expiry.
/// Period = [expiresAt - 1 year, expiresAt).
({DateTime start, DateTime end}) subscriptionPeriod(DateTime expiresAt) {
  final end = expiresAt;
  final start = DateTime(end.year - 1, end.month, end.day);
  return (start: start, end: end);
}

class XrayRepository {
  XrayRepository(this._db) : _vault = XrayVault(_db);
  final AppDatabase _db;
  final XrayVault _vault;

  Stream<List<XrayRow>> watch(int patientId) => _db.watchXrays(patientId);

  Stream<List<XrayRow>> watchPhotos(int patientId) =>
      _db.watchPhotos(patientId);

  /// Usage within the CURRENT subscription year (limited tiers only).
  Future<({int used, int limit, int left})> usage({
    required DateTime expiresAt,
    bool photos = false,
  }) async {
    final p = subscriptionPeriod(expiresAt);
    final used = photos
        ? await _db.photoCountBetween(p.start, p.end)
        : await _db.xrayCountBetween(p.start, p.end);
    final limit = photos ? kBasicPhotoYearlyLimit : kBasicXrayYearlyLimit;
    final left = limit - used;
    return (used: used, limit: limit, left: left < 0 ? 0 : left);
  }

  /// Add an X-ray or a photo. Returns an error string, or null on success.
  /// The picked file is read once and only an ENCRYPTED copy is stored.
  Future<String?> add({
    required int patientId,
    required String patientUuid,
    required String sourcePath,
    required String fileName,
    String caption = '',
    DateTime? takenAt,
    required bool isLimited,
    DateTime? expiresAt,
    String kind = 'xray',
    String? pairGroup,
    String tooth = '',
    String treatment = '',
    bool consent = false,
    String consentBy = '',
  }) async {
    final isPhoto = kind != 'xray';
    if (isLimited && expiresAt != null) {
      final p = subscriptionPeriod(expiresAt);
      final used = isPhoto
          ? await _db.photoCountBetween(p.start, p.end)
          : await _db.xrayCountBetween(p.start, p.end);
      final limit = isPhoto ? kBasicPhotoYearlyLimit : kBasicXrayYearlyLimit;
      if (used >= limit) {
        final resets = '${p.end.day}/${p.end.month}/${p.end.year}';
        final what = isPhoto ? 'photos' : 'X-rays';
        return 'Your plan allows $limit $what per subscription year. '
            'You have used $used. This resets on $resets '
            '— or upgrade to Standard/Premium for unlimited storage.';
      }
    }

    final uuid = Uuids.v4();
    final stored = await _vault.storeNew(
      patientUuid: patientUuid,
      uuid: uuid,
      sourcePath: sourcePath,
    );
    final now = DateTime.now();

    await _db
        .into(_db.patientXrays)
        .insert(
          PatientXraysCompanion.insert(
            uuid: uuid,
            clinicId: await _db.currentClinicId() ?? '',
            branchId: Value(await _db.currentBranchId()),
            patientId: patientId,
            patientUuid: patientUuid,
            filePath: stored.path,
            fileName: fileName,
            fileType: Value(
              sourcePath.toLowerCase().endsWith('.pdf') ? 'pdf' : 'image',
            ),
            caption: Value(caption),
            takenAt: Value(takenAt ?? now),
            isEncrypted: const Value(true),
            sha256: Value(stored.sha),
            byteSize: Value(stored.size),
            keyId: Value(stored.keyId),
            isLocal: const Value(true),
            originDevice: Value((await _db.localDevice()).uuid),
            updatedAt: Value(now),
            kind: Value(kind),
            // every photo belongs to a case; a lone photo is its own case
            pairGroup: Value(isPhoto ? (pairGroup ?? uuid) : null),
            tooth: Value(tooth.trim()),
            treatment: Value(treatment.trim()),
            consent: Value(consent),
            consentBy: Value(consent ? consentBy : ''),
            consentAt: Value(consent ? now : null),
          ),
        );
    return null;
  }

  /// Change one photo's kind (Before / After / Progress).
  Future<void> setPhotoKind(XrayRow row, String kind) =>
      (_db.update(_db.patientXrays)..where((t) => t.id.equals(row.id))).write(
        PatientXraysCompanion(
          kind: Value(kind),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Edit a whole case: treatment, tooth and consent apply to every photo
  /// in it, so the case reads the same on every computer.
  ///
  /// When consent changes, who changed it and when is recorded. Withdrawing
  /// consent also removes the star, so the case leaves the Showcase fully.
  Future<void> updateCase(
    String pairGroup, {
    required String treatment,
    required String tooth,
    required bool consent,
    String by = '',
  }) async {
    final rows = await _caseRows(pairGroup).get();
    final had = rows.isNotEmpty && rows.every((r) => r.consent);
    final changed = had != consent;
    final now = DateTime.now();
    await _caseUpdate(pairGroup).write(
      PatientXraysCompanion(
        treatment: Value(treatment.trim()),
        tooth: Value(tooth.trim()),
        consent: Value(consent),
        consentBy: changed ? Value(consent ? by : '') : const Value.absent(),
        consentAt: changed ? Value(consent ? now : null) : const Value.absent(),
        featured: consent ? const Value.absent() : const Value(false),
        updatedAt: Value(now),
      ),
    );
  }

  /// Star / un-star a case as one of the clinic's best.
  Future<void> setCaseFeatured(String pairGroup, bool featured) =>
      _caseUpdate(pairGroup).write(
        PatientXraysCompanion(
          featured: Value(featured),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Marketing crop for one photo ("x,y,w,h"), or null for the whole photo.
  Future<void> setCrop(XrayRow row, String? crop) =>
      (_db.update(_db.patientXrays)..where((t) => t.id.equals(row.id))).write(
        PatientXraysCompanion(
          crop: Value(crop),
          updatedAt: Value(DateTime.now()),
        ),
      );

  SimpleSelectStatement<$PatientXraysTable, XrayRow> _caseRows(String g) =>
      _db.select(_db.patientXrays)
        ..where((t) => t.pairGroup.equals(g) & t.isDeleted.equals(false));

  UpdateStatement<$PatientXraysTable, XrayRow> _caseUpdate(String g) =>
      _db.update(_db.patientXrays)
        ..where((t) => t.pairGroup.equals(g) & t.isDeleted.equals(false));

  /// Decrypted bytes (memory only) — for saving, comparing and sending.
  Future<Uint8List> readBytes(XrayRow row) => _vault.read(row);

  /// Soft-deletes the record (so the deletion syncs to every computer) and
  /// removes this computer's encrypted file.
  Future<void> delete(XrayRow row) async {
    _vault.forget(row.uuid);
    await _db.softDeleteXray(row.id);
    if (row.isLocal && row.filePath.isNotEmpty) {
      try {
        await File(row.filePath).delete();
      } catch (_) {}
    }
  }
}
