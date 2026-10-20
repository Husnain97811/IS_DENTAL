import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/views.dart';

/// How far back the clinic-wide prescription list looks.
enum RxPeriod {
  all('All time'),
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days');

  const RxPeriod(this.label);
  final String label;

  DateTime? get since {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      RxPeriod.all => null,
      RxPeriod.today => today,
      RxPeriod.week => today.subtract(const Duration(days: 6)),
      RxPeriod.month => today.subtract(const Duration(days: 29)),
    };
  }
}

/// One line of the "All prescriptions" list — just enough to show and
/// search it. The full prescription is loaded only when it is opened.
class RxListEntry {
  const RxListEntry({
    required this.id,
    required this.rxNo,
    required this.issuedAt,
    required this.doctorName,
    required this.patientId,
    required this.patientUuid,
    required this.patientName,
    required this.patientCode,
    required this.phone,
    required this.allergies,
    required this.medicines,
  });

  final int id, patientId;
  final String rxNo, doctorName, patientUuid, patientName, patientCode, phone;
  final String? allergies;
  final List<String> medicines;

  final DateTime issuedAt;

  bool get hasAllergy => (allergies ?? '').trim().isNotEmpty;

  String get medicinesLine => medicines.isEmpty
      ? 'Advice only'
      : medicines.length <= 3
      ? medicines.join(', ')
      : '${medicines.take(3).join(', ')} +${medicines.length - 3} more';
}

typedef RxListQuery = ({String text, RxPeriod period});

/// The list stops here so a clinic with years of history stays fast;
/// searching reaches every prescription.
const kRxListLimit = 200;

final allPrescriptionsProvider = StreamProvider.autoDispose
    .family<List<RxListEntry>, RxListQuery>((ref, q) {
      final db = ref.watch(appDatabaseProvider);
      final branch = ref.watch(activeBranchProvider);
      return watchAllPrescriptions(
        db,
        text: q.text,
        since: q.period.since,
        branchId: branch,
      );
    });

/// Every prescription in the branch, newest first, with the patient's
/// details. [text] matches the RX number, patient name, file number,
/// phone or any medicine on it.
Stream<List<RxListEntry>> watchAllPrescriptions(
  AppDatabase db, {
  String text = '',
  DateTime? since,
  String? branchId,
  int limit = kRxListLimit,
}) {
  final rx = db.prescriptions;
  final p = db.patients;
  final items = db.prescriptionItems;

  Expression<bool> where = rx.isDeleted.equals(false);
  if (branchId != null) {
    // older prescriptions carry no branch — they follow their patient's
    where =
        where &
        (rx.branchId.equals(branchId) |
            (rx.branchId.isNull() & p.branchId.equals(branchId)));
  }
  if (since != null) where = where & rx.issuedAt.isBiggerOrEqualValue(since);

  final t = text.trim().replaceAll(RegExp(r'[%_]'), '');
  if (t.isNotEmpty) {
    final like = '%$t%';
    final withMedicine = db.selectOnly(items)
      ..addColumns([items.prescriptionId])
      ..where(items.medicine.like(like));
    where =
        where &
        (rx.rxNo.like(like) |
            p.fullName.like(like) |
            p.code.like(like) |
            p.phone.like(like) |
            rx.id.isInQuery(withMedicine));
  }

  final query = db.select(rx).join([innerJoin(p, p.id.equalsExp(rx.patientId))])
    ..where(where)
    ..orderBy([OrderingTerm.desc(rx.issuedAt), OrderingTerm.desc(rx.id)])
    ..limit(limit);

  return query.watch().asyncMap((rows) async {
    if (rows.isEmpty) return const <RxListEntry>[];
    final ids = [for (final r in rows) r.readTable(rx).id];
    final lines =
        await (db.select(items)
              ..where((i) => i.prescriptionId.isIn(ids))
              ..orderBy([(i) => OrderingTerm.asc(i.position)]))
            .get();
    final meds = <int, List<String>>{};
    for (final l in lines) {
      final name = l.medicine.trim();
      if (name.isNotEmpty) (meds[l.prescriptionId] ??= []).add(name);
    }
    RxListEntry entry(TypedResult r) {
      final x = r.readTable(rx);
      final pt = r.readTable(p);
      return RxListEntry(
        id: x.id,
        rxNo: x.rxNo,
        issuedAt: x.issuedAt,
        doctorName: x.doctorName,
        patientId: pt.id,
        patientUuid: x.patientUuid,
        patientName: pt.fullName,
        patientCode: pt.code,
        phone: pt.phone,
        allergies: pt.allergies,
        medicines: meds[x.id] ?? const [],
      );
    }

    return [for (final r in rows) entry(r)];
  });
}
