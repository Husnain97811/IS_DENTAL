import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:is_dental/core/constants/views.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  What's coming — every estimate is worked out from this clinic's own
//  history (no outside numbers), and only once there are 60 days of it.
// ═══════════════════════════════════════════════════════════════════════════

/// Days of a clinic's own data needed before anything is forecast.
///
/// While developing (`flutter run`, debug build) it is 14, so the page can
/// be checked on a test clinic. Clinics always run release builds → 60.
const kForecastMinDays = kDebugMode ? 14 : 60;

class HubDayAhead {
  const HubDayAhead({
    required this.day,
    required this.closed,
    required this.booked,
    required this.usual,
    required this.usualMoney,
  });

  final DateTime day;
  final bool closed;
  final int booked;

  /// Average visits on this weekday over the last 8 weeks.
  final double usual;

  /// What this weekday usually brings in.
  final int usualMoney;

  /// Booked well under a usual day — room to fill.
  bool get light => !closed && usual >= 2 && booked < usual * .6;
}

class HubAtRisk {
  const HubAtRisk({
    required this.patientId,
    required this.name,
    required this.code,
    required this.phone,
    required this.visits,
    required this.usualGap,
    required this.daysSince,
  });

  final int patientId, visits, usualGap, daysSince;
  final String name, code, phone;
  int get overdue => daysSince - usualGap;
}

class HubOwedBack {
  const HubOwedBack(this.label, this.owed, this.rate);
  final String label;
  final int owed;

  /// Share of this kind of debt that past bills show does get paid.
  final double rate;
  int get likely => (owed * rate).round();
}

class HubForecast {
  const HubForecast({
    required this.ready,
    required this.dataDays,
    required this.startsOn,
    this.confidence = 0,
    this.monthSoFar = 0,
    this.monthLow = 0,
    this.monthMid = 0,
    this.monthHigh = 0,
    this.lastMonthTotal = 0,
    this.cumulative = const [],
    this.projected = const [],
    this.week = const [],
    this.in30 = 0,
    this.out30 = 0,
    this.expenseMonths = 0,
    this.owedBack = const [],
    this.owedHistory = 0,
    this.atRisk = const [],
    this.atRiskTotal = 0,
    this.heat = const [],
    this.heatFrom = 9,
    this.heatTo = 21,
    this.months = const [],
    this.monthIndex = 0,
    this.yearLow = 0,
    this.yearMid = 0,
    this.yearHigh = 0,
    this.lastYearTotal = 0,
    this.weekdayMean = const [],
    this.weekdayLow = const [],
    this.weekdayHigh = const [],
    this.weekdayVisits = const [],
    this.closedWeekdays = const {},
    this.todaySoFar = 0,
    this.monthSpread = 0,
  });

  /// False until [kForecastMinDays] of data exist.
  final bool ready;
  final int dataDays;
  final DateTime startsOn;

  /// 1–5: how far the numbers can be trusted (more history, steadier days).
  final int confidence;

  // ── month end ──
  final int monthSoFar, monthLow, monthMid, monthHigh, lastMonthTotal;

  /// Collected so far, running total by day of this month (index = day-1).
  final List<int> cumulative;

  /// Expected running total for the rest of the month (index = day-1;
  /// 0 for days already past).
  final List<int> projected;

  // ── next 7 days ──
  final List<HubDayAhead> week;

  // ── next 30 days ──
  final int in30, out30, expenseMonths;

  // ── owed money coming back ──
  final List<HubOwedBack> owedBack;

  /// Bills the recovery rates were learned from (0 = not enough history).
  final int owedHistory;

  // ── regulars at risk ──
  final List<HubAtRisk> atRisk;
  final int atRiskTotal;

  // ── chairs: average bookings, [weekday 0=Mon][hour - heatFrom] ──
  final List<List<double>> heat;
  final int heatFrom, heatTo;

  // ── year ahead: 12 months, actual up to [monthIndex], expected after ──
  final List<int> months;
  final int monthIndex;
  final int yearLow, yearMid, yearHigh, lastYearTotal;

  // ── the pace everything above is built from (index 0 = Monday) ──
  final List<double> weekdayMean, weekdayLow, weekdayHigh, weekdayVisits;
  final Set<int> closedWeekdays;
  final int todaySoFar;

  /// How much a month usually differs from the average (standard deviation).
  final double monthSpread;

  int get owedLikely => owedBack.fold(0, (s, o) => s + o.likely);
  int get owedTotal => owedBack.fold(0, (s, o) => s + o.owed);
  int get net30 => in30 - out30;
}

// ─────────────────────────────── helpers ──────────────────────────────────

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;
String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

double _pct(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final i = (sorted.length - 1) * p;
  final lo = i.floor(), hi = i.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
}

double _mean(Iterable<num> xs) =>
    xs.isEmpty ? 0 : xs.fold<double>(0, (s, x) => s + x) / xs.length;

double _sd(List<num> xs) {
  if (xs.length < 2) return 0;
  final m = _mean(xs);
  return math.sqrt(
    xs.fold<double>(0, (s, x) => s + (x - m) * (x - m)) / (xs.length - 1),
  );
}

// ─────────────────────────────── horizons ─────────────────────────────────

enum HubHorizon {
  today('Today', 1),
  week('Week', 7),
  month('Month', 30),
  months6('6 months', 182),
  year1('1 year', 365),
  year2('2 years', 730),
  year3('3 years', 1095),
  year4('4 years', 1461),
  year5('5 years', 1826);

  const HubHorizon(this.label, this.days);
  final String label;
  final int days;
}

class HubOutlook {
  const HubOutlook({
    required this.low,
    required this.mid,
    required this.high,
    required this.visits,
    required this.spend,
    required this.openDays,
    required this.confidence,
  });

  final int low, mid, high, visits, spend, openDays, confidence;
  int get net => mid - spend;
}

/// Money expected from today over [h], at the clinic's recent pace.
HubOutlook hubOutlook(HubForecast f, HubHorizon h) {
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  var mid = 0.0, low = 0.0, high = 0.0, visits = 0.0;
  var open = 0;
  for (var i = 0; i < h.days; i++) {
    final d = DateTime(d0.year, d0.month, d0.day + i);
    if (f.closedWeekdays.contains(d.weekday)) continue;
    open++;
    final w = d.weekday - 1;
    if (i == 0) {
      // today counts as whichever is more: what came in already or a usual day
      mid += math.max(f.todaySoFar.toDouble(), f.weekdayMean[w]);
      low += math.max(f.todaySoFar.toDouble(), f.weekdayLow[w]);
      high += math.max(f.todaySoFar.toDouble(), f.weekdayHigh[w]);
    } else {
      mid += f.weekdayMean[w];
      low += f.weekdayLow[w];
      high += f.weekdayHigh[w];
    }
    visits += f.weekdayVisits[w];
  }
  final months = h.days / 30.44;
  // Over months, good and bad weeks even out: the range grows with how
  // much whole months vary, not day by day.
  if (h.days > 31 && f.monthSpread > 0) {
    final band = f.monthSpread * math.sqrt(months);
    low = math.max(0.0, mid - band);
    high = mid + band;
  }
  return HubOutlook(
    low: low.round(),
    mid: mid.round(),
    high: high.round(),
    visits: visits.round(),
    spend: (f.out30 * months).round(),
    openDays: open,
    confidence:
        (f.confidence - (h.days >= 365 ? 1 : 0) - (h.days >= 1095 ? 1 : 0))
            .clamp(1, 5),
  );
}

// ─────────────────────────────── loader ───────────────────────────────────

Future<HubForecast> loadHubForecast({
  required AppDatabase db,
  required List<Branch> branches,
  required String? branchId,
  required List<({int due, int days})> owed,
}) async {
  final now = DateTime.now();
  final today = _day(now);

  Expression<bool> inBranch(GeneratedColumn<String> c) =>
      branchId == null ? const Constant(true) : c.equals(branchId);

  // ── how much history is there? ──
  final firstPay =
      await (db.select(db.invoicePayments)
            ..where((t) => t.isDeleted.equals(false) & inBranch(t.branchId))
            ..orderBy([(t) => OrderingTerm.asc(t.paidAt)])
            ..limit(1))
          .getSingleOrNull();
  final firstAppt =
      await (db.select(db.appointments)
            ..where((t) => t.isDeleted.equals(false) & inBranch(t.branchId))
            ..orderBy([(t) => OrderingTerm.asc(t.startsAt)])
            ..limit(1))
          .getSingleOrNull();
  final firsts = [
    if (firstPay != null) firstPay.paidAt,
    if (firstAppt != null) firstAppt.startsAt,
  ];
  final first = firsts.isEmpty
      ? today
      : _day(firsts.reduce((a, b) => a.isBefore(b) ? a : b));
  final dataDays = today.difference(first).inDays.clamp(0, 100000);
  final startsOn = first.add(const Duration(days: kForecastMinDays));
  if (dataDays < kForecastMinDays) {
    return HubForecast(ready: false, dataDays: dataDays, startsOn: startsOn);
  }

  // A weekday counts as closed only when every branch in view is closed.
  final closedWeekdays = <int>{};
  if (branches.isNotEmpty) {
    for (var w = 1; w <= 7; w++) {
      final all = branches.every(
        (b) => b.closedDays
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .contains(w),
      );
      if (all) closedWeekdays.add(w);
    }
  }
  bool closed(DateTime d) => closedWeekdays.contains(d.weekday);

  // ── payments: from 1 Jan last year (year-on-year) ──
  final since = DateTime(now.year - 1, 1, 1);
  final pays =
      await (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(since) &
                inBranch(t.branchId),
          ))
          .get();
  final byDay = <String, int>{};
  for (final p in pays) {
    final k = _key(p.paidAt);
    byDay[k] = (byDay[k] ?? 0) + p.amount;
  }
  int dayTotal(DateTime d) => byDay[_key(d)] ?? 0;

  // last 8 full weeks before today, open days only, grouped by weekday
  final perWeekday = {for (var w = 1; w <= 7; w++) w: <int>[]};
  final allDays = <int>[];
  for (var i = 1; i <= 56; i++) {
    final d = today.subtract(Duration(days: i));
    if (d.isBefore(first) || closed(d)) continue;
    perWeekday[d.weekday]!.add(dayTotal(d));
    allDays.add(dayTotal(d));
  }
  for (final l in perWeekday.values) {
    l.sort();
  }
  double mean(int w) => _mean(perWeekday[w]!);
  double p25(int w) => _pct(perWeekday[w]!, .25);
  double p75(int w) => _pct(perWeekday[w]!, .75);

  // ── 1. month end ──
  final monthStart = DateTime(now.year, now.month, 1);
  final dim = _daysIn(now.year, now.month);
  final cumulative = <int>[];
  var run = 0;
  for (var d = 1; d <= now.day; d++) {
    run += dayTotal(DateTime(now.year, now.month, d));
    cumulative.add(run);
  }
  final todaySoFar = dayTotal(today);
  final beforeToday = run - todaySoFar;
  var mid = beforeToday.toDouble(),
      low = beforeToday.toDouble(),
      high = beforeToday.toDouble();
  final projected = List<int>.filled(dim, 0);
  for (var d = now.day; d <= dim; d++) {
    final day = DateTime(now.year, now.month, d);
    if (!closed(day)) {
      final w = day.weekday;
      if (d == now.day) {
        mid += math.max(todaySoFar.toDouble(), mean(w));
        low += math.max(todaySoFar.toDouble(), p25(w));
        high += math.max(todaySoFar.toDouble(), p75(w));
      } else {
        mid += mean(w);
        low += p25(w);
        high += p75(w);
      }
    } else if (d == now.day) {
      mid += todaySoFar;
      low += todaySoFar;
      high += todaySoFar;
    }
    projected[d - 1] = mid.round();
  }
  final lastMonthStart = DateTime(now.year, now.month - 1, 1);
  var lastMonthTotal = 0;
  for (
    var d = lastMonthStart;
    d.isBefore(monthStart);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    lastMonthTotal += dayTotal(d);
  }

  // confidence: more history and steadier days → higher
  var confidence = dataDays < 90
      ? 2
      : dataDays < 180
      ? 3
      : dataDays < 365
      ? 4
      : 5;
  final m = _mean(allDays);
  if (m > 0 && _sd(allDays) / m > .9) confidence--;
  confidence = confidence.clamp(1, 5);

  // ── 2. next 7 days ──
  final past =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.isNotIn(const ['cancelled']) &
                t.startsAt.isBiggerOrEqualValue(
                  today.subtract(const Duration(days: 56)),
                ) &
                t.startsAt.isSmallerThanValue(today) &
                inBranch(t.branchId),
          ))
          .get();
  final usualCount = {for (var w = 1; w <= 7; w++) w: 0};
  for (final a in past) {
    usualCount[a.startsAt.weekday] = usualCount[a.startsAt.weekday]! + 1;
  }
  final weeksSeen = math.max(
    1,
    math.min(8, today.difference(first).inDays ~/ 7),
  );
  final ahead =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.isIn(const ['upcoming', 'waiting', 'inChair']) &
                t.startsAt.isBiggerOrEqualValue(
                  today.add(const Duration(days: 1)),
                ) &
                t.startsAt.isSmallerThanValue(
                  today.add(const Duration(days: 31)),
                ) &
                inBranch(t.branchId),
          ))
          .get();
  // weeks of history behind the averages (at most the 8 looked at)
  final weeks = math.max(1, math.min(8, today.difference(first).inDays ~/ 7));
  final week = [
    for (var i = 1; i <= 7; i++)
      () {
        final d = today.add(Duration(days: i));
        return HubDayAhead(
          day: d,
          closed: closed(d),
          booked: ahead.where((a) => _day(a.startsAt) == d).length,
          usual: usualCount[d.weekday]! / weeks,
          usualMoney: closed(d) ? 0 : mean(d.weekday).round(),
        );
      }(),
  ];

  // ── 3. next 30 days: money in vs money out ──
  var in30 = 0.0;
  for (var i = 1; i <= 30; i++) {
    final d = today.add(Duration(days: i));
    if (!closed(d)) in30 += mean(d.weekday);
  }
  final expStart = DateTime(now.year, now.month - 3, 1);
  final exps =
      await (db.select(db.expenses)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(expStart) &
                t.paidAt.isSmallerThanValue(monthStart) &
                inBranch(t.branchId),
          ))
          .get();
  final expMonths = {
    for (final e in exps) '${e.paidAt.year}-${e.paidAt.month}',
  }.length;
  final out30 = expMonths == 0
      ? 0
      : exps.fold<int>(0, (s, e) => s + e.amount) / expMonths;

  // ── 4. owed money coming back (learned from bills 90–365 days old) ──
  final sampleInv =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                t.total.isBiggerThanValue(0) &
                t.issuedAt.isBiggerOrEqualValue(
                  today.subtract(const Duration(days: 365)),
                ) &
                t.issuedAt.isSmallerThanValue(
                  today.subtract(const Duration(days: 90)),
                ) &
                inBranch(t.branchId),
          ))
          .get();
  final paysByInvoice = <int, List<InvoicePaymentRow>>{};
  for (final p in pays) {
    (paysByInvoice[p.invoiceId] ??= []).add(p);
  }
  var tTotal = 0.0, pAll = 0.0;
  final pBy = {1: 0.0, 30: 0.0, 60: 0.0, 90: 0.0};
  for (final inv in sampleInv) {
    final issued = _day(inv.issuedAt);
    final ps = paysByInvoice[inv.id] ?? const <InvoicePaymentRow>[];
    tTotal += inv.total;
    double paidWithin(int days) => math
        .min(
          inv.total,
          ps
              .where(
                (p) =>
                    !_day(p.paidAt).isAfter(issued.add(Duration(days: days))),
              )
              .fold<int>(0, (s, p) => s + p.amount),
        )
        .toDouble();
    pAll += math.min(inv.total, ps.fold<int>(0, (s, p) => s + p.amount));
    for (final a in pBy.keys.toList()) {
      pBy[a] = pBy[a]! + paidWithin(a);
    }
  }
  final enough = sampleInv.length >= 15 && tTotal > 0;
  double rate(int a) {
    if (!enough) return 0;
    final left = tTotal - pBy[a]!;
    return left <= 0 ? 0 : ((pAll - pBy[a]!) / left).clamp(0.0, 1.0);
  }

  final buckets = List<int>.filled(4, 0);
  for (final o in owed) {
    buckets[o.days <= 30
            ? 0
            : o.days <= 60
            ? 1
            : o.days <= 90
            ? 2
            : 3] +=
        o.due;
  }
  final owedBack = [
    HubOwedBack('Up to 30 days old', buckets[0], rate(1)),
    HubOwedBack('31–60 days old', buckets[1], rate(30)),
    HubOwedBack('61–90 days old', buckets[2], rate(60)),
    HubOwedBack('Over 90 days old', buckets[3], rate(90)),
  ];

  // ── 5. regulars at risk ──
  final done =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('completed') &
                t.startsAt.isSmallerThanValue(
                  today.add(const Duration(days: 1)),
                ) &
                inBranch(t.branchId),
          ))
          .get();
  final billed =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                inBranch(t.branchId),
          ))
          .get();
  final days = <int, Set<DateTime>>{};
  for (final a in done) {
    (days[a.patientId] ??= {}).add(_day(a.startsAt));
  }
  for (final i in billed) {
    if (i.issuedAt.isAfter(now)) continue;
    (days[i.patientId] ??= {}).add(_day(i.issuedAt));
  }
  final booked = {for (final a in ahead) a.patientId};
  final todayBooked =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.isIn(const ['upcoming', 'waiting', 'inChair']) &
                t.startsAt.isBiggerOrEqualValue(today) &
                inBranch(t.branchId),
          ))
          .get();
  booked.addAll(todayBooked.map((a) => a.patientId));

  final risky = <({int pid, int visits, int gap, int since})>[];
  for (final e in days.entries) {
    if (booked.contains(e.key)) continue;
    final sorted = e.value.toList()..sort();
    // visits within 14 days of each other are one course of treatment
    final starts = <DateTime>[];
    for (final d in sorted) {
      if (starts.isEmpty || d.difference(starts.last).inDays > 14) {
        starts.add(d);
      }
    }
    if (starts.length < 3) continue;
    final gaps = [
      for (var i = 1; i < starts.length; i++)
        starts[i].difference(starts[i - 1]).inDays,
    ]..sort();
    final usual = gaps[gaps.length ~/ 2];
    final since = today.difference(sorted.last).inDays;
    final lateAfter = math.max((usual * 1.5).round(), usual + 30);
    if (since > lateAfter && since < 730) {
      risky.add((pid: e.key, visits: starts.length, gap: usual, since: since));
    }
  }
  risky.sort((a, b) => (b.since - b.gap).compareTo(a.since - a.gap));
  final top = risky.take(8).toList();
  final people = top.isEmpty
      ? const <int, PatientRow>{}
      : {
          for (final p
              in await (db.select(db.patients)..where(
                    (t) =>
                        t.id.isIn(top.map((r) => r.pid)) &
                        t.isDeleted.equals(false),
                  ))
                  .get())
            p.id: p,
        };
  final atRisk = [
    for (final r in top)
      if (people[r.pid] != null)
        HubAtRisk(
          patientId: r.pid,
          name: people[r.pid]!.fullName,
          code: people[r.pid]!.code,
          phone: people[r.pid]!.phone ?? '',
          visits: r.visits,
          usualGap: r.gap,
          daysSince: r.since,
        ),
  ];

  // ── 6. when the chairs are full (last 8 weeks) ──
  var from = branches.isEmpty
      ? 9
      : branches.map((b) => b.openMinutes ~/ 60).reduce(math.min);
  var to = branches.isEmpty
      ? 21
      : branches.map((b) => (b.closeMinutes + 59) ~/ 60).reduce(math.max);
  if (to <= from) to = from + 8;
  from = from.clamp(0, 23);
  to = to.clamp(from + 1, 24);
  final heat = List.generate(7, (_) => List<double>.filled(to - from, 0));
  for (final a in past) {
    final h = a.startsAt.hour;
    if (h < from || h >= to) continue;
    heat[a.startsAt.weekday - 1][h - from] += 1 / weeks;
  }

  // ── 7. year ahead ──
  final months = List<int>.filled(12, 0);
  var lastYearTotal = 0;
  for (final p in pays) {
    if (p.paidAt.year == now.year) months[p.paidAt.month - 1] += p.amount;
    if (p.paidAt.year == now.year - 1) lastYearTotal += p.amount;
  }
  // whole months before this one (newest first) with data from day one
  final full = <int>[];
  for (var i = 1; i <= 6; i++) {
    final ms = DateTime(now.year, now.month - i, 1);
    if (ms.isBefore(DateTime(first.year, first.month + 1, 1))) break;
    full.add(
      ms.year == now.year
          ? months[ms.month - 1]
          : pays
                .where(
                  (p) => p.paidAt.year == ms.year && p.paidAt.month == ms.month,
                )
                .fold<int>(0, (s, p) => s + p.amount),
    );
  }
  // no whole month yet → a usual open day × open days in a month
  final avg = full.isEmpty
      ? _mean(allDays) * 30 * (7 - closedWeekdays.length) / 7
      : _mean(full.take(3));
  final spread = _sd(full);
  final ci = now.month - 1;
  months[ci] = mid.round();
  var yMid = 0.0, yLow = 0.0, yHigh = 0.0;
  for (var i = 0; i < 12; i++) {
    if (i < ci) {
      yMid += months[i];
      yLow += months[i];
      yHigh += months[i];
    } else if (i == ci) {
      yMid += mid;
      yLow += low;
      yHigh += high;
    } else {
      months[i] = avg.round();
      yMid += avg;
      yLow += math.max(0, avg - spread);
      yHigh += avg + spread;
    }
  }

  return HubForecast(
    ready: true,
    dataDays: dataDays,
    startsOn: startsOn,
    confidence: confidence,
    monthSoFar: run,
    monthLow: low.round(),
    monthMid: mid.round(),
    monthHigh: high.round(),
    lastMonthTotal: lastMonthTotal,
    cumulative: cumulative,
    projected: projected,
    week: week,
    in30: in30.round(),
    out30: out30.round(),
    expenseMonths: expMonths,
    owedBack: owedBack,
    owedHistory: enough ? sampleInv.length : 0,
    atRisk: atRisk,
    atRiskTotal: risky.length,
    heat: heat,
    heatFrom: from,
    heatTo: to,
    months: months,
    monthIndex: ci,
    yearLow: yLow.round(),
    yearMid: yMid.round(),
    yearHigh: yHigh.round(),
    lastYearTotal: lastYearTotal,
    weekdayMean: [for (var w = 1; w <= 7; w++) mean(w)],
    weekdayLow: [for (var w = 1; w <= 7; w++) p25(w)],
    weekdayHigh: [for (var w = 1; w <= 7; w++) p75(w)],
    weekdayVisits: [for (var w = 1; w <= 7; w++) usualCount[w]! / weeksSeen],
    closedWeekdays: closedWeekdays,
    todaySoFar: todaySoFar,
    monthSpread: spread,
  );
}
