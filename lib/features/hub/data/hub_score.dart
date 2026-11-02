import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:is_dental/core/constants/views.dart';

import 'hub_data.dart';
import 'hub_forecast.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Clinic health score (0–100). Always the last 30 full days (today is not
//  counted), compared with the 30 days before, so the number stays steady
//  whatever period is picked at the top of the Hub.
//
//  Every text here can end up in the owner PDF, whose built-in font only
//  knows Latin-1: plain hyphens, no long dashes or arrows.
// ═══════════════════════════════════════════════════════════════════════════

/// Settings key for how many chairs a branch has ('' = worked out).
String hubChairsKey(String branchUuid) => 'hub_chairs:$branchUuid';

/// Below this many points measured, there is no score yet.
const kScoreMinWeight = 40;

enum HubScoreKey {
  collections,
  owed,
  visits,
  chairs,
  regulars,
  system,
  discounts,
}

/// One pass / fail item of the "System" part.
class HubCheck {
  const HubCheck(this.label, this.ok, this.go);

  /// Says what should be true, e.g. "Computer B synced in the last 3 days".
  final String label;
  final bool ok;
  final HubGo go;
}

/// One part of the score.
class HubScorePart {
  const HubScorePart({
    required this.key,
    required this.label,
    required this.weight,
    required this.earned,
    required this.text,
    required this.how,
    this.missing,
    this.action,
    this.go,
  });

  final HubScoreKey key;
  final String label;
  final int weight;

  /// Points earned out of [weight]; null = left out of the score.
  final double? earned;

  /// What was seen, in plain words. Amounts become dots when hidden.
  final String Function(bool hidden) text;

  /// "How we worked this out".
  final String how;

  /// Why it was left out. Null while [earned] is null means it is not
  /// measured for this view on purpose (clinic-wide parts on a branch).
  final String? missing;

  /// The button that goes to the fix.
  final String? action;
  final HubGo? go;

  bool get counted => earned != null;
  double get lost => counted ? weight - earned! : 0.0;

  /// 0–1 of the points this part can give.
  double get share => counted && weight > 0 ? earned! / weight : 0.0;
}

class HubScore {
  const HubScore({
    required this.value,
    required this.previous,
    required this.parts,
    required this.completeOn,
  });

  /// Null until at least [kScoreMinWeight] points can be measured.
  final int? value;

  /// The same parts, 30 days earlier. Null when they can't be compared.
  final int? previous;
  final List<HubScorePart> parts;

  /// When every missing part should be measurable (null = unknown).
  final DateTime? completeOn;

  bool get ready => value != null;

  /// Some parts couldn't be measured yet; the rest were scaled to 100.
  bool get partial => parts.any((p) => !p.counted && p.missing != null);
  int? get change =>
      value == null || previous == null ? null : value! - previous!;
  String get label => hubScoreLabel(value);

  /// Parts costing at least half a point, biggest first.
  List<HubScorePart> get drags => [
    for (final p in parts)
      if (p.counted && p.lost >= .5) p,
  ]..sort((a, b) => b.lost.compareTo(a.lost));

  List<HubScorePart> get missingParts => [
    for (final p in parts)
      if (!p.counted && p.missing != null) p,
  ];
}

String hubScoreLabel(int? v) => v == null
    ? 'Not enough data yet'
    : v >= 85
    ? 'Excellent'
    : v >= 70
    ? 'Good'
    : v >= 50
    ? 'Needs attention'
    : 'At risk';

/// Everything the score is worked out from, for one stretch of 30 days.
class HubScoreInputs {
  const HubScoreInputs({
    this.collected = 0,
    this.usual,
    this.usualStretches = 0,
    this.collectionsMissing,
    this.owedTotal = 0,
    this.owedOver60 = 0,
    this.bookings = 0,
    this.noShows = 0,
    this.cancelled = 0,
    this.bookedMinutes = 0,
    this.capacityMinutes = 0,
    this.chairs = 0,
    this.chairsSet = false,
    this.regulars,
    this.regularsOverdue = 0,
    this.regularsMissing,
    this.checks,
    this.discount = 0,
    this.billed = 0,
    this.removals = 0,
  });

  // ── collections ──
  /// Collected in the 30 days.
  final int collected;

  /// Average of up to 3 earlier 30-day stretches; null = none to compare.
  final int? usual;
  final int usualStretches;
  final String? collectionsMissing;

  // ── owed (as it stands today) ──
  final int owedTotal, owedOver60;

  // ── bookings in the 30 days ──
  final int bookings, noShows, cancelled;

  // ── chairs ──
  final int bookedMinutes, capacityMinutes, chairs;

  /// Chairs typed in by the owner rather than worked out.
  final bool chairsSet;

  // ── regulars (whole clinic or the branch picked at the top) ──
  /// Null = not measured for this view.
  final int? regulars;
  final int regularsOverdue;
  final String? regularsMissing;

  // ── system; null = not measured for this view ──
  final List<HubCheck>? checks;

  // ── discounts and removals in the 30 days ──
  final int discount, billed, removals;

  /// Usual monthly collections — what owed money is compared with.
  int get monthBase => usual ?? collected;

  /// This stretch's money and visits with today's owed money, regulars and
  /// checks — those can't be rebuilt for 30 days ago.
  HubScoreInputs withStateOf(HubScoreInputs today) => HubScoreInputs(
    collected: collected,
    usual: usual,
    usualStretches: usualStretches,
    collectionsMissing: collectionsMissing,
    owedTotal: today.owedTotal,
    owedOver60: today.owedOver60,
    bookings: bookings,
    noShows: noShows,
    cancelled: cancelled,
    bookedMinutes: bookedMinutes,
    capacityMinutes: capacityMinutes,
    chairs: chairs,
    chairsSet: chairsSet,
    regulars: today.regulars,
    regularsOverdue: today.regularsOverdue,
    regularsMissing: today.regularsMissing,
    checks: today.checks,
    discount: discount,
    billed: billed,
    removals: removals,
  );
}

// ─────────────────────────────── the maths ────────────────────────────────

/// Where [x] sits between [zero] (0) and [full] (1), clamped. Works both
/// ways round: (ratio, 1.0, .6) and (share, 0, .3).
double hubBand(double x, double full, double zero) {
  if (full == zero) return x >= full ? 1.0 : 0.0;
  final t = (x - zero) / (full - zero);
  if (t.isNaN) return 0;
  return t.clamp(0.0, 1.0).toDouble();
}

String _money(int v, bool hidden) => hidden
    ? 'Rs ••••••' // screen only — the PDF always passes hidden: false
    : '${v < 0 ? '-' : ''}Rs ${v.abs().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

String _n(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

int _pct(double x) => (x * 100).round();

const _monShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String _date(DateTime d) => '${d.day} ${_monShort[d.month - 1]} ${d.year}';

/// The seven parts for one set of inputs.
List<HubScorePart> hubScoreParts(HubScoreInputs n) {
  final parts = <HubScorePart>[];

  // ── 1. collections vs usual (25) ──
  final usual = n.usual;
  if (usual == null || usual <= 0) {
    parts.add(
      HubScorePart(
        key: HubScoreKey.collections,
        label: 'Collections vs usual',
        weight: 25,
        earned: null,
        missing:
            n.collectionsMissing ??
            'Needs 30 days of earlier payments to compare with',
        text: (h) => '${_money(n.collected, h)} in the last 30 days',
        how: _howCollections,
        action: 'See Money',
        go: HubGo.money,
      ),
    );
  } else {
    final ratio = n.collected / usual;
    final p = _pct(ratio);
    parts.add(
      HubScorePart(
        key: HubScoreKey.collections,
        label: 'Collections vs usual',
        weight: 25,
        earned: 25 * hubBand(ratio, 1, .6),
        text: (h) => p == 100
            ? '${_money(n.collected, h)} in the last 30 days, right at your '
                  'usual ${_money(usual, h)}'
            : p > 100
            ? '${_money(n.collected, h)} in the last 30 days, ${p - 100}% '
                  'above your usual ${_money(usual, h)}'
            : '${_money(n.collected, h)} in the last 30 days, $p% of your '
                  'usual ${_money(usual, h)}',
        how: _howCollections,
        action: 'See Money',
        go: HubGo.money,
      ),
    );
  }

  // ── 2. owed money and its age (20) ──
  final base = n.monthBase;
  if (base <= 0 && n.owedTotal <= 0) {
    parts.add(
      HubScorePart(
        key: HubScoreKey.owed,
        label: 'Money owed',
        weight: 20,
        earned: null,
        missing: 'No bills or payments yet',
        text: (h) => 'Nothing billed yet',
        how: _howOwed,
        action: 'Open Billing',
        go: HubGo.billing,
      ),
    );
  } else {
    final share = base > 0
        ? n.owedOver60 / base
        : (n.owedOver60 > 0 ? 1.0 : 0.0);
    parts.add(
      HubScorePart(
        key: HubScoreKey.owed,
        label: 'Money owed',
        weight: 20,
        earned: 20 * hubBand(share, 0, .3),
        text: (h) => n.owedTotal <= 0
            ? 'Nothing is owed'
            : n.owedOver60 <= 0
            ? '${_money(n.owedTotal, h)} owed, none of it older than 60 days'
            : '${_money(n.owedOver60, h)} owed for over 60 days, '
                  '${_pct(share)}% of a usual month\'s collections',
        how: _howOwed,
        action: 'Open Billing',
        go: HubGo.billing,
      ),
    );
  }

  // ── 3. no-shows and cancellations (15) ──
  if (n.bookings < 10) {
    parts.add(
      HubScorePart(
        key: HubScoreKey.visits,
        label: 'No-shows and cancellations',
        weight: 15,
        earned: null,
        missing:
            'Needs at least 10 bookings in 30 days '
            '(${n.bookings} so far)',
        text: (h) => _n(n.bookings, 'booking'),
        how: _howVisits,
        action: 'Open Appointments',
        go: HubGo.appointments,
      ),
    );
  } else {
    final rate = (n.noShows + n.cancelled) / n.bookings;
    parts.add(
      HubScorePart(
        key: HubScoreKey.visits,
        label: 'No-shows and cancellations',
        weight: 15,
        earned: 15 * hubBand(rate, .05, .25),
        text: (h) =>
            '${_n(n.noShows, 'no-show')} and '
            '${_n(n.cancelled, 'cancellation')} out of '
            '${_n(n.bookings, 'booking')} (${_pct(rate)}%)',
        how: _howVisits,
        action: 'Open Appointments',
        go: HubGo.appointments,
      ),
    );
  }

  // ── 4. chair use (15) ──
  final chairsWord =
      '${_n(n.chairs, 'chair')}${n.chairsSet ? '' : ', worked out'}';
  if (n.capacityMinutes <= 0 || n.bookings < 10) {
    parts.add(
      HubScorePart(
        key: HubScoreKey.chairs,
        label: 'Chair use',
        weight: 15,
        earned: null,
        missing: n.capacityMinutes <= 0
            ? 'Opening hours are not set for this branch'
            : 'Needs at least 10 bookings in 30 days',
        text: (h) => chairsWord,
        how: _howChairs,
        action: 'See busy hours',
        go: HubGo.whatsComing,
      ),
    );
  } else {
    final use = n.bookedMinutes / n.capacityMinutes;
    parts.add(
      HubScorePart(
        key: HubScoreKey.chairs,
        label: 'Chair use',
        weight: 15,
        earned: 15 * hubBand(use, .65, .25),
        text: (h) =>
            'Chairs were booked ${_pct(use)}% of open hours ($chairsWord)',
        how: _howChairs,
        action: 'See busy hours',
        go: HubGo.whatsComing,
      ),
    );
  }

  // ── 5. regulars coming back (10) ──
  final regulars = n.regulars;
  if (regulars == null || regulars < 5) {
    parts.add(
      HubScorePart(
        key: HubScoreKey.regulars,
        label: 'Regulars coming back',
        weight: 10,
        earned: null,
        missing: regulars == null
            ? n.regularsMissing
            : 'Needs at least 5 regular patients ($regulars so far)',
        text: (h) => regulars != null
            ? _n(regulars, 'regular')
            : (n.regularsMissing != null
                  ? 'Not measured yet'
                  : 'Counted for the whole clinic only'),
        how: _howRegulars,
        action: 'See who',
        go: HubGo.whatsComing,
      ),
    );
  } else {
    final share = n.regularsOverdue / regulars;
    parts.add(
      HubScorePart(
        key: HubScoreKey.regulars,
        label: 'Regulars coming back',
        weight: 10,
        earned: 10 * hubBand(share, .05, .30),
        text: (h) => n.regularsOverdue == 0
            ? 'None of your $regulars regulars is overdue'
            : '${n.regularsOverdue} of $regulars regulars are overdue for a '
                  'visit (${_pct(share)}%)',
        how: _howRegulars,
        action: 'See who',
        go: HubGo.whatsComing,
      ),
    );
  }

  // ── 6. system (10) ──
  final checks = n.checks;
  if (checks == null || checks.isEmpty) {
    parts.add(
      HubScorePart(
        key: HubScoreKey.system,
        label: 'Computers, WhatsApp and licence',
        weight: 10,
        earned: null,
        missing: checks == null ? null : 'Nothing to check',
        text: (h) => 'Counted for the whole clinic only',
        how: _howSystem,
        action: 'See System health',
        go: HubGo.health,
      ),
    );
  } else {
    final ok = checks.where((c) => c.ok).length;
    final failing = [
      for (final c in checks)
        if (!c.ok) c,
    ];
    parts.add(
      HubScorePart(
        key: HubScoreKey.system,
        label: 'Computers, WhatsApp and licence',
        weight: 10,
        earned: 10 * ok / checks.length,
        text: (h) => failing.isEmpty
            ? 'All ${checks.length} checks pass'
            : 'Not right: ${failing.map((c) => c.label).join('; ')}',
        how: _howSystem,
        action: failing.isEmpty
            ? 'See System health'
            : (failing.first.go == HubGo.whatsapp
                  ? 'Open WhatsApp'
                  : 'Open Settings'),
        go: failing.isEmpty ? HubGo.health : failing.first.go,
      ),
    );
  }

  // ── 7. discounts and removals (5) ──
  if (n.billed <= 0) {
    parts.add(
      HubScorePart(
        key: HubScoreKey.discounts,
        label: 'Discounts and removals',
        weight: 5,
        earned: null,
        missing: 'No bills in the last 30 days',
        text: (h) => 'No bills',
        how: _howDiscounts,
        action: 'Open Watch list',
        go: HubGo.watchList,
      ),
    );
  } else {
    final share = n.discount / (n.billed + n.discount);
    parts.add(
      HubScorePart(
        key: HubScoreKey.discounts,
        label: 'Discounts and removals',
        weight: 5,
        earned:
            3 * hubBand(share, .05, .15) +
            2 * hubBand(n.removals.toDouble(), 0, 5),
        text: (h) =>
            'Discounts were ${_pct(share)}% of bills · '
            '${n.removals == 0 ? 'nothing cancelled, removed or deleted' : '${_n(n.removals, 'bill, payment or expense', 'bills, payments or expenses')} cancelled, removed or deleted'}',
        how: _howDiscounts,
        action: 'Open Watch list',
        go: HubGo.watchList,
      ),
    );
  }
  return parts;
}

/// 0–100, or null when fewer than [kScoreMinWeight] points could be measured.
/// Parts left out are skipped and the rest scaled up to 100.
int? hubScoreValue(List<HubScorePart> parts) {
  var got = 0.0;
  var max = 0;
  for (final p in parts) {
    if (!p.counted) continue;
    got += p.earned!;
    max += p.weight;
  }
  if (max < kScoreMinWeight) return null;
  return (got / max * 100).round().clamp(0, 100);
}

/// The score for [now], with the change since [before] when both measure
/// the same parts (otherwise the change would compare different things).
HubScore hubScore(
  HubScoreInputs now, {
  HubScoreInputs? before,
  DateTime? completeOn,
}) {
  final parts = hubScoreParts(now);
  int? previous;
  if (before != null) {
    final old = hubScoreParts(before);
    Set<HubScoreKey> measured(List<HubScorePart> l) => {
      for (final p in l)
        if (p.counted) p.key,
    };
    final a = measured(old), b = measured(parts);
    if (a.length == b.length && a.containsAll(b)) {
      previous = hubScoreValue(old);
    }
  }
  final value = hubScoreValue(parts);
  return HubScore(
    value: value,
    previous: value == null ? null : previous,
    parts: parts,
    completeOn: parts.any((p) => !p.counted && p.missing != null)
        ? completeOn
        : null,
  );
}

// "How we worked this out" for each part.
const _howCollections =
    'Money collected in the last 30 full days (today is not counted), '
    'against the average of up to three earlier 30-day stretches. Full '
    'points at your usual pace or better, none at 60% of it or less.';
const _howOwed =
    'Money still owed on bills older than 60 days, against what a usual '
    'month brings in. Full points when nothing is that old, none when it '
    'reaches 30% of a month.';
const _howVisits =
    'Bookings in the last 30 days that ended as a no-show or were '
    'cancelled. Full points at 5% or less, none at 25% or more.';
const _howChairs =
    'Booked appointment time in the last 30 days, against opening hours '
    'times chairs on the days you are open. Chairs are worked out from the '
    'most visits booked at the same time on at least 3 days in the last '
    '8 weeks, unless you set the number. Full points at 65% or more, none '
    'at 25% or less.';
const _howRegulars =
    'Regulars are patients with 3 or more separate courses of treatment '
    'who came in the last 2 years. Overdue means well past their usual gap '
    'between visits, with nothing booked. Full points at 5% or less, none '
    'at 30% or more.';
const _howSystem =
    'Each check counts the same: this computer synced in the last 24 '
    'hours, every other computer seen in the last 3 days, every record '
    'synced, WhatsApp connected with no failed messages this week, and '
    'more than 14 days left on the licence.';
const _howDiscounts =
    'Money taken off bills in the last 30 days against what was billed '
    '(3 points: full at 5% or less, none at 15%), plus bills cancelled, '
    'payments removed and expenses deleted (2 points: full at none, none '
    'at 5 or more).';

// ─────────────────────────────── chairs ───────────────────────────────────

class HubChairInfo {
  const HubChairInfo({
    required this.uuid,
    required this.name,
    required this.auto,
    required this.chosen,
  });

  final String uuid, name;

  /// Worked out from the last 8 weeks of bookings.
  final int auto;

  /// Typed in by the owner (null = use [auto]).
  final int? chosen;
  int get used => chosen ?? auto;
}

/// Chairs a branch seems to have: the most visits booked at the same time,
/// reached on at least 3 different days (one double-booking doesn't add a
/// chair). [spans] are (start, end) times of the branch's bookings.
int hubAutoChairs(List<(DateTime, DateTime)> spans) {
  final byDay = <int, List<(DateTime, DateTime)>>{};
  for (final s in spans) {
    final k = s.$1.year * 10000 + s.$1.month * 100 + s.$1.day;
    (byDay[k] ??= []).add(s);
  }
  final peaks = <int>[];
  for (final day in byDay.values) {
    final events = <(int, int)>[
      for (final s in day) ...[
        (s.$1.millisecondsSinceEpoch, 1),
        (s.$2.millisecondsSinceEpoch, -1),
      ],
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    var cur = 0, best = 0;
    for (final e in events) {
      cur += e.$2;
      if (cur > best) best = cur;
    }
    peaks.add(best);
  }
  if (peaks.isEmpty) return 1;
  peaks.sort((a, b) => b - a);
  final v = peaks.length >= 3 ? peaks[2] : peaks.reduce(math.min);
  return math.max(1, v);
}

// ─────────────────────────────── loader ───────────────────────────────────

class HubScores {
  const HubScores({
    required this.clinic,
    required this.branches,
    required this.chairs,
    required this.inputs,
  });

  /// The branch picked at the top, or the whole clinic.
  final HubScore clinic;

  /// One per branch, only in the all-branches view of a clinic with 2+.
  final Map<String, HubScore> branches;

  /// Chairs of the branches in view.
  final List<HubChairInfo> chairs;

  /// The last 30 days behind [clinic] — What if reuses them.
  final HubScoreInputs inputs;

  int get chairCount => chairs.fold(0, (s, c) => s + c.used);
  bool get chairsAllSet =>
      chairs.isNotEmpty && chairs.every((c) => c.chosen != null);
}

Future<HubScores> loadHubScores({
  required AppDatabase db,
  required List<Branch> allBranches,
  required String? branchId,
  required HubForecast forecast,
  required List<({String branch, int due, int days})> owed,
  required List<HubCheck> checks,
}) async {
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  DateTime ago(int days) => DateTime(d0.year, d0.month, d0.day - days);

  Expression<bool> inScope(GeneratedColumn<String> c) =>
      branchId == null ? const Constant(true) : c.equals(branchId);
  bool inB(String? row, String? b) => b == null || row == b;

  final inView = branchId == null
      ? allBranches
      : allBranches.where((b) => b.uuid == branchId).toList();

  // ── the records, read once ──
  final pays =
      await (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(ago(150)) &
                t.paidAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();
  // cancelled visits are soft-deleted, so they are read back by status
  final appts =
      await (db.select(db.appointments)..where(
            (t) =>
                (t.isDeleted.equals(false) | t.status.equals('cancelled')) &
                t.startsAt.isBiggerOrEqualValue(ago(60)) &
                t.startsAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();
  final bills =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                t.issuedAt.isBiggerOrEqualValue(ago(60)) &
                t.issuedAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();
  final cancelledBills =
      await (db.select(db.invoices)..where(
            (t) =>
                t.status.equals('cancelled') &
                t.cancelledAt.isBiggerOrEqualValue(ago(60)) &
                t.cancelledAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();
  final removedPays =
      await (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(true) &
                t.deletedAt.isBiggerOrEqualValue(ago(60)) &
                t.deletedAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();
  final deletedExps =
      await (db.select(db.expenses)..where(
            (t) =>
                t.isDeleted.equals(true) &
                t.deletedAt.isBiggerOrEqualValue(ago(60)) &
                t.deletedAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();

  // ── first day of records, per branch (and for the whole view) ──
  Future<DateTime?> firstDay(String? b) async {
    Expression<bool> f(GeneratedColumn<String> c) =>
        b == null ? const Constant(true) : c.equals(b);
    final p =
        await (db.select(db.invoicePayments)
              ..where((t) => t.isDeleted.equals(false) & f(t.branchId))
              ..orderBy([(t) => OrderingTerm.asc(t.paidAt)])
              ..limit(1))
            .getSingleOrNull();
    final a =
        await (db.select(db.appointments)
              ..where((t) => t.isDeleted.equals(false) & f(t.branchId))
              ..orderBy([(t) => OrderingTerm.asc(t.startsAt)])
              ..limit(1))
            .getSingleOrNull();
    final all = [if (p != null) p.paidAt, if (a != null) a.startsAt];
    if (all.isEmpty) return null;
    final m = all.reduce((x, y) => x.isBefore(y) ? x : y);
    return DateTime(m.year, m.month, m.day);
  }

  // ── chairs, from the last 8 weeks ──
  final chairs = <HubChairInfo>[];
  for (final b in inView) {
    final spans = [
      for (final a in appts)
        if (a.branchId == b.uuid &&
            a.status != 'cancelled' &&
            !a.startsAt.isBefore(ago(56)))
          (
            a.startsAt,
            a.startsAt.add(
              Duration(minutes: a.durationMin <= 0 ? 30 : a.durationMin),
            ),
          ),
    ];
    final typed = int.tryParse(
      (await db.getSetting(hubChairsKey(b.uuid)) ?? '').trim(),
    );
    chairs.add(
      HubChairInfo(
        uuid: b.uuid,
        name: b.name,
        auto: hubAutoChairs(spans),
        chosen: typed != null && typed > 0 ? typed : null,
      ),
    );
  }
  final chairsOf = {for (final c in chairs) c.uuid: c};

  Set<int> closedOf(Branch b) => {
    for (final s in b.closedDays.split(','))
      if (int.tryParse(s.trim()) != null) int.parse(s.trim()),
  };

  // ── one 30-day stretch [from, to) for branch [b] (null = the view) ──
  HubScoreInputs stretch(
    String? b,
    DateTime from,
    DateTime to,
    DateTime? first, {
    required bool wholeView,
  }) {
    bool inWin(DateTime t) => !t.isBefore(from) && t.isBefore(to);

    final collected = pays
        .where((p) => inB(p.branchId, b) && inWin(p.paidAt))
        .fold<int>(0, (s, p) => s + p.amount);

    // up to 3 earlier stretches, only ones fully inside the records
    final earlier = <int>[];
    for (var k = 1; k <= 3; k++) {
      final s = DateTime(from.year, from.month, from.day - 30 * k);
      final e = DateTime(to.year, to.month, to.day - 30 * k);
      if (first == null || s.isBefore(first)) break;
      earlier.add(
        pays
            .where(
              (p) =>
                  inB(p.branchId, b) &&
                  !p.paidAt.isBefore(s) &&
                  p.paidAt.isBefore(e),
            )
            .fold<int>(0, (sum, p) => sum + p.amount),
      );
    }
    final usual = earlier.isEmpty
        ? null
        : (earlier.reduce((x, y) => x + y) / earlier.length).round();
    final collectionsMissing = first == null
        ? 'No payments yet'
        : 'Needs 30 days of earlier payments to compare with - from '
              '${_date(DateTime(first.year, first.month, first.day + 60))}';

    // owed money as it stands today
    final myOwed = owed.where((o) => b == null || o.branch == b);
    final owedTotal = myOwed.fold<int>(0, (s, o) => s + o.due);
    final owedOver60 = myOwed
        .where((o) => o.days > 60)
        .fold<int>(0, (s, o) => s + o.due);

    // bookings
    final mine = appts.where((a) => inB(a.branchId, b) && inWin(a.startsAt));
    var bookings = 0, noShows = 0, cancelled = 0, booked = 0;
    for (final a in mine) {
      bookings++;
      if (a.status == 'noShow') {
        noShows++;
      } else if (a.status == 'cancelled') {
        cancelled++;
      } else {
        booked += a.durationMin <= 0 ? 30 : a.durationMin;
      }
    }

    // opening hours x chairs on open days
    var capacity = 0;
    var chairCount = 0;
    var allSet = true;
    for (final br in inView) {
      if (b != null && br.uuid != b) continue;
      final c = chairsOf[br.uuid];
      final n = c?.used ?? 1;
      chairCount += n;
      if (c?.chosen == null) allSet = false;
      final perDay = br.closeMinutes - br.openMinutes;
      if (perDay <= 0) continue;
      final closed = closedOf(br);
      for (
        var d = from;
        d.isBefore(to);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        if (!closed.contains(d.weekday)) capacity += perDay * n;
      }
    }

    // discounts and removals
    final myBills = bills.where((i) => inB(i.branchId, b) && inWin(i.issuedAt));
    final discount = myBills
        .where((i) => i.adjustment > 0)
        .fold<int>(0, (s, i) => s + i.adjustment);
    final billed = myBills.fold<int>(0, (s, i) => s + i.total);
    final removals =
        cancelledBills
            .where(
              (i) =>
                  inB(i.branchId, b) &&
                  i.cancelledAt != null &&
                  inWin(i.cancelledAt!),
            )
            .length +
        removedPays
            .where(
              (p) =>
                  inB(p.branchId, b) &&
                  p.deletedAt != null &&
                  inWin(p.deletedAt!),
            )
            .length +
        deletedExps
            .where(
              (e) =>
                  inB(e.branchId, b) &&
                  e.deletedAt != null &&
                  inWin(e.deletedAt!),
            )
            .length;

    return HubScoreInputs(
      collected: collected,
      usual: usual,
      usualStretches: earlier.length,
      collectionsMissing: collectionsMissing,
      owedTotal: owedTotal,
      owedOver60: owedOver60,
      bookings: bookings,
      noShows: noShows,
      cancelled: cancelled,
      bookedMinutes: booked,
      capacityMinutes: capacity,
      chairs: chairCount,
      chairsSet: allSet && chairCount > 0,
      regulars: wholeView && forecast.ready ? forecast.regulars : null,
      regularsOverdue: wholeView ? forecast.atRiskTotal : 0,
      regularsMissing: wholeView && !forecast.ready
          ? 'Starts with the forecasts on ${_date(forecast.startsOn)}'
          : null,
      checks: wholeView ? checks : null,
      discount: discount,
      billed: billed,
      removals: removals,
    );
  }

  HubScore scoreFor(String? b, DateTime? first, {required bool wholeView}) {
    final now30 = stretch(b, ago(30), d0, first, wholeView: wholeView);
    final before = stretch(
      b,
      ago(60),
      ago(30),
      first,
      wholeView: wholeView,
    ).withStateOf(now30);
    DateTime? complete;
    if (now30.usual == null && first != null) {
      complete = DateTime(first.year, first.month, first.day + 60);
    }
    if (wholeView && !forecast.ready) {
      if (complete == null || forecast.startsOn.isAfter(complete)) {
        complete = forecast.startsOn;
      }
    }
    return hubScore(now30, before: before, completeOn: complete);
  }

  final viewFirst = await firstDay(branchId);
  final clinicInputs = stretch(
    branchId,
    ago(30),
    d0,
    viewFirst,
    wholeView: true,
  );
  final clinic = scoreFor(branchId, viewFirst, wholeView: true);

  final perBranch = <String, HubScore>{};
  if (branchId == null && allBranches.length > 1) {
    for (final b in allBranches) {
      perBranch[b.uuid] = scoreFor(
        b.uuid,
        await firstDay(b.uuid),
        wholeView: false,
      );
    }
  }

  return HubScores(
    clinic: clinic,
    branches: perBranch,
    chairs: chairs,
    inputs: clinicInputs,
  );
}
