import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import 'xray_storage.dart';

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
  XrayRepository(this._db);
  final AppDatabase _db;

  Stream<List<XrayRow>> watch(int patientId) => _db.watchXrays(patientId);

  /// Usage within the CURRENT subscription year (basic tier only).
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
  Future<String?> add({
    required int patientId,
    required String patientUuid,
    required String sourcePath,
    required String fileName,
    String caption = '',
    DateTime? takenAt,
    required bool isLimited, // true only for basic tier
    DateTime? expiresAt, // subscription end; required if isLimited
  }) async {
    if (isLimited && expiresAt != null) {
      final p = subscriptionPeriod(expiresAt);
      final used = await _db.xrayCountBetween(p.start, p.end);
      if (used >= kBasicXrayYearlyLimit) {
        final resets = '${p.end.day}/${p.end.month}/${p.end.year}';
        return 'Your Basic plan allows $kBasicXrayYearlyLimit X-rays per '
            'subscription year. You have used $used. This resets on $resets — '
            'or upgrade to Standard/Premium for unlimited storage.';
      }
    }

    final uuid = Uuids.v4();
    final stored = await XrayStorage.store(
      patientUuid: patientUuid,
      sourcePath: sourcePath,
      newBaseName: uuid,
    );

    await _db
        .into(_db.patientXrays)
        .insert(
          PatientXraysCompanion.insert(
            uuid: uuid,
            clinicId: await _db.currentClinicId() ?? '',
            branchId: Value(await _db.currentBranchId()),
            patientId: patientId,
            patientUuid: patientUuid,
            filePath: stored,
            fileName: fileName,
            fileType: Value(XrayStorage.isPdf(stored) ? 'pdf' : 'image'),
            caption: Value(caption),
            takenAt: Value(takenAt ?? DateTime.now()),
          ),
        );
    return null;
  }

  Future<void> delete(XrayRow row) async {
    await _db.softDeleteXray(row.id);
    await XrayStorage.deleteFile(row.filePath);
  }
}
