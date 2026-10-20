import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/core/utils/uuids.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Daily cash closing + dentist commission
// ═════════════════════════════════════════════════════════════════════════════

/// Which tab the Billing screen shows (0 Invoices · 1 Day close). Kept in a
/// provider so the Dashboard's "close the day" card can open the right tab.
class _TabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int v) => state = v;
}

final billingTabProvider = NotifierProvider<_TabNotifier, int>(
  _TabNotifier.new,
);

/// 0 Expenses · 1 Dentist payouts.
final expensesTabProvider = NotifierProvider<_TabNotifier, int>(
  _TabNotifier.new,
);

/// A day the Dashboard asks Day close to open on ('yyyy-mm-dd'). Day close
/// reads it once and clears it.
class _DayTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final dayCloseTargetProvider = NotifierProvider<_DayTargetNotifier, String?>(
  _DayTargetNotifier.new,
);

/// How many days back "you forgot to close" looks.
const kMissedLookbackDays = 7;

/// The clinic's closing time on [day], or null if the clinic is closed that
/// day. The "close the day" reminder appears one hour before it.
///
/// TODO(schedule): connect to the clinic's opening hours. Until then every
/// day closes at 7 pm, so the reminder shows from 6 pm.
Future<({int hour, int minute})?> clinicClosingTime(
  Ref ref,
  DateTime day,
) async {
  final db = ref.watch(appDatabaseProvider);
  final active = ref.watch(activeBranchProvider);
  final rows = await (db.select(
    db.branches,
  )..where((t) => t.isDeleted.equals(false))).get();
  if (rows.isEmpty) return (hour: 19, minute: 0);
  final mine = active == null
      ? rows
      : rows.where((b) => b.uuid == active).toList();
  int? latest;
  for (final b in mine.isEmpty ? rows : mine) {
    final closed = b.closedDays
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
    if (closed.contains(day.weekday)) continue;
    final close = b.closeMinutes <= b.openMinutes || b.closeMinutes > 1439
        ? 1439
        : b.closeMinutes;
    if (latest == null || close > latest) latest = close;
  }
  if (latest == null) return null;
  return (hour: latest ~/ 60, minute: latest % 60);
}

final clinicClosingTimeProvider = FutureProvider.autoDispose
    .family<({int hour, int minute})?, String>(
      (ref, key) => clinicClosingTime(ref, parseDayKey(key)),
    );

/// Expense category every commission payout is filed under.
const kCommissionCategory = 'Dentist commission';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The description written on a payout expense. It is also how a payout is
/// recognised later (and on other computers), so it must stay stable:
/// "Commission · Dr Ali · Oct 2026".
String commissionDescription(String dentist, DateTime month) =>
    'Commission · ${dentist.trim()} · ${_monthNames[month.month - 1]} ${month.year}';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

bool _isCash(String method) => method.trim().toLowerCase() == 'cash';

/// What one day looks like before (or after) it is closed.
class CashDay {
  const CashDay({
    required this.day,
    required this.suggestedFloat,
    required this.cashIn,
    required this.cashOut,
    required this.cashPayments,
    required this.otherMethods,
    required this.closing,
  });

  final DateTime day;

  /// Opening cash suggested from the previous closing (what was left in
  /// the drawer). 0 when there is no earlier closing.
  final int suggestedFloat;

  /// Cash payments received that day, and cash expenses paid that day.
  final int cashIn, cashOut;

  /// Number of cash payments, for the "12 payments" line.
  final int cashPayments;

  /// Money received by other methods (card, JazzCash …) — shown for
  /// information; it never goes into the drawer.
  final Map<String, int> otherMethods;

  /// The saved closing, if this day was already closed.
  final CashClosingRow? closing;

  int expectedWith(int float) => float + cashIn - cashOut;

  /// True when payments/expenses changed after the day was closed.
  bool get changedSinceClosing =>
      closing != null &&
      (closing!.cashIn != cashIn || closing!.cashOut != cashOut);
}

/// One dentist's line on the commission sheet.
class CommissionLine {
  const CommissionLine({
    required this.dentist,
    required this.collected,
    required this.percent,
    required this.visits,
    required this.payments,
    this.paid = 0,
  });

  /// '' = payments that could not be linked to any dentist.
  final String dentist;
  final int collected;
  final double percent;
  final int visits;
  final List<CommissionPayment> payments;

  /// Already paid out for this month (payout expenses).
  final int paid;

  int get commission => (collected * percent / 100).round();
  int get clinicShare => collected - commission;
  bool get unassigned => dentist.isEmpty;

  /// Still to pay. Negative when more was paid than earned.
  int get due => commission - paid;
}

class CommissionPayment {
  const CommissionPayment({
    required this.paidAt,
    required this.patient,
    required this.invoiceNo,
    required this.amount,
  });
  final DateTime paidAt;
  final String patient;
  final String invoiceNo;
  final int amount;
}

class CommissionSheet {
  const CommissionSheet({required this.month, required this.lines});

  /// First day of the month.
  final DateTime month;
  final List<CommissionLine> lines;

  int get totalCollected => lines.fold(0, (s, l) => s + l.collected);
  int get totalCommission =>
      lines.where((l) => !l.unassigned).fold(0, (s, l) => s + l.commission);
  int get totalPaid =>
      lines.where((l) => !l.unassigned).fold(0, (s, l) => s + l.paid);
  int get totalDue => lines
      .where((l) => !l.unassigned && l.due > 0)
      .fold(0, (s, l) => s + l.due);
}

class CashRepository {
  CashRepository(this._db);
  final AppDatabase _db;

  Expression<bool> _branchText(GeneratedColumn<String> col, String? b) =>
      b == null ? const Constant(true) : col.equals(b);

  String _closingUuid(String clinicId, String? branchId, String day) =>
      'close:$clinicId:${(branchId == null || branchId.isEmpty) ? 'all' : branchId}:$day';

  // ── cash closing ──────────────────────────────────────────────────────────

  Future<CashDay> loadDay(DateTime day, String? branchId) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final key = dayKey(start);

    final pays =
        await (_db.select(_db.invoicePayments)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.paidAt.isBiggerOrEqualValue(start) &
                  t.paidAt.isSmallerThanValue(end) &
                  _branchText(t.branchId, branchId),
            ))
            .get();
    final exps =
        await (_db.select(_db.expenses)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.paidAt.isBiggerOrEqualValue(start) &
                  t.paidAt.isSmallerThanValue(end) &
                  _branchText(t.branchId, branchId),
            ))
            .get();

    var cashIn = 0, cashCount = 0;
    final other = <String, int>{};
    for (final p in pays) {
      if (_isCash(p.method)) {
        cashIn += p.amount;
        cashCount++;
      } else {
        final m = p.method.trim().isEmpty ? 'Other' : p.method.trim();
        other[m] = (other[m] ?? 0) + p.amount;
      }
    }
    final cashOut = exps
        .where((e) => _isCash(e.method))
        .fold<int>(0, (s, e) => s + e.amount);

    final clinicId = await _db.currentClinicId() ?? '';
    final closing =
        await (_db.select(_db.cashClosings)..where(
              (t) =>
                  t.uuid.equals(_closingUuid(clinicId, branchId, key)) &
                  t.isDeleted.equals(false),
            ))
            .getSingleOrNull();

    // Previous closing (the latest day before this one) → opening cash.
    final prev =
        await (_db.select(_db.cashClosings)
              ..where(
                (t) =>
                    t.isDeleted.equals(false) &
                    t.day.isSmallerThanValue(key) &
                    t.branchId.equals(branchId ?? ''),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.day)])
              ..limit(1))
            .getSingleOrNull();

    return CashDay(
      day: start,
      suggestedFloat: prev == null ? 0 : prev.counted - prev.takenOut,
      cashIn: cashIn,
      cashOut: cashOut,
      cashPayments: cashCount,
      otherMethods: other,
      closing: closing,
    );
  }

  /// Saves (or re-saves) the closing for [cashDay].
  Future<void> close({
    required CashDay cashDay,
    required String? branchId,
    required int openingFloat,
    required int counted,
    required int takenOut,
    required String note,
    required String by,
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    final key = dayKey(cashDay.day);
    final now = DateTime.now();
    await _upsertClosing(
      CashClosingsCompanion.insert(
        uuid: _closingUuid(clinicId, branchId, key),
        clinicId: clinicId,
        branchId: Value(branchId ?? ''),
        day: key,
        openingFloat: Value(openingFloat),
        cashIn: Value(cashDay.cashIn),
        cashOut: Value(cashDay.cashOut),
        expected: Value(cashDay.expectedWith(openingFloat)),
        counted: Value(counted),
        takenOut: Value(takenOut),
        note: Value(note.trim()),
        closedByName: Value(by),
        closedAt: Value(now),
        isDeleted: const Value(false),
        updatedAt: Value(now),
      ),
    );
  }

  /// Insert-or-update by uuid. `insertOnConflictUpdate` alone keys on the
  /// primary key (id), so do it explicitly.
  Future<void> _upsertClosing(CashClosingsCompanion c) async {
    final existing = await (_db.select(
      _db.cashClosings,
    )..where((t) => t.uuid.equals(c.uuid.value))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.cashClosings).insert(c);
    } else {
      await (_db.update(
        _db.cashClosings,
      )..where((t) => t.id.equals(existing.id))).write(c);
    }
  }

  /// Days before [before] (up to [kMissedLookbackDays] back) that had cash
  /// payments or cash expenses but were never closed. Oldest first.
  Future<List<({DateTime day, int cashPayments})>> unclosedDays({
    required DateTime before,
    required String? branchId,
  }) async {
    final end = DateTime(before.year, before.month, before.day);
    final start = end.subtract(const Duration(days: kMissedLookbackDays));

    final pays =
        await (_db.select(_db.invoicePayments)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.paidAt.isBiggerOrEqualValue(start) &
                  t.paidAt.isSmallerThanValue(end) &
                  _branchText(t.branchId, branchId),
            ))
            .get();
    final exps =
        await (_db.select(_db.expenses)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.paidAt.isBiggerOrEqualValue(start) &
                  t.paidAt.isSmallerThanValue(end) &
                  _branchText(t.branchId, branchId),
            ))
            .get();

    final activity = <String, int>{}; // day → cash payments (0 = expenses only)
    for (final p in pays) {
      if (!_isCash(p.method)) continue;
      final k = dayKey(p.paidAt);
      activity[k] = (activity[k] ?? 0) + 1;
    }
    for (final e in exps) {
      if (!_isCash(e.method)) continue;
      activity.putIfAbsent(dayKey(e.paidAt), () => 0);
    }
    if (activity.isEmpty) return const [];

    final closed = {
      for (final c
          in await (_db.select(_db.cashClosings)..where(
                (t) =>
                    t.isDeleted.equals(false) &
                    t.branchId.equals(branchId ?? '') &
                    t.day.isBiggerOrEqualValue(dayKey(start)) &
                    t.day.isSmallerThanValue(dayKey(end)),
              ))
              .get())
        c.day,
    };

    final keys = activity.keys.where((k) => !closed.contains(k)).toList()
      ..sort();
    return [
      for (final k in keys) (day: parseDayKey(k), cashPayments: activity[k]!),
    ];
  }

  Stream<List<CashClosingRow>> watchHistory(String? branchId) =>
      (_db.select(_db.cashClosings)
            ..where(
              (t) =>
                  t.isDeleted.equals(false) & t.branchId.equals(branchId ?? ''),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.day)])
            ..limit(60))
          .watch();

  // ── commission ────────────────────────────────────────────────────────────

  Stream<List<DentistRateRow>> watchRates() => (_db.select(
    _db.dentistRates,
  )..where((t) => t.isDeleted.equals(false))).watch();

  Future<void> setRate(String dentist, double percent) async {
    final clinicId = await _db.currentClinicId() ?? '';
    final name = dentist.trim();
    final now = DateTime.now();
    final uuid = 'rate:$clinicId:${name.toLowerCase()}';
    final c = DentistRatesCompanion.insert(
      uuid: uuid,
      clinicId: clinicId,
      dentistName: name,
      percent: Value(percent.clamp(0, 100).toDouble()),
      isDeleted: const Value(false),
      updatedAt: Value(now),
    );
    final existing = await (_db.select(
      _db.dentistRates,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.dentistRates).insert(c);
    } else {
      await (_db.update(
        _db.dentistRates,
      )..where((t) => t.id.equals(existing.id))).write(c);
    }
  }

  /// Commission is paid on money actually COLLECTED in the month, by the
  /// dentist of the appointment the invoice belongs to.
  ///
  /// Invoices made before the appointment link existed are matched to the
  /// patient's appointment on the same day, when there is exactly one
  /// dentist that day. Anything still unmatched is listed as unassigned, so
  /// no money silently disappears from the sheet.
  Future<CommissionSheet> commission(DateTime month, String? branchId) async {
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1);

    final pays =
        await (_db.select(_db.invoicePayments)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.paidAt.isBiggerOrEqualValue(from) &
                  t.paidAt.isSmallerThanValue(to) &
                  _branchText(t.branchId, branchId),
            ))
            .get();
    final invoices = await (_db.select(
      _db.invoices,
    )..where((t) => t.isDeleted.equals(false))).get();
    final invById = {for (final i in invoices) i.id: i};

    final appts = await (_db.select(
      _db.appointments,
    )..where((t) => t.isDeleted.equals(false))).get();
    final apptById = {for (final a in appts) a.id: a};

    // patientId + day → dentists who saw them that day (not cancelled).
    final dentistsByPatientDay = <String, Set<String>>{};
    for (final a in appts) {
      if (a.status == 'cancelled' || a.status == 'noShow') continue;
      final k = '${a.patientId}|${dayKey(a.startsAt)}';
      (dentistsByPatientDay[k] ??= <String>{}).add(a.dentist.trim());
    }

    final patients = await _db.select(_db.patients).get();
    final nameById = {for (final p in patients) p.id: p.fullName};

    final rates = await (_db.select(
      _db.dentistRates,
    )..where((t) => t.isDeleted.equals(false))).get();
    final rateOf = {
      for (final r in rates) r.dentistName.trim().toLowerCase(): r.percent,
    };

    String dentistFor(InvoiceRow inv) {
      final a = inv.appointmentId == null ? null : apptById[inv.appointmentId];
      if (a != null) return a.dentist.trim();
      final set =
          dentistsByPatientDay['${inv.patientId}|${dayKey(inv.issuedAt)}'];
      if (set != null && set.length == 1) return set.first;
      return '';
    }

    final collected = <String, int>{};
    final display = <String, String>{};
    final lists = <String, List<CommissionPayment>>{};
    for (final p in pays) {
      final inv = invById[p.invoiceId];
      if (inv == null) continue;
      final dentist = dentistFor(inv);
      final key = dentist.toLowerCase();
      display.putIfAbsent(key, () => dentist);
      collected[key] = (collected[key] ?? 0) + p.amount;
      (lists[key] ??= []).add(
        CommissionPayment(
          paidAt: p.paidAt,
          patient: nameById[inv.patientId] ?? '—',
          invoiceNo: inv.invoiceNo,
          amount: p.amount,
        ),
      );
    }

    // Completed visits per dentist in the month (for context).
    final visits = <String, int>{};
    for (final a in appts) {
      if (a.status != 'completed') continue;
      if (a.startsAt.isBefore(from) || !a.startsAt.isBefore(to)) continue;
      if (branchId != null && a.branchId != branchId) continue;
      final key = a.dentist.trim().toLowerCase();
      display.putIfAbsent(key, () => a.dentist.trim());
      visits[key] = (visits[key] ?? 0) + 1;
    }

    // Every dentist with a rate shows up, even with nothing this month.
    for (final r in rates) {
      display.putIfAbsent(
        r.dentistName.trim().toLowerCase(),
        () => r.dentistName.trim(),
      );
    }

    // What was already paid out: payout expenses for this month, matched by
    // their description in the commission category.
    final catUuids = {
      for (final c in await _db.lookups('expense_category'))
        if (c.name.trim().toLowerCase() == kCommissionCategory.toLowerCase())
          c.uuid,
    };
    final paidByKey = <String, int>{};
    if (catUuids.isNotEmpty) {
      final payouts =
          await (_db.select(_db.expenses)..where(
                (t) =>
                    t.isDeleted.equals(false) & t.categoryUuid.isIn(catUuids),
              ))
              .get();
      final byDesc = <String, int>{};
      for (final e in payouts) {
        final k = e.description.trim().toLowerCase();
        byDesc[k] = (byDesc[k] ?? 0) + e.amount;
      }
      for (final key in display.keys) {
        if (key.isEmpty) continue;
        final desc = commissionDescription(display[key]!, from).toLowerCase();
        paidByKey[key] = byDesc[desc] ?? 0;
      }
    }

    final lines =
        [
          for (final key in display.keys)
            CommissionLine(
              dentist: display[key]!,
              collected: collected[key] ?? 0,
              percent: key.isEmpty ? 0 : (rateOf[key] ?? 0),
              visits: visits[key] ?? 0,
              paid: paidByKey[key] ?? 0,
              payments: (lists[key] ?? [])
                ..sort((a, b) => b.paidAt.compareTo(a.paidAt)),
            ),
        ]..sort((a, b) {
          if (a.unassigned != b.unassigned) return a.unassigned ? 1 : -1;
          return b.collected.compareTo(a.collected);
        });

    return CommissionSheet(month: from, lines: lines);
  }
}

extension CommissionPayout on CashRepository {
  /// Records a commission payout as an expense in "Dentist commission", so
  /// net profit stays right and the month shows as paid everywhere.
  Future<void> payCommission({
    required String dentist,
    required DateTime month,
    required int amount,
    required String method,
    required String? branchId,
    required String by,
  }) async {
    final db = _db;
    final clinicId = await db.currentClinicId() ?? '';
    final category = await _ensureCommissionCategory(db, clinicId);
    final monthStart = DateTime(month.year, month.month);
    final key =
        '${dayKey(monthStart).substring(0, 7)}|${dentist.trim().toLowerCase()}';
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId,
            branchId: Value(branchId ?? ''),
            categoryUuid: Value(category),
            amount: amount,
            paidAt: DateTime.now(),
            description: Value(commissionDescription(dentist, monthStart)),
            vendor: Value(dentist.trim()),
            method: Value(method),
            recordedByName: Value(by),
            sourceType: const Value('commission'),
            sourceUuid: Value(key),
          ),
        );
  }

  /// The "Dentist commission" category, created once if it doesn't exist.
  /// The uuid is built from the clinic, so two computers creating it at the
  /// same time make the same row instead of a duplicate.
  Future<String> _ensureCommissionCategory(
    AppDatabase db,
    String clinicId,
  ) async {
    for (final c in await db.lookups('expense_category')) {
      if (c.name.trim().toLowerCase() == kCommissionCategory.toLowerCase()) {
        return c.uuid;
      }
    }
    final uuid = 'seed:$clinicId:expense_category:$kCommissionCategory';
    final count = (await db.lookups('expense_category')).length;
    await db
        .into(db.lookupLists)
        .insert(
          LookupListsCompanion.insert(
            uuid: uuid,
            clinicId: clinicId,
            kind: 'expense_category',
            name: kCommissionCategory,
            sortOrder: Value(count),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return uuid;
  }

  /// Payment method names from Settings, for the payout dialog.
  Future<List<String>> paymentMethods() async {
    final names = [
      for (final m in await _db.lookups('payment_method')) m.name.trim(),
    ].where((n) => n.isNotEmpty).toList();
    return names.isEmpty ? const ['Cash', 'Bank transfer'] : names;
  }
}

final cashRepositoryProvider = Provider(
  (ref) => CashRepository(ref.watch(appDatabaseProvider)),
);

final cashDayProvider = FutureProvider.autoDispose.family<CashDay, String>((
  ref,
  key,
) {
  // Re-run when the history changes (a closing saved on this or another PC).
  ref.watch(cashHistoryProvider);
  return ref
      .watch(cashRepositoryProvider)
      .loadDay(parseDayKey(key), ref.watch(activeBranchProvider));
});

/// Unclosed days before the day [key] ('yyyy-mm-dd'). Refreshes when any
/// closing is saved.
final unclosedDaysProvider = FutureProvider.autoDispose
    .family<List<({DateTime day, int cashPayments})>, String>((ref, key) {
      ref.watch(cashHistoryProvider);
      return ref
          .watch(cashRepositoryProvider)
          .unclosedDays(
            before: parseDayKey(key),
            branchId: ref.watch(activeBranchProvider),
          );
    });

final cashHistoryProvider = StreamProvider.autoDispose<List<CashClosingRow>>(
  (ref) => ref
      .watch(cashRepositoryProvider)
      .watchHistory(ref.watch(activeBranchProvider)),
);

final dentistRatesProvider = StreamProvider.autoDispose<List<DentistRateRow>>(
  (ref) => ref.watch(cashRepositoryProvider).watchRates(),
);

/// Key = first day of the month.
final commissionProvider = FutureProvider.autoDispose
    .family<CommissionSheet, DateTime>((ref, month) {
      ref.watch(dentistRatesProvider); // recompute when a rate changes
      return ref
          .watch(cashRepositoryProvider)
          .commission(month, ref.watch(activeBranchProvider));
    });
