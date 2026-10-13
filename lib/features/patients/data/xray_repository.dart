import 'dart:io';
import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import 'xray_vault.dart';

/// Basic tier: max this many X-rays stored per SUBSCRIPTION year.
const int kBasicXrayYearlyLimit = 100;

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

  /// Usage within the CURRENT subscription year (limited tiers only).
  Future<({int used, int limit, int left})> usage({
    required DateTime expiresAt,
  }) async {
    final p = subscriptionPeriod(expiresAt);
    final used = await _db.xrayCountBetween(p.start, p.end);
    final left = kBasicXrayYearlyLimit - used;
    return (
      used: used,
      limit: kBasicXrayYearlyLimit,
      left: left < 0 ? 0 : left,
    );
  }

  /// Add an X-ray. Returns an error string, or null on success.
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
  }) async {
    if (isLimited && expiresAt != null) {
      final p = subscriptionPeriod(expiresAt);
      final used = await _db.xrayCountBetween(p.start, p.end);
      if (used >= kBasicXrayYearlyLimit) {
        final resets = '${p.end.day}/${p.end.month}/${p.end.year}';
        return 'Your plan allows $kBasicXrayYearlyLimit X-rays per '
            'subscription year. You have used $used. This resets on $resets '
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
          ),
        );
    return null;
  }

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
