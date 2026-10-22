import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/cash/data/cash_repository.dart';

import 'hub_forecast.dart';
import 'hub_watch.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  What the Detailed Reporting Hub shows. Everything is read from the local
//  database (so it works offline); only the WhatsApp queue is asked of the
//  cloud, and that check is allowed to fail quietly.
// ═══════════════════════════════════════════════════════════════════════════

int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

const _mo = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

enum HubPreset {
  today('Today'),
  thisWeek('This week'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last90('Last 90 days'),
  thisYear('This year'),
  custom('Custom range');

  const HubPreset(this.label);
  final String label;
}

/// The stretch of time Money, Dentists, Watch list and Branches look at,
/// and the stretch it is compared with. [end] and [prevEnd] are exclusive.
class HubPeriod {
  const HubPeriod._(
    this.preset,
    this.start,
    this.end,
    this.prevStart,
    this.prevEnd,
  );

  final HubPreset preset;
  final DateTime start, end, prevStart, prevEnd;

  /// Longest custom range — dentist commission is worked out month by month.
  static const maxCustomDays = 731;

  factory HubPeriod.of(HubPreset p, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final d0 = DateTime(n.year, n.month, n.day);
    final d1 = d0.add(const Duration(days: 1));
    switch (p) {
      case HubPreset.today:
        // compared with the same weekday last week (a whole day each)
        return HubPeriod._(
          p,
          d0,
          d1,
          d0.subtract(const Duration(days: 7)),
          d1.subtract(const Duration(days: 7)),
        );
      case HubPreset.thisWeek:
        final mon = d0.subtract(Duration(days: d0.weekday - 1));
        return HubPeriod._(
          p,
          mon,
          d1,
          mon.subtract(const Duration(days: 7)),
          d1.subtract(const Duration(days: 7)),
        );
      case HubPreset.thisMonth:
        final start = DateTime(n.year, n.month, 1);
        final prevStart = DateTime(n.year, n.month - 1, 1);
        final day = math.min(n.day, _daysIn(prevStart.year, prevStart.month));
        return HubPeriod._(
          p,
          start,
          d1,
          prevStart,
          DateTime(prevStart.year, prevStart.month, day + 1),
        );
      case HubPreset.lastMonth:
        final start = DateTime(n.year, n.month - 1, 1);
        return HubPeriod._(
          p,
          start,
          DateTime(n.year, n.month, 1),
          DateTime(start.year, start.month - 1, 1),
          start,
        );
      case HubPreset.last90:
        final start = d1.subtract(const Duration(days: 90));
        return HubPeriod._(
          p,
          start,
          d1,
          start.subtract(const Duration(days: 90)),
          start,
        );
      case HubPreset.thisYear:
        final start = DateTime(n.year, 1, 1);
        final prevStart = DateTime(n.year - 1, 1, 1);
        return HubPeriod._(
          p,
          start,
          d1,
          prevStart,
          DateTime(
            n.year - 1,
            n.month,
            math.min(n.day, _daysIn(n.year - 1, n.month)) + 1,
          ),
        );
      case HubPreset.custom:
        return HubPeriod.range(d0, d0);
    }
  }

  /// A custom range, both days included.
  factory HubPeriod.range(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    final len = b.difference(a);
    return HubPeriod._(HubPreset.custom, a, b, a.subtract(len), a);
  }

  static const presets = [
    HubPreset.today,
    HubPreset.thisWeek,
    HubPreset.thisMonth,
    HubPreset.lastMonth,
    HubPreset.last90,
    HubPreset.thisYear,
  ];

  int get days => end.difference(start).inDays;

  /// The calendar month this period sits in, when it is one month (or the
  /// part of this month so far). Commission payouts are monthly.
  DateTime? get month {
    final whole =
        start.day == 1 && end == DateTime(start.year, start.month + 1, 1);
    return preset == HubPreset.thisMonth ||
            preset == HubPreset.lastMonth ||
            whole
        ? DateTime(start.year, start.month, 1)
        : null;
  }

  static String _d(DateTime d, {bool year = true}) =>
      '${d.day} ${_mo[d.month - 1]}${year ? ' ${d.year}' : ''}';

  /// "1 Oct – 22 Oct 2026", "Thu 22 Oct 2026".
  String get describe {
    final last = end.subtract(const Duration(days: 1));
    if (days <= 1) return _d(start);
    final sameYear = start.year == last.year;
    return '${_d(start, year: !sameYear)} – ${_d(last)}';
  }

  /// The chip text: the preset's name, or the dates for a custom range.
  String get label => preset == HubPreset.custom ? describe : preset.label;

  /// "vs …" words for the change pills.
  String get vs => switch (preset) {
    HubPreset.today => 'same day last week',
    HubPreset.thisWeek => 'same days last week',
    HubPreset.thisMonth => 'same days last month',
    HubPreset.lastMonth => 'the month before',
    HubPreset.last90 => 'the 90 days before',
    HubPreset.thisYear => 'same days last year',
    HubPreset.custom => 'the $days days before',
  };

  @override
  bool operator ==(Object o) =>
      o is HubPeriod && o.preset == preset && o.start == start && o.end == end;

  @override
  int get hashCode => Object.hash(preset, start, end);
}

/// How finely the Money chart splits a period.
enum HubBarUnit { hour, day, week, month }

// ─────────────────────────────── models ───────────────────────────────────

class HubAppt {
  const HubAppt({
    required this.id,
    required this.patientId,
    required this.patient,
    required this.dentist,
    required this.procedure,
    required this.status,
    required this.startsAt,
    required this.minutes,
    required this.billed,
  });

  final int id, patientId, minutes;
  final String patient, dentist, procedure, status;
  final DateTime startsAt;
  final bool billed;

  DateTime get endsAt => startsAt.add(Duration(minutes: minutes));
}

enum HubLevel { urgent, today, later }

/// Where an alert's button goes when the owner leaves the Hub.
enum HubGo {
  appointments,
  billing,
  closeDay,
  expenses,
  requests,
  whatsapp,
  settings,

  /// Stays in the Hub — opens the Watch list section.
  watchList,
}

class HubAlert {
  const HubAlert({
    required this.level,
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.go,
    this.arg,
  });

  final HubLevel level;

  /// cash · wa · sync · licence · request · wait · bill · noshow · owed · payout
  final String icon;
  final String title, detail, action;
  final HubGo go;

  /// Extra target, e.g. the day key for [HubGo.closeDay].
  final String? arg;
}

class HubOwing {
  const HubOwing({
    required this.patientId,
    required this.patient,
    required this.code,
    required this.amount,
    required this.oldestDays,
    required this.invoices,
  });

  final int patientId, amount, oldestDays, invoices;
  final String patient, code;
}

class HubToday {
  const HubToday({
    required this.appts,
    required this.collected,
    required this.collectedCash,
    required this.lastWeekSameTime,
    required this.monthCollected,
    required this.lastMonthToDate,
    required this.monthExpenses,
    required this.owedTotal,
    required this.owedCount,
    required this.owedOver60,
    required this.pendingRequests,
    required this.dayStart,
    required this.dayEnd,
  });

  final List<HubAppt> appts;
  final int collected, collectedCash, lastWeekSameTime;
  final int monthCollected, lastMonthToDate, monthExpenses;
  final int owedTotal, owedCount, owedOver60;
  final int pendingRequests;

  /// Timeline window, minutes after midnight (whole hours).
  final int dayStart, dayEnd;

  int count(String status) => appts.where((a) => a.status == status).length;
  int get patients => {
    for (final a in appts)
      if (a.status != 'cancelled') a.patientId,
  }.length;
  int get monthNet => monthCollected - monthExpenses;
}

class HubMoney {
  const HubMoney({
    required this.collected,
    required this.prevCollected,
    required this.expenses,
    required this.prevExpenses,
    required this.billed,
    required this.billedCount,
    required this.bars,
    required this.unit,
    required this.byCategory,
    required this.byMethod,
    required this.owedBuckets,
    required this.owedBucketCounts,
    required this.topOwing,
  });

  final int collected, prevCollected, expenses, prevExpenses;
  final int billed, billedCount;

  /// Collected per hour / day / week / month across the period ([unit]).
  /// [future] bars are still to come (this week, month or year).
  final List<({DateTime start, int amount, bool future})> bars;
  final HubBarUnit unit;
  final List<({String name, int total})> byCategory, byMethod;

  /// Owed money by age: 0–30, 31–60, 61–90, 90+ days.
  final List<int> owedBuckets, owedBucketCounts;
  final List<HubOwing> topOwing;

  int get net => collected - expenses;
  int get prevNet => prevCollected - prevExpenses;
}

class HubDentist {
  const HubDentist({
    required this.name,
    required this.booked,
    required this.completed,
    required this.noShows,
    required this.cancelled,
    required this.collected,
    required this.percent,
    required this.commission,
    required this.paid,
    this.paidKnown = true,
  });

  final String name;
  final int booked, completed, noShows, cancelled;
  final int collected, commission, paid;
  final double percent;

  /// Payouts are monthly: what is still to pay is only known when the
  /// period is one calendar month.
  final bool paidKnown;

  int get due => paidKnown ? commission - paid : 0;
  int get avgBill => completed == 0 ? 0 : (collected / completed).round();

  /// No-shows as a share of visits that were due to happen.
  double get noShowRate {
    final due = completed + noShows;
    return due == 0 ? 0 : noShows / due;
  }
}

class HubBranch {
  const HubBranch({
    required this.uuid,
    required this.name,
    required this.collected,
    required this.expenses,
    required this.appts,
    required this.completed,
    required this.noShows,
    required this.owed,
    required this.lastClosed,
    required this.waOn,
    required this.waConnected,
  });

  final String uuid, name;
  final int collected, expenses, appts, completed, noShows, owed;

  /// Last cash-closing day as yyyy-mm-dd, null when never closed.
  final String? lastClosed;
  final bool waOn, waConnected;

  int get net => collected - expenses;
}

class HubDevice {
  const HubDevice({
    required this.letter,
    required this.name,
    required this.platform,
    required this.lastSeen,
    required this.isThis,
  });

  final String letter, name, platform;
  final DateTime? lastSeen;
  final bool isThis;
}

class HubWa {
  const HubWa({
    required this.branch,
    required this.on,
    required this.connected,
    required this.failed,
    required this.waiting,
  });

  final String branch;
  final bool on, connected;

  /// From the cloud queue, last 7 days. Null when it couldn't be checked.
  final int? failed, waiting;
}

class HubHealth {
  const HubHealth({
    required this.devices,
    required this.lastSyncHere,
    required this.skipped,
    required this.wa,
    required this.waChecked,
    required this.cloud,
    required this.plan,
    required this.expiresAt,
    required this.users,
    required this.maxUsers,
    required this.branches,
    required this.maxBranches,
  });

  final List<HubDevice> devices;
  final DateTime? lastSyncHere;
  final int skipped;
  final List<HubWa> wa;
  final bool waChecked, cloud;
  final String plan;
  final DateTime? expiresAt;
  final int users, maxUsers, branches, maxBranches;

  int? get licenceDaysLeft => expiresAt == null
      ? null
      : expiresAt!.difference(DateTime.now()).inHours ~/ 24;

  /// Things on this page that need doing.
  int get issues {
    var n = 0;
    final now = DateTime.now();
    for (final d in devices) {
      if (!d.isThis &&
          (d.lastSeen == null || now.difference(d.lastSeen!).inDays >= 3)) {
        n++;
      }
    }
    if (cloud &&
        (lastSyncHere == null || now.difference(lastSyncHere!).inHours >= 24)) {
      n++;
    }
    if (skipped > 0) n++;
    for (final w in wa) {
      if (w.on && !w.connected) n++;
      if ((w.failed ?? 0) > 0) n++;
    }
    final left = licenceDaysLeft;
    if (left != null && left <= 14) n++;
    return n;
  }
}

class HubData {
  const HubData({
    required this.loadedAt,
    required this.today,
    required this.money,
    required this.dentists,
    required this.unassigned,
    required this.commissionDue,
    required this.branches,
    required this.health,
    required this.alerts,
    required this.forecast,
    required this.watch,
  });

  final DateTime loadedAt;
  final HubForecast forecast;

  /// For the chosen period.
  final HubWatch watch;
  final HubToday today;
  final HubMoney money;
  final List<HubDentist> dentists;

  /// Collected in the period that couldn't be linked to any dentist.
  final int unassigned;
  final int commissionDue;

  /// Side by side — empty for a single branch or a branch-scoped view.
  final List<HubBranch> branches;
  final HubHealth health;
  final List<HubAlert> alerts;

  int get urgent => alerts.where((a) => a.level == HubLevel.urgent).length;
}

// ─────────────────────────────── loader ───────────────────────────────────

/// The loading screen's checklist, in the order [loadHubData] works.
const hubLoadSteps = [
  "Reading today's appointments",
  'Adding up money in and out',
  'Working out each dentist',
  'Looking ahead from your history',
  'Checking the watch list',
  'Comparing branches',
  'Checking computers, WhatsApp and licence',
];

/// Loads everything the Hub shows for [branchId] (null = all branches).
/// [onStep] is called with the index of the step about to start.
Future<HubData> loadHubData({
  required AppDatabase db,
  required CashRepository cash,
  required List<Branch> allBranches,
  required License? licence,
  required Entitlements ent,
  required String? branchId,
  required HubPeriod period,
  required bool showPayouts,
  void Function(int step)? onStep,
}) async {
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  final d1 = d0.add(const Duration(days: 1));
  final monthStart = DateTime(now.year, now.month, 1);
  final r = period;

  Expression<bool> inBranch(GeneratedColumn<String> c) =>
      branchId == null ? const Constant(true) : c.equals(branchId);

  final branches = branchId == null
      ? allBranches
      : allBranches.where((b) => b.uuid == branchId).toList();

  Future<List<InvoicePaymentRow>> payments(DateTime a, DateTime b) =>
      (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(a) &
                t.paidAt.isSmallerThanValue(b) &
                inBranch(t.branchId),
          ))
          .get();

  Future<List<ExpenseRow>> expenses(DateTime a, DateTime b) =>
      (db.select(db.expenses)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(a) &
                t.paidAt.isSmallerThanValue(b) &
                inBranch(t.branchId),
          ))
          .get();

  int sumPay(Iterable<InvoicePaymentRow> l) =>
      l.fold(0, (s, p) => s + p.amount);
  int sumExp(Iterable<ExpenseRow> l) => l.fold(0, (s, e) => s + e.amount);
  bool isCash(String m) => m.trim().toLowerCase() == 'cash';

  // ── 1. today ────────────────────────────────────────────────────────────
  onStep?.call(0);
  final apptRows =
      await (db.select(db.appointments).join([
              innerJoin(
                db.patients,
                db.patients.id.equalsExp(db.appointments.patientId),
              ),
            ])
            ..where(
              db.appointments.isDeleted.equals(false) &
                  db.appointments.startsAt.isBiggerOrEqualValue(d0) &
                  db.appointments.startsAt.isSmallerThanValue(d1) &
                  inBranch(db.appointments.branchId),
            )
            ..orderBy([OrderingTerm.asc(db.appointments.startsAt)]))
          .get();
  final appts = [
    for (final row in apptRows)
      () {
        final a = row.readTable(db.appointments);
        final p = row.readTable(db.patients);
        return HubAppt(
          id: a.id,
          patientId: a.patientId,
          patient: p.fullName,
          dentist: a.dentist.trim(),
          procedure: a.procedure,
          status: a.status,
          startsAt: a.startsAt,
          minutes: a.durationMin <= 0 ? 30 : a.durationMin,
          billed: a.billed,
        );
      }(),
  ];

  final todayPays = await payments(d0, d1);
  final lastWeekPays = await payments(
    d0.subtract(const Duration(days: 7)),
    now.subtract(const Duration(days: 7)),
  );
  final mtdPays = await payments(monthStart, d1);
  final lmStart = DateTime(now.year, now.month - 1, 1);
  final lmDay = math.min(now.day, _daysIn(lmStart.year, lmStart.month));
  final lmPays = await payments(
    lmStart,
    DateTime(lmStart.year, lmStart.month, lmDay + 1),
  );
  final mtdExp = await expenses(monthStart, d1);

  // Everything still owed, whatever the period — age matters, not the month.
  final owedRows =
      await (db.select(db.invoices).join([
            innerJoin(
              db.patients,
              db.patients.id.equalsExp(db.invoices.patientId),
            ),
          ])..where(
            db.invoices.isDeleted.equals(false) &
                db.invoices.status.equals('cancelled').not() &
                db.invoices.total.isBiggerThan(db.invoices.amountPaid) &
                inBranch(db.invoices.branchId),
          ))
          .get();
  final owed = [
    for (final row in owedRows)
      () {
        final i = row.readTable(db.invoices);
        final p = row.readTable(db.patients);
        return (
          patientId: p.id,
          patient: p.fullName,
          code: p.code,
          branch: i.branchId ?? '',
          due: i.total - i.amountPaid,
          days: d0
              .difference(
                DateTime(i.issuedAt.year, i.issuedAt.month, i.issuedAt.day),
              )
              .inDays,
        );
      }(),
  ];
  final owedTotal = owed.fold<int>(0, (s, o) => s + o.due);
  final owedOver60 = owed
      .where((o) => o.days > 60)
      .fold<int>(0, (s, o) => s + o.due);

  final reqCount = countAll();
  final pendingRequests =
      (await (db.selectOnly(db.bookingRequests)
                ..addColumns([reqCount])
                ..where(
                  db.bookingRequests.status.equals('pending') &
                      inBranch(db.bookingRequests.branchId),
                ))
              .getSingle())
          .read(reqCount) ??
      0;

  // timeline window — branch hours, widened to fit every visit
  var open = branches.isEmpty
      ? 9 * 60
      : branches.map((b) => b.openMinutes).reduce(math.min);
  var close = branches.isEmpty
      ? 21 * 60
      : branches.map((b) => b.closeMinutes).reduce(math.max);
  for (final a in appts) {
    final s = a.startsAt.hour * 60 + a.startsAt.minute;
    open = math.min(open, s);
    close = math.max(close, s + a.minutes);
  }
  open = (open ~/ 60) * 60;
  close = math.min(24 * 60, ((close + 59) ~/ 60) * 60);
  if (close - open < 4 * 60) close = math.min(24 * 60, open + 4 * 60);

  final today = HubToday(
    appts: appts,
    collected: sumPay(todayPays),
    collectedCash: sumPay(todayPays.where((p) => isCash(p.method))),
    lastWeekSameTime: sumPay(lastWeekPays),
    monthCollected: sumPay(mtdPays),
    lastMonthToDate: sumPay(lmPays),
    monthExpenses: sumExp(mtdExp),
    owedTotal: owedTotal,
    owedCount: owed.length,
    owedOver60: owedOver60,
    pendingRequests: pendingRequests,
    dayStart: open,
    dayEnd: close,
  );

  // ── 2. money for the period ─────────────────────────────────────────────
  onStep?.call(1);
  final pays = await payments(r.start, r.end);
  final prevPays = await payments(r.prevStart, r.prevEnd);
  final exps = await expenses(r.start, r.end);
  final prevExps = await expenses(r.prevStart, r.prevEnd);

  final billedRows =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                t.issuedAt.isBiggerOrEqualValue(r.start) &
                t.issuedAt.isSmallerThanValue(r.end) &
                inBranch(t.branchId),
          ))
          .get();

  // Chart buckets. A running week / month / year is drawn to its end so
  // the days still to come show as empty bars.
  final span = r.end.difference(r.start).inDays;
  final unit = span <= 1
      ? HubBarUnit.hour
      : span <= 62
      ? HubBarUnit.day
      : span <= 190
      ? HubBarUnit.week
      : HubBarUnit.month;
  final barEnd = switch (r.preset) {
    HubPreset.thisWeek => r.start.add(const Duration(days: 7)),
    HubPreset.thisMonth => DateTime(r.start.year, r.start.month + 1, 1),
    HubPreset.thisYear => DateTime(r.start.year + 1, 1, 1),
    _ => r.end,
  };
  DateTime next(DateTime t) => switch (unit) {
    HubBarUnit.hour => t.add(const Duration(hours: 1)),
    HubBarUnit.day => DateTime(t.year, t.month, t.day + 1),
    HubBarUnit.week => DateTime(t.year, t.month, t.day + 7),
    HubBarUnit.month => DateTime(t.year, t.month + 1, 1),
  };
  final firstBar = unit == HubBarUnit.month
      ? DateTime(r.start.year, r.start.month, 1)
      : r.start;
  final starts = <DateTime>[];
  for (var t = firstBar; t.isBefore(barEnd); t = next(t)) {
    starts.add(t);
  }
  final amounts = List<int>.filled(starts.length, 0);
  for (final p in pays) {
    // last bar that starts at or before the payment
    var lo = 0, hi = starts.length - 1, at = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (!starts[mid].isAfter(p.paidAt)) {
        at = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (at >= 0) amounts[at] += p.amount;
  }
  final bars = [
    for (var i = 0; i < starts.length; i++)
      (
        start: starts[i],
        amount: amounts[i],
        future: unit == HubBarUnit.hour
            ? starts[i].isAfter(now)
            : !starts[i].isBefore(d1),
      ),
  ];

  final catNames = {
    for (final l in await db.lookups('expense_category')) l.uuid: l.name,
  };
  final byCat = <String, int>{};
  for (final e in exps) {
    final n = catNames[e.categoryUuid] ?? 'Other';
    byCat[n] = (byCat[n] ?? 0) + e.amount;
  }
  final byMethod = <String, int>{};
  for (final p in pays) {
    final m = p.method.trim().isEmpty ? 'Cash' : p.method.trim();
    byMethod[m] = (byMethod[m] ?? 0) + p.amount;
  }
  List<({String name, int total})> sorted(Map<String, int> m) =>
      [for (final e in m.entries) (name: e.key, total: e.value)]
        ..sort((a, b) => b.total.compareTo(a.total));

  final buckets = List<int>.filled(4, 0), bucketCounts = List<int>.filled(4, 0);
  final byPatient = <int, HubOwing>{};
  for (final o in owed) {
    final b = o.days <= 30
        ? 0
        : o.days <= 60
        ? 1
        : o.days <= 90
        ? 2
        : 3;
    buckets[b] += o.due;
    bucketCounts[b]++;
    final prev = byPatient[o.patientId];
    byPatient[o.patientId] = HubOwing(
      patientId: o.patientId,
      patient: o.patient,
      code: o.code,
      amount: (prev?.amount ?? 0) + o.due,
      oldestDays: math.max(prev?.oldestDays ?? 0, o.days),
      invoices: (prev?.invoices ?? 0) + 1,
    );
  }
  final topOwing = byPatient.values.toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  final money = HubMoney(
    collected: sumPay(pays),
    prevCollected: sumPay(prevPays),
    expenses: sumExp(exps),
    prevExpenses: sumExp(prevExps),
    billed: billedRows.fold(0, (s, i) => s + i.total),
    billedCount: billedRows.length,
    bars: bars,
    unit: unit,
    byCategory: sorted(byCat),
    byMethod: sorted(byMethod),
    owedBuckets: buckets,
    owedBucketCounts: bucketCounts,
    topOwing: topOwing.take(6).toList(),
  );

  // ── 3. dentists ─────────────────────────────────────────────────────────
  onStep?.call(2);
  final periodAppts =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.startsAt.isBiggerOrEqualValue(r.start) &
                t.startsAt.isSmallerThanValue(r.end) &
                inBranch(t.branchId),
          ))
          .get();
  // Commission is worked out per calendar month; a longer or shorter
  // period adds up the payments that fall inside it, month by month.
  final oneMonth = r.month;
  final sheets = <CommissionSheet>[];
  for (
    var m = DateTime(r.start.year, r.start.month, 1);
    m.isBefore(r.end);
    m = DateTime(m.year, m.month + 1, 1)
  ) {
    sheets.add(await cash.commission(m, branchId));
  }
  bool inRange(DateTime t) => !t.isBefore(r.start) && t.isBefore(r.end);
  final merged =
      <String, ({String name, int collected, double percent, int paid})>{};
  var unassigned = 0;
  for (final sh in sheets) {
    for (final l in sh.lines) {
      final got = l.payments
          .where((x) => inRange(x.paidAt))
          .fold<int>(0, (s, x) => s + x.amount);
      if (l.unassigned) {
        unassigned += got;
        continue;
      }
      final k = dentistKey(l.dentist);
      final prev = merged[k];
      merged[k] = (
        name: prev?.name ?? l.dentist,
        collected: (prev?.collected ?? 0) + got,
        percent: l.percent,
        paid: (prev?.paid ?? 0) + l.paid,
      );
    }
  }

  final visitStats =
      <String, ({String name, int booked, int done, int noShow, int cancel})>{};
  for (final a in periodAppts) {
    final name = a.dentist.trim();
    if (name.isEmpty) continue;
    final k = dentistKey(name);
    final s =
        visitStats[k] ?? (name: name, booked: 0, done: 0, noShow: 0, cancel: 0);
    visitStats[k] = (
      name: s.name,
      booked: s.booked + 1,
      done: s.done + (a.status == 'completed' ? 1 : 0),
      noShow: s.noShow + (a.status == 'noShow' ? 1 : 0),
      cancel: s.cancel + (a.status == 'cancelled' ? 1 : 0),
    );
  }
  final dentistMap = <String, HubDentist>{};
  for (final e in merged.entries) {
    final l = e.value;
    final v = visitStats.remove(e.key);
    if (l.collected == 0 && v == null) continue;
    dentistMap[e.key] = HubDentist(
      name: l.name,
      booked: v?.booked ?? 0,
      completed: v?.done ?? 0,
      noShows: v?.noShow ?? 0,
      cancelled: v?.cancel ?? 0,
      collected: l.collected,
      percent: l.percent,
      commission: (l.collected * l.percent / 100).round(),
      paid: oneMonth == null ? 0 : l.paid,
      paidKnown: oneMonth != null,
    );
  }
  for (final e in visitStats.entries) {
    dentistMap[e.key] = HubDentist(
      name: e.value.name,
      booked: e.value.booked,
      completed: e.value.done,
      noShows: e.value.noShow,
      cancelled: e.value.cancel,
      collected: 0,
      percent: 0,
      commission: 0,
      paid: 0,
    );
  }
  final dentists = dentistMap.values.toList()
    ..sort((a, b) {
      final c = b.collected.compareTo(a.collected);
      return c != 0 ? c : b.booked.compareTo(a.booked);
    });

  // ── 4. what's coming ────────────────────────────────────────────────────
  onStep?.call(3);
  final forecast = await loadHubForecast(
    db: db,
    branches: branches,
    branchId: branchId,
    owed: [for (final o in owed) (due: o.due, days: o.days)],
  );

  // ── 5. watch list ───────────────────────────────────────────────────────
  onStep?.call(4);
  final watch = await loadHubWatch(
    db: db,
    branches: branches,
    branchId: branchId,
    start: r.start,
    end: r.end,
  );
  final weekAgo = d0.subtract(const Duration(days: 7));
  final failedWeek =
      await (db.select(db.activityEvents)..where(
            (t) =>
                t.kind.equals('sign_in_failed') &
                t.happenedAt.isBiggerOrEqualValue(weekAgo),
          ))
          .get();

  // ── 6. branches side by side ────────────────────────────────────────────
  onStep?.call(5);
  final branchStats = <HubBranch>[];
  if (branchId == null && allBranches.length > 1) {
    for (final b in allBranches) {
      final last =
          await (db.select(db.cashClosings)
                ..where(
                  (t) => t.isDeleted.equals(false) & t.branchId.equals(b.uuid),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.day)])
                ..limit(1))
              .getSingleOrNull();
      final bAppts = periodAppts.where((a) => a.branchId == b.uuid);
      branchStats.add(
        HubBranch(
          uuid: b.uuid,
          name: b.name,
          collected: sumPay(pays.where((p) => p.branchId == b.uuid)),
          expenses: sumExp(exps.where((e) => e.branchId == b.uuid)),
          appts: bAppts.where((a) => a.status != 'cancelled').length,
          completed: bAppts.where((a) => a.status == 'completed').length,
          noShows: bAppts.where((a) => a.status == 'noShow').length,
          owed: owed
              .where((o) => o.branch == b.uuid)
              .fold(0, (s, o) => s + o.due),
          lastClosed: last?.day,
          waOn: b.waEnabled,
          waConnected: b.qrConnected || b.officialConnected,
        ),
      );
    }
  }

  // ── 7. system health ────────────────────────────────────────────────────
  onStep?.call(6);
  final here = await db.localDevice();
  final devices = [
    for (final d in await db.activeDevices())
      HubDevice(
        letter: d.letter,
        name: d.name,
        platform: d.platform,
        lastSeen: d.lastSeenAt,
        isThis: d.uuid == here.uuid,
      ),
  ];
  final skipped =
      int.tryParse(await db.getSetting('sync_skipped_count') ?? '') ?? 0;

  final failed = <String, int>{}, waiting = <String, int>{};
  var waChecked = false;
  if (ent.cloud && branches.any((b) => b.waEnabled)) {
    try {
      var q = Supabase.instance.client
          .from('wa_outbox')
          .select('status, branch_id')
          .gte(
            'created_at',
            now.subtract(const Duration(days: 7)).toUtc().toIso8601String(),
          )
          .neq('status', 'sent');
      if (branchId != null) q = q.eq('branch_id', branchId);
      final rows = await q.limit(1000).timeout(const Duration(seconds: 6));
      for (final row in rows) {
        final b = '${row['branch_id'] ?? ''}';
        final s = '${row['status'] ?? ''}';
        if (s == 'failed') failed[b] = (failed[b] ?? 0) + 1;
        if (s == 'pending' || s == 'sending') {
          waiting[b] = (waiting[b] ?? 0) + 1;
        }
      }
      waChecked = true;
    } catch (_) {
      // offline or the cloud is slow — the page says it couldn't check
    }
  }
  final wa = [
    for (final b in branches)
      HubWa(
        branch: b.name,
        on: b.waEnabled,
        connected: b.qrConnected || b.officialConnected,
        failed: waChecked ? (failed[b.uuid] ?? 0) : null,
        waiting: waChecked ? (waiting[b.uuid] ?? 0) : null,
      ),
  ];

  final health = HubHealth(
    devices: devices,
    lastSyncHere: await db.lastSyncAt(),
    skipped: skipped,
    wa: wa,
    waChecked: waChecked,
    cloud: ent.cloud,
    plan: ent.tierLabel,
    expiresAt: licence?.expiresAt,
    users: await db.userCount(),
    maxUsers: ent.maxUsers,
    branches: allBranches.length,
    maxBranches: ent.maxBranches,
  );

  final unclosed = await cash.unclosedDays(before: d0, branchId: branchId);

  return HubData(
    loadedAt: DateTime.now(),
    today: today,
    money: money,
    dentists: dentists,
    unassigned: unassigned,
    commissionDue: dentists.fold(0, (s, x) => s + (x.due > 0 ? x.due : 0)),
    branches: branchStats,
    health: health,
    forecast: forecast,
    watch: watch,
    alerts: _alerts(
      now: now,
      today: today,
      health: health,
      unclosed: unclosed,
      owed60Count: owed.where((o) => o.days > 60).length,
      commissionDue: showPayouts && period.preset == HubPreset.thisMonth
          ? dentists.fold(0, (s, x) => s + (x.due > 0 ? x.due : 0))
          : 0,
      failedSignIns: failedWeek.length,
    ),
  );
}

String _n(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String _rs(int v) =>
    'Rs ${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

List<HubAlert> _alerts({
  required DateTime now,
  required HubToday today,
  required HubHealth health,
  required List<({DateTime day, int cashPayments})> unclosed,
  required int owed60Count,
  required int commissionDue,
  required int failedSignIns,
}) {
  final out = <HubAlert>[];

  // ── urgent ──
  if (unclosed.isNotEmpty) {
    final first = unclosed.first.day;
    out.add(
      HubAlert(
        level: HubLevel.urgent,
        icon: 'cash',
        title: unclosed.length == 1
            ? 'A day was not closed'
            : '${unclosed.length} days were not closed',
        detail:
            'Cash was taken but never counted · oldest '
            '${first.day}/${first.month}/${first.year}',
        action: 'Close day',
        go: HubGo.closeDay,
        arg: dayKey(first),
      ),
    );
  }
  for (final w in health.wa) {
    if (w.on && !w.connected) {
      out.add(
        HubAlert(
          level: HubLevel.urgent,
          icon: 'wa',
          title: 'WhatsApp is disconnected · ${w.branch}',
          detail: 'Reminders and prescriptions are not going out',
          action: 'Reconnect',
          go: HubGo.whatsapp,
        ),
      );
    }
  }
  final failed = health.wa.fold<int>(0, (s, w) => s + (w.failed ?? 0));
  if (failed > 0) {
    out.add(
      HubAlert(
        level: HubLevel.urgent,
        icon: 'wa',
        title: '${_n(failed, 'WhatsApp message')} failed this week',
        detail: 'Open the message log to retry them',
        action: 'Open WhatsApp',
        go: HubGo.whatsapp,
      ),
    );
  }
  for (final d in health.devices) {
    if (d.isThis) continue;
    final days = d.lastSeen == null ? null : now.difference(d.lastSeen!).inDays;
    if (days == null || days >= 3) {
      out.add(
        HubAlert(
          level: HubLevel.urgent,
          icon: 'sync',
          title:
              'Computer ${d.letter}${d.name.isEmpty ? '' : ' (${d.name})'} '
              'is not syncing',
          detail: days == null
              ? 'It has never synced'
              : 'Last synced ${_n(days, 'day')} ago — its work may be missing',
          action: 'See computers',
          go: HubGo.settings,
        ),
      );
    }
  }
  final left = health.licenceDaysLeft;
  if (left != null && left <= 14) {
    out.add(
      HubAlert(
        level: HubLevel.urgent,
        icon: 'licence',
        title: left <= 0
            ? 'Your licence ends today'
            : 'Your licence ends in ${_n(left, 'day')}',
        detail: 'Contact Inover Studio to renew before it locks',
        action: 'Licence',
        go: HubGo.settings,
      ),
    );
  }

  // ── today ──
  if (failedSignIns >= 3) {
    out.add(
      HubAlert(
        level: HubLevel.today,
        icon: 'lock',
        title: '${_n(failedSignIns, 'failed sign-in')} this week',
        detail: 'Wrong passwords — see who in the Watch list',
        action: 'Watch list',
        go: HubGo.watchList,
      ),
    );
  }
  if (today.pendingRequests > 0) {
    out.add(
      HubAlert(
        level: HubLevel.today,
        icon: 'request',
        title: '${_n(today.pendingRequests, 'booking request')} waiting',
        detail: 'Patients asked for a slot from the app',
        action: 'Review',
        go: HubGo.requests,
      ),
    );
  }
  final longWait = today.appts
      .where(
        (a) =>
            a.status == 'waiting' &&
            now.difference(a.startsAt) > const Duration(minutes: 20),
      )
      .toList();
  if (longWait.isNotEmpty) {
    out.add(
      HubAlert(
        level: HubLevel.today,
        icon: 'wait',
        title: '${_n(longWait.length, 'patient')} waiting over 20 minutes',
        detail: longWait.take(3).map((a) => a.patient).join(', '),
        action: 'Appointments',
        go: HubGo.appointments,
      ),
    );
  }
  final unbilled = today.appts
      .where((a) => a.status == 'completed' && !a.billed)
      .toList();
  if (unbilled.isNotEmpty) {
    out.add(
      HubAlert(
        level: HubLevel.today,
        icon: 'bill',
        title: '${_n(unbilled.length, 'finished visit')} not billed',
        detail: unbilled.take(3).map((a) => a.patient).join(', '),
        action: 'Bill now',
        go: HubGo.appointments,
      ),
    );
  }
  final noShows = today.count('noShow');
  if (noShows > 0) {
    out.add(
      HubAlert(
        level: HubLevel.today,
        icon: 'noshow',
        title: '${_n(noShows, 'no-show')} today',
        detail: 'A quick call today often rebooks them',
        action: 'Appointments',
        go: HubGo.appointments,
      ),
    );
  }

  // ── when you can ──
  if (today.owedOver60 > 0) {
    out.add(
      HubAlert(
        level: HubLevel.later,
        icon: 'owed',
        title: '${_rs(today.owedOver60)} owed for over 60 days',
        detail:
            '${_n(owed60Count, 'invoice')} — older debts get harder to collect',
        action: 'Billing',
        go: HubGo.billing,
      ),
    );
  }
  if (commissionDue > 0) {
    out.add(
      HubAlert(
        level: HubLevel.later,
        icon: 'payout',
        title: '${_rs(commissionDue)} commission due to dentists',
        detail: 'For this month so far',
        action: 'Payouts',
        go: HubGo.expenses,
      ),
    );
  }
  if (health.skipped > 0) {
    out.add(
      HubAlert(
        level: HubLevel.later,
        icon: 'sync',
        title: '${_n(health.skipped, 'record')} did not sync',
        detail: 'They stay on this computer until fixed',
        action: 'Settings',
        go: HubGo.settings,
      ),
    );
  }
  return out;
}
