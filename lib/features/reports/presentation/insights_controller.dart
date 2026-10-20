import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Advanced insights for the Reports screen.
//
//  Everything is worked out from data the clinic already records:
//  appointments, invoices (+ items) and payments. Nothing new to enter.
//
//  A "visit" here is a VISIT EPISODE: visits less than 14 days apart count
//  as one. Three root-canal sessions in ten days are one course of
//  treatment, not a patient "returning" three times. Without this, every
//  multi-session patient would look like a loyal regular, and every
//  patient who just finished treatment would look "overdue".
// ═════════════════════════════════════════════════════════════════════════════

/// Visits closer together than this are one episode.
const kEpisodeGapDays = 14;

/// [from] inclusive, [to] exclusive. Only used for "top services".
typedef InsightsRange = ({DateTime from, DateTime to});

class ServiceEarning {
  const ServiceEarning({
    required this.name,
    required this.amount,
    required this.count,
    required this.share,
  });
  final String name;

  /// Invoiced, after each invoice's discount/adjustment is shared out.
  final int amount;
  final int count;

  /// 0..1 of all service income in the period.
  final double share;
}

class PatientSpend {
  const PatientSpend({
    required this.patientId,
    required this.name,
    required this.paid,
    required this.visits,
    required this.lastVisit,
  });
  final int patientId;
  final String name;
  final int paid;
  final int visits;
  final DateTime? lastVisit;
}

/// One patient inside a "how many visits" group.
class BucketPatient {
  const BucketPatient({
    required this.patientId,
    required this.name,
    required this.phone,
    required this.visits,
    required this.lastVisit,
    required this.paid,
  });
  final int patientId;
  final String name;
  final String phone;
  final int visits;
  final DateTime lastVisit;
  final int paid;
}

/// A "how many visits" group: 1 visit, 2 visits, 3–5, 6+.
typedef VisitBucket = ({String label, int count, List<BucketPatient> patients});

class AtRiskPatient {
  const AtRiskPatient({
    required this.patientId,
    required this.name,
    required this.phone,
    required this.usualGapDays,
    required this.daysSinceLast,
    required this.paid,
  });
  final int patientId;
  final String name;
  final String phone;
  final int usualGapDays;
  final int daysSinceLast;
  final int paid;
}

class RetentionCohort {
  const RetentionCohort({
    required this.month,
    required this.size,
    required this.m1,
    required this.m3,
    required this.m6,
  });

  /// First day of the month these patients first visited.
  final DateTime month;
  final int size;

  /// Share (0..1) who came back within 1 / 3 / 6 months of their first
  /// visit. null = not enough time has passed to know yet.
  final double? m1, m3, m6;
}

class YearForecast {
  const YearForecast({
    required this.year,
    required this.fullMonths,
    required this.monthsUsed,
    required this.ytdCollected,
    required this.forecast,
    required this.low,
    required this.high,
    required this.forecastProfit,
    required this.actual,
    required this.projected,
  });

  final int year;

  /// Complete calendar months of payment history (0 = locked).
  final int fullMonths;

  /// Months that went into the average (up to 3).
  final int monthsUsed;

  final int ytdCollected;
  final int forecast, low, high;

  /// Collected minus expenses for the year. null when the clinic has never
  /// recorded an expense (the number would just equal income).
  final int? forecastProfit;

  /// 12 values, Jan..Dec, in thousands. null for months not reached yet.
  final List<double?> actual;

  /// 12 values, in thousands. null before the current month.
  final List<double?> projected;

  bool get locked => fullMonths < 1;
  bool get reliable => monthsUsed >= 3;
}

class Insights {
  const Insights({
    required this.visitedPatients,
    required this.returningPatients,
    required this.visitBuckets,
    required this.avgVisitsReturning,
    required this.typicalGapDays,
    required this.sixMonthReturn,
    required this.topServices,
    required this.forecast,
    required this.avgLifetimeValue,
    required this.payingPatients,
    required this.topPatients,
    required this.atRisk,
    required this.cohorts,
  });

  final int visitedPatients;
  final int returningPatients;
  final List<VisitBucket> visitBuckets;
  final double avgVisitsReturning;

  /// Median days between visits of returning patients. null = no data.
  final int? typicalGapDays;

  /// Share of patients (first visit 6+ months ago) who came back within
  /// 6 months. null = nobody is old enough yet.
  final double? sixMonthReturn;

  final List<ServiceEarning> topServices;
  final YearForecast forecast;
  final int avgLifetimeValue;
  final int payingPatients;
  final List<PatientSpend> topPatients;
  final List<AtRiskPatient> atRisk;
  final List<RetentionCohort> cohorts;

  double get returnRate =>
      visitedPatients == 0 ? 0 : returningPatients / visitedPatients;
}

// ── small date helpers (UTC calendar days, so DST can never shift a day) ──

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
int _daysBetween(DateTime a, DateTime b) => _day(b).difference(_day(a)).inDays;
int _monthKey(DateTime d) => d.year * 12 + d.month - 1;

int? _median(List<int> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : ((s[m - 1] + s[m]) / 2).round();
}

/// Sorted distinct days → episode start days.
List<DateTime> _episodes(List<DateTime> sortedDays) {
  final out = <DateTime>[];
  DateTime? lastDay;
  for (final d in sortedDays) {
    if (lastDay == null || _daysBetween(lastDay, d) >= kEpisodeGapDays) {
      out.add(d);
    }
    lastDay = d;
  }
  return out;
}

/// Projected year total: what is already in, plus the current month at
/// least at the expected pace, plus [perMonth] for each month left.
int _projectYear({
  required int ytd,
  required int thisMonth,
  required double perMonth,
  required int monthsAfter,
}) =>
    (ytd -
            thisMonth +
            math.max(thisMonth.toDouble(), perMonth) +
            perMonth * monthsAfter)
        .round();

// ═════════════════════════════════════════════════════════════════════════════

Future<Insights> _build(Ref ref, InsightsRange range) async {
  final db = ref.watch(appDatabaseProvider);
  final branchId = ref.watch(activeBranchProvider);
  final now = DateTime.now();
  final today = _day(now);

  final patients =
      await (db.select(db.patients)..where(
            (t) =>
                t.isDeleted.equals(false) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();
  final patientById = {for (final p in patients) p.id: p};

  final appts =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  // All live invoices — cancelled ones are kept here only so a payment on
  // one can still be traced to its patient.
  final allInvoices =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();
  final invoices = allInvoices.where((i) => i.status != 'cancelled').toList();

  final payments =
      await (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  final expenses =
      await (db.select(db.expenses)..where(
            (t) =>
                t.isDeleted.equals(false) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  // ── 1. visit episodes per patient ─────────────────────────────────────────
  // A visit day = a completed appointment or an invoice (some clinics never
  // tick "completed", but they always bill). Future dates are ignored.
  final daysByPatient = <int, Set<DateTime>>{};
  void addVisit(int patientId, DateTime at) {
    if (!patientById.containsKey(patientId)) return;
    if (at.isAfter(now)) return;
    (daysByPatient[patientId] ??= <DateTime>{}).add(_day(at));
  }

  for (final a in appts) {
    if (a.status == 'completed') addVisit(a.patientId, a.startsAt);
  }
  for (final i in invoices) {
    addVisit(i.patientId, i.issuedAt);
  }

  final episodes = <int, List<DateTime>>{
    for (final e in daysByPatient.entries)
      e.key: _episodes(e.value.toList()..sort()),
  };

  // ── 2. returning patients ─────────────────────────────────────────────────
  var returning = 0;
  final ids1 = <int>[], ids2 = <int>[], ids3to5 = <int>[], ids6 = <int>[];
  var returningVisitsSum = 0;
  final allGaps = <int>[];
  var sixEligible = 0, sixBack = 0;

  for (final entry in episodes.entries) {
    final eps = entry.value;
    final n = eps.length;
    if (n == 1) {
      ids1.add(entry.key);
    } else if (n == 2) {
      ids2.add(entry.key);
    } else if (n <= 5) {
      ids3to5.add(entry.key);
    } else {
      ids6.add(entry.key);
    }
    if (n >= 2) {
      returning++;
      returningVisitsSum += n;
      for (var i = 1; i < n; i++) {
        allGaps.add(_daysBetween(eps[i - 1], eps[i]));
      }
    }
    // Back within 6 months — only for patients whose first visit is at
    // least 6 months old, so new patients don't drag the number down.
    if (_daysBetween(eps.first, today) >= 180) {
      sixEligible++;
      if (n >= 2 && _daysBetween(eps[0], eps[1]) <= 180) sixBack++;
    }
  }

  // ── 3. top services (invoices issued in the selected period) ──────────────
  final inRange = <int, InvoiceRow>{
    for (final i in invoices)
      if (!i.issuedAt.isBefore(range.from) && i.issuedAt.isBefore(range.to))
        i.id: i,
  };
  final items = inRange.isEmpty
      ? const <InvoiceItemRow>[]
      : await db.select(db.invoiceItems).get();

  final svcAmount = <String, double>{};
  final svcCount = <String, int>{};
  final svcName = <String, String>{};
  for (final it in items) {
    final inv = inRange[it.invoiceId];
    if (inv == null) continue;
    final name = it.description.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    // Share the invoice's discount/adjustment across its lines, so the
    // ranking reflects money actually charged.
    final factor = inv.subtotal > 0 ? inv.total / inv.subtotal : 1.0;
    svcAmount[key] = (svcAmount[key] ?? 0) + it.amount * factor;
    svcCount[key] = (svcCount[key] ?? 0) + (it.qty < 1 ? 1 : it.qty);
    svcName.putIfAbsent(key, () => name);
  }
  final svcTotal = svcAmount.values.fold<double>(0, (a, b) => a + b);
  final ranked = svcAmount.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topServices = [
    for (final e in ranked.take(3))
      if (e.value > 0)
        ServiceEarning(
          name: svcName[e.key]!,
          amount: e.value.round(),
          count: svcCount[e.key] ?? 0,
          share: svcTotal <= 0 ? 0 : e.value / svcTotal,
        ),
  ];

  // ── 4. year-end forecast ──────────────────────────────────────────────────
  final byMonth = <int, int>{};
  DateTime? firstPayment;
  for (final p in payments) {
    if (p.paidAt.isAfter(now)) continue;
    byMonth[_monthKey(p.paidAt)] =
        (byMonth[_monthKey(p.paidAt)] ?? 0) + p.amount;
    if (firstPayment == null || p.paidAt.isBefore(firstPayment)) {
      firstPayment = p.paidAt;
    }
  }
  final expByMonth = <int, int>{};
  for (final e in expenses) {
    if (e.paidAt.isAfter(now)) continue;
    expByMonth[_monthKey(e.paidAt)] =
        (expByMonth[_monthKey(e.paidAt)] ?? 0) + e.amount;
  }

  final curKey = _monthKey(now);
  final yearStartKey = now.year * 12;
  final monthsAfter = 12 - now.month;

  var fullMonths = 0;
  var usedKeys = <int>[];
  if (firstPayment != null) {
    final firstKey = _monthKey(firstPayment);
    fullMonths = curKey - firstKey; // months completed since data began
    usedKeys = [
      for (var k = curKey - 1; k >= firstKey && k >= curKey - 3; k--) k,
    ];
    // A first month that started after the 7th is partial — it would make
    // the average look too low. Drop it when there's something better.
    if (firstPayment.day > 7 && usedKeys.length > 1) usedKeys.remove(firstKey);
  }

  double weighted(Map<int, int> m) {
    // Latest month counts most: 50% / 30% / 20%.
    const w = [0.5, 0.3, 0.2];
    var sum = 0.0, wSum = 0.0;
    for (var i = 0; i < usedKeys.length; i++) {
      sum += (m[usedKeys[i]] ?? 0) * w[i];
      wSum += w[i];
    }
    return wSum == 0 ? 0 : sum / wSum;
  }

  int ytdOf(Map<int, int> m) {
    var s = 0;
    for (var k = yearStartKey; k <= curKey; k++) {
      s += m[k] ?? 0;
    }
    return s;
  }

  final expected = weighted(byMonth);
  final ytd = ytdOf(byMonth);
  final thisMonth = byMonth[curKey] ?? 0;

  int project(double perMonth) => _projectYear(
    ytd: ytd,
    thisMonth: thisMonth,
    perMonth: perMonth,
    monthsAfter: monthsAfter,
  );

  final forecastTotal = project(expected);
  int low, high;
  if (usedKeys.length >= 3) {
    final vals = [for (final k in usedKeys) (byMonth[k] ?? 0).toDouble()];
    low = project(vals.reduce(math.min));
    high = project(vals.reduce(math.max));
  } else {
    // Too little history to measure month-to-month swings: ±20%.
    low = project(expected * 0.8);
    high = project(expected * 1.2);
  }

  int? forecastProfit;
  if (expenses.isNotEmpty && usedKeys.isNotEmpty) {
    final expExpected = weighted(expByMonth);
    final expYear = _projectYear(
      ytd: ytdOf(expByMonth),
      thisMonth: expByMonth[curKey] ?? 0,
      perMonth: expExpected,
      monthsAfter: monthsAfter,
    );
    forecastProfit = forecastTotal - expYear;
  }

  final actual = List<double?>.filled(12, null);
  final projected = List<double?>.filled(12, null);
  for (var m = 0; m < now.month; m++) {
    actual[m] = (byMonth[yearStartKey + m] ?? 0) / 1000;
  }
  if (usedKeys.isNotEmpty) {
    projected[now.month - 1] = math.max(thisMonth.toDouble(), expected) / 1000;
    for (var m = now.month; m < 12; m++) {
      projected[m] = expected / 1000;
    }
  }

  final forecast = YearForecast(
    year: now.year,
    fullMonths: fullMonths,
    monthsUsed: usedKeys.length,
    ytdCollected: ytd,
    forecast: forecastTotal,
    low: low,
    high: high,
    forecastProfit: forecastProfit,
    actual: actual,
    projected: projected,
  );

  // ── 5. lifetime value ─────────────────────────────────────────────────────
  final patientOfInvoice = {for (final i in allInvoices) i.id: i.patientId};
  final paidByPatient = <int, int>{};
  for (final p in payments) {
    final pid = patientOfInvoice[p.invoiceId];
    if (pid == null || !patientById.containsKey(pid)) continue;
    paidByPatient[pid] = (paidByPatient[pid] ?? 0) + p.amount;
  }
  final paying = paidByPatient.entries.where((e) => e.value > 0).toList();
  final totalPaid = paying.fold<int>(0, (s, e) => s + e.value);
  paying.sort((a, b) => b.value.compareTo(a.value));
  final topPatients = [
    for (final e in paying.take(10))
      PatientSpend(
        patientId: e.key,
        name: patientById[e.key]!.fullName,
        paid: e.value,
        visits: episodes[e.key]?.length ?? 0,
        lastVisit: episodes[e.key]?.last,
      ),
  ];

  // Patients behind each "how many visits" group, most recent first.
  VisitBucket bucket(String label, List<int> ids) {
    final list = [
      for (final id in ids)
        BucketPatient(
          patientId: id,
          name: patientById[id]!.fullName,
          phone: patientById[id]!.phone,
          visits: episodes[id]!.length,
          lastVisit: episodes[id]!.last,
          paid: paidByPatient[id] ?? 0,
        ),
    ]..sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
    return (label: label, count: list.length, patients: list);
  }

  final visitBuckets = [
    bucket('1 visit', ids1),
    bucket('2 visits', ids2),
    bucket('3–5 visits', ids3to5),
    bucket('6+ visits', ids6),
  ];

  // ── 6. at-risk regulars ───────────────────────────────────────────────────
  // Someone with a booking coming up is not at risk.
  final hasUpcoming = <int>{
    for (final a in appts)
      if ((a.status == 'upcoming' ||
              a.status == 'waiting' ||
              a.status == 'inChair') &&
          !_day(a.startsAt).isBefore(today))
        a.patientId,
  };
  final atRisk = <AtRiskPatient>[];
  for (final e in episodes.entries) {
    final eps = e.value;
    if (eps.length < 3) continue; // need a real pattern to judge "late"
    if (hasUpcoming.contains(e.key)) continue;
    final gaps = [
      for (var i = 1; i < eps.length; i++) _daysBetween(eps[i - 1], eps[i]),
    ];
    final usual = _median(gaps)!;
    final since = _daysBetween(eps.last, today);
    // Late = 50% past their usual gap, and at least a month past it.
    final threshold = math.max((usual * 1.5).round(), usual + 30);
    // Gone for 2+ years is lost, not "at risk".
    if (since > threshold && since <= 730) {
      final p = patientById[e.key]!;
      atRisk.add(
        AtRiskPatient(
          patientId: e.key,
          name: p.fullName,
          phone: p.phone,
          usualGapDays: usual,
          daysSinceLast: since,
          paid: paidByPatient[e.key] ?? 0,
        ),
      );
    }
  }
  // Most valuable first — those are the ones worth a call.
  atRisk.sort((a, b) {
    final c = b.paid.compareTo(a.paid);
    return c != 0 ? c : b.daysSinceLast.compareTo(a.daysSinceLast);
  });

  // ── 7. retention by joining month (last 12 months) ────────────────────────
  final cohortPatients = <int, List<List<DateTime>>>{};
  for (final eps in episodes.values) {
    final k = _monthKey(eps.first);
    if (k < curKey - 11) continue;
    (cohortPatients[k] ??= []).add(eps);
  }
  double? share(int key, List<List<DateTime>> group, int windowDays) {
    // Known only once the window has fully passed for everyone in the
    // cohort, i.e. counted from the LAST day of that month.
    final monthEnd = DateTime.utc(key ~/ 12, key % 12 + 2, 0);
    if (_daysBetween(monthEnd, today) < windowDays) return null;
    var back = 0;
    for (final eps in group) {
      if (eps.length >= 2 && _daysBetween(eps[0], eps[1]) <= windowDays) back++;
    }
    return back / group.length;
  }

  final cohortKeys = cohortPatients.keys.toList()..sort((a, b) => b - a);
  final cohorts = [
    for (final k in cohortKeys)
      RetentionCohort(
        month: DateTime(k ~/ 12, k % 12 + 1),
        size: cohortPatients[k]!.length,
        m1: share(k, cohortPatients[k]!, 30),
        m3: share(k, cohortPatients[k]!, 90),
        m6: share(k, cohortPatients[k]!, 180),
      ),
  ];

  return Insights(
    visitedPatients: episodes.length,
    returningPatients: returning,
    visitBuckets: visitBuckets,
    avgVisitsReturning: returning == 0 ? 0 : returningVisitsSum / returning,
    typicalGapDays: _median(allGaps),
    sixMonthReturn: sixEligible == 0 ? null : sixBack / sixEligible,
    topServices: topServices,
    forecast: forecast,
    avgLifetimeValue: paying.isEmpty ? 0 : (totalPaid / paying.length).round(),
    payingPatients: paying.length,
    topPatients: topPatients,
    atRisk: atRisk,
    cohorts: cohorts,
  );
}

final insightsProvider = FutureProvider.autoDispose
    .family<Insights, InsightsRange>((ref, range) => _build(ref, range));
