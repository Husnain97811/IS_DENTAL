import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/cash/data/cash_repository.dart';

import 'hub_forecast.dart';
import 'hub_score.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  What if — try a decision before making it. Starts from the next 30 days
//  as What's coming expects them, then adds the effect of each change.
//  Every number comes from this clinic's own records.
// ═══════════════════════════════════════════════════════════════════════════

/// Settings key for the saved scenarios (JSON list, at most 3).
const kWhatIfSavedKey = 'hub_whatif_saved';
const kWhatIfMaxSaved = 3;

/// A procedure as it was billed over the last 90 days.
class HubProc {
  const HubProc({
    required this.key,
    required this.name,
    required this.perMonth,
    required this.avgPrice,
    required this.samples,
    this.listPrice,
  });

  /// Lower-case name — how bills are matched.
  final String key;
  final String name;

  /// Times done per 30 days.
  final double perMonth;

  /// What one usually costs the patient, after discounts.
  final double avgPrice;

  /// Times done in the 90 days (fewer than 5 = thin).
  final int samples;

  /// Price in the procedure list, when the name matches.
  final int? listPrice;

  double get monthly => perMonth * avgPrice;
}

/// A dentist's share of the money, from the last 90 days.
class HubDentistShare {
  const HubDentistShare({
    required this.key,
    required this.name,
    required this.perMonth,
    required this.percent,
  });

  final String key, name;

  /// Collected for their work per 30 days.
  final double perMonth;

  /// Commission % today.
  final double percent;
}

class HubWhatIfBase {
  const HubWhatIfBase({
    required this.ready,
    required this.startsOn,
    required this.dataDays,
    this.confidence = 0,
    this.in30 = 0,
    this.out30 = 0,
    this.commissionRate = 0,
    this.collectRate = 1,
    this.procs = const [],
    this.dentists = const [],
    this.closedWeekdays = const {},
    this.openDayMean = 0,
    this.weekdaysAhead = const [0, 0, 0, 0, 0, 0, 0],
    this.capacityMinutes = 0,
    this.bookedMinutes = 0,
    this.collected30 = 0,
    this.chairs = 0,
    this.chairsSet = false,
  });

  /// False until What's coming has enough history.
  final bool ready;
  final DateTime startsOn;
  final int dataDays;
  final int confidence;

  /// Expected next 30 days (What's coming).
  final int in30, out30;

  /// Commission as a share of everything collected (0–1).
  final double commissionRate;

  /// Share of what is billed that gets paid (0–1).
  final double collectRate;

  /// Most money first.
  final List<HubProc> procs;
  final List<HubDentistShare> dentists;

  /// Weekdays 1 (Mon) – 7 (Sun) the clinic is closed.
  final Set<int> closedWeekdays;

  /// What an open day usually brings in.
  final double openDayMean;

  /// How many of each weekday fall in the next 30 days (index 0 = Mon).
  final List<int> weekdaysAhead;

  /// Last 30 days: opening hours x chairs, and booked time (minutes).
  final int capacityMinutes, bookedMinutes;
  final int collected30;
  final int chairs;
  final bool chairsSet;

  int get commission30 => (in30 * commissionRate).round();
  int get profit30 => in30 - commission30 - out30;

  /// Free chair time over 30 days, in hours.
  double get freeHours => math.max(0, capacityMinutes - bookedMinutes) / 60.0;

  /// Money one booked chair-hour brings in.
  double get perChairHour =>
      bookedMinutes <= 0 ? 0.0 : collected30 / (bookedMinutes / 60.0);

  double get avgPercent => commissionRate * 100;
}

/// The owner's choices. Each change has its own on/off.
class HubWhatIf {
  const HubWhatIf({
    this.priceOn = false,
    this.procKey,
    this.priceChange = .1,
    this.lost = 0,
    this.rateOn = false,
    this.dentistKey,
    this.newPercent,
    this.dayOn = false,
    this.weekday,
    this.ramp = .5,
    this.staffPerDay = 0,
    this.dentistOn = false,
    this.fill = .3,
    this.dentistPercent = 40,
    this.dentistFixed = 0,
    this.expenseOn = false,
    this.expenseChange = 0,
  });

  // procedure price
  final bool priceOn;
  final String? procKey;

  /// −0.30 … +0.50
  final double priceChange;

  /// Patients lost because of it, 0 … 0.30.
  final double lost;

  // dentist commission
  final bool rateOn;
  final String? dentistKey;
  final double? newPercent;

  // an extra open day
  final bool dayOn;
  final int? weekday;

  /// How busy the new day gets compared with a usual day (0.2 … 1).
  final double ramp;
  final int staffPerDay;

  // one more dentist
  final bool dentistOn;

  /// Share of the free chair time they fill (0.1 … 1).
  final double fill;
  final double dentistPercent;

  /// Fixed monthly pay on top of commission.
  final int dentistFixed;

  // expenses
  final bool expenseOn;

  /// Per month; more spending is positive.
  final int expenseChange;

  bool get anyOn => priceOn || rateOn || dayOn || dentistOn || expenseOn;

  HubWhatIf copyWith({
    bool? priceOn,
    String? procKey,
    double? priceChange,
    double? lost,
    bool? rateOn,
    String? dentistKey,
    double? newPercent,
    bool? dayOn,
    int? weekday,
    double? ramp,
    int? staffPerDay,
    bool? dentistOn,
    double? fill,
    double? dentistPercent,
    int? dentistFixed,
    bool? expenseOn,
    int? expenseChange,
  }) => HubWhatIf(
    priceOn: priceOn ?? this.priceOn,
    procKey: procKey ?? this.procKey,
    priceChange: priceChange ?? this.priceChange,
    lost: lost ?? this.lost,
    rateOn: rateOn ?? this.rateOn,
    dentistKey: dentistKey ?? this.dentistKey,
    newPercent: newPercent ?? this.newPercent,
    dayOn: dayOn ?? this.dayOn,
    weekday: weekday ?? this.weekday,
    ramp: ramp ?? this.ramp,
    staffPerDay: staffPerDay ?? this.staffPerDay,
    dentistOn: dentistOn ?? this.dentistOn,
    fill: fill ?? this.fill,
    dentistPercent: dentistPercent ?? this.dentistPercent,
    dentistFixed: dentistFixed ?? this.dentistFixed,
    expenseOn: expenseOn ?? this.expenseOn,
    expenseChange: expenseChange ?? this.expenseChange,
  );

  Map<String, Object?> toJson() => {
    'priceOn': priceOn,
    'procKey': procKey,
    'priceChange': priceChange,
    'lost': lost,
    'rateOn': rateOn,
    'dentistKey': dentistKey,
    'newPercent': newPercent,
    'dayOn': dayOn,
    'weekday': weekday,
    'ramp': ramp,
    'staffPerDay': staffPerDay,
    'dentistOn': dentistOn,
    'fill': fill,
    'dentistPercent': dentistPercent,
    'dentistFixed': dentistFixed,
    'expenseOn': expenseOn,
    'expenseChange': expenseChange,
  };

  factory HubWhatIf.fromJson(Map<String, dynamic> j) {
    double dbl(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    int whole(String k) => (j[k] as num?)?.round() ?? 0;
    bool on(String k) => j[k] == true;
    return HubWhatIf(
      priceOn: on('priceOn'),
      procKey: j['procKey'] as String?,
      priceChange: dbl('priceChange', .1).clamp(-.3, .5).toDouble(),
      lost: dbl('lost', 0).clamp(0.0, .3).toDouble(),
      rateOn: on('rateOn'),
      dentistKey: j['dentistKey'] as String?,
      newPercent: (j['newPercent'] as num?)?.toDouble(),
      dayOn: on('dayOn'),
      weekday: (j['weekday'] as num?)?.round(),
      ramp: dbl('ramp', .5).clamp(.2, 1.0).toDouble(),
      staffPerDay: whole('staffPerDay'),
      dentistOn: on('dentistOn'),
      fill: dbl('fill', .3).clamp(.1, 1.0).toDouble(),
      dentistPercent: dbl('dentistPercent', 40).clamp(0.0, 100.0).toDouble(),
      dentistFixed: whole('dentistFixed'),
      expenseOn: on('expenseOn'),
      expenseChange: whole('expenseChange'),
    );
  }
}

/// A named scenario kept on this computer.
class HubSavedWhatIf {
  const HubSavedWhatIf(this.name, this.choices);
  final String name;
  final HubWhatIf choices;

  Map<String, Object?> toJson() => {'name': name, 'choices': choices.toJson()};

  static List<HubSavedWhatIf> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map<String, dynamic> && e['choices'] is Map<String, dynamic>)
            HubSavedWhatIf(
              '${e['name'] ?? 'Scenario'}',
              HubWhatIf.fromJson(e['choices'] as Map<String, dynamic>),
            ),
      ];
    } catch (_) {
      return const []; // a damaged value never breaks the page
    }
  }

  static String encode(List<HubSavedWhatIf> list) =>
      jsonEncode([for (final s in list) s.toJson()]);
}

enum HubWhatIfKind { price, rate, day, dentist, expense }

/// The effect of one change on the next 30 days' profit.
class HubWhatIfLine {
  const HubWhatIfLine({
    required this.kind,
    required this.label,
    required this.delta,
    required this.how,
    this.warning,
  });

  final HubWhatIfKind kind;
  final String label;

  /// Change in profit over 30 days.
  final int delta;
  final String how;

  /// Set when the number rests on thin data.
  final String? warning;
}

class HubWhatIfResult {
  const HubWhatIfResult({required this.base, required this.lines});

  final int base;
  final List<HubWhatIfLine> lines;

  int get change => lines.fold(0, (s, l) => s + l.delta);
  int get result => base + change;
  List<String> get warnings => [
    for (final l in lines)
      if (l.warning != null) l.warning!,
  ];
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
String hubWeekdayName(int weekday) => _weekdayNames[(weekday - 1) % 7];

String _rs(num v) {
  final r = v.round();
  final s = r.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${r < 0 ? '-' : ''}Rs $s';
}

String _signed(num v) => v.round() >= 0 ? '+${_rs(v)}' : _rs(v);

String _pct(double x) {
  final p = x * 100;
  return p == p.roundToDouble() ? '${p.round()}%' : '${p.toStringAsFixed(1)}%';
}

/// The effect of the owner's choices on the next 30 days.
HubWhatIfResult hubWhatIf(HubWhatIfBase b, HubWhatIf w) {
  final lines = <HubWhatIfLine>[];
  final keep = 1 - b.commissionRate; // what stays with the clinic

  // ── procedure price ──
  final proc = b.procs.where((p) => p.key == w.procKey).firstOrNull;
  if (w.priceOn && proc != null) {
    final now = proc.perMonth * proc.avgPrice;
    final after =
        proc.perMonth * (1 - w.lost) * proc.avgPrice * (1 + w.priceChange);
    final delta = (after - now) * b.collectRate * keep;
    final sign = w.priceChange >= 0 ? '+' : '';
    lines.add(
      HubWhatIfLine(
        kind: HubWhatIfKind.price,
        label: '${proc.name} price $sign${_pct(w.priceChange)}',
        delta: delta.round(),
        how:
            '${proc.name} was done about ${proc.perMonth.toStringAsFixed(1)} '
            'times a month at ${_rs(proc.avgPrice)} each (after discounts). '
            '${w.lost > 0 ? 'With ${_pct(w.lost)} fewer patients, ' : 'With the same number of patients, '}'
            'the new price changes the month\'s bills by ${_signed(after - now)}; '
            '${_pct(b.collectRate)} of bills usually get paid, and after '
            '${_pct(b.commissionRate)} commission that is '
            '${_signed(delta)} for the clinic.',
        warning: proc.samples < 5
            ? '${proc.name} was done only ${proc.samples} times in 90 days, '
                  'so its price change is a rough guide.'
            : null,
      ),
    );
  }

  // ── a dentist's commission ──
  final dentist = b.dentists.where((d) => d.key == w.dentistKey).firstOrNull;
  if (w.rateOn && dentist != null && w.newPercent != null) {
    final delta = dentist.perMonth * (dentist.percent - w.newPercent!) / 100;
    lines.add(
      HubWhatIfLine(
        kind: HubWhatIfKind.rate,
        label:
            '${dentist.name} commission ${_pct(dentist.percent / 100)} to '
            '${_pct(w.newPercent! / 100)}',
        delta: delta.round(),
        how:
            '${dentist.name} brings in about ${_rs(dentist.perMonth)} a month. '
            'Each 1% of commission is ${_rs(dentist.perMonth / 100)} a month.',
        warning: dentist.perMonth < 1000
            ? 'Very little money was linked to ${dentist.name}\'s visits in '
                  '90 days.'
            : null,
      ),
    );
  }

  // ── an extra open day ──
  final day = w.weekday;
  if (w.dayOn && day != null && b.closedWeekdays.contains(day)) {
    final count = b.weekdaysAhead[(day - 1) % 7];
    final perDay = b.openDayMean * w.ramp;
    final income = perDay * count;
    final delta = income * keep - w.staffPerDay * count;
    lines.add(
      HubWhatIfLine(
        kind: HubWhatIfKind.day,
        label: 'Open on ${hubWeekdayName(day)}s',
        delta: delta.round(),
        how:
            'A usual open day brings in ${_rs(b.openDayMean)}. At '
            '${_pct(w.ramp)} of that, $count ${hubWeekdayName(day)}s in the '
            'next 30 days bring ${_rs(income)}; after '
            '${_pct(b.commissionRate)} commission'
            '${w.staffPerDay > 0 ? ' and ${_rs(w.staffPerDay)} a day for staff' : ''}'
            ', the clinic keeps ${_rs(delta)}.',
        warning:
            'You have never opened on ${hubWeekdayName(day)}s, so how busy '
            'they get is your guess (${_pct(w.ramp)} of a usual day).',
      ),
    );
  }

  // ── one more dentist ──
  if (w.dentistOn) {
    final hours = b.freeHours * w.fill;
    final income = hours * b.perChairHour;
    final delta =
        income * b.collectRate * (1 - w.dentistPercent / 100) - w.dentistFixed;
    lines.add(
      HubWhatIfLine(
        kind: HubWhatIfKind.dentist,
        label: 'Add a dentist',
        delta: delta.round(),
        how:
            'Your chairs had ${b.freeHours.round()} free hours in the last 30 '
            'days. Filling ${_pct(w.fill)} of them at ${_rs(b.perChairHour)} '
            'an hour (what a booked hour brings in now) is ${_rs(income)}; '
            'after ${_pct(b.collectRate)} getting paid, '
            '${_pct(w.dentistPercent / 100)} commission'
            '${w.dentistFixed > 0 ? ' and ${_rs(w.dentistFixed)} fixed pay' : ''}'
            ', the clinic keeps ${_rs(delta)}.',
        warning: b.freeHours < 10
            ? 'Your chairs are nearly full, so a new dentist needs another '
                  'chair or longer hours.'
            : (!b.chairsSet
                  ? 'Chairs are worked out from your bookings (${b.chairs}). '
                        'Set the real number in the health score to be sure.'
                  : null),
      ),
    );
  }

  // ── expenses ──
  if (w.expenseOn && w.expenseChange != 0) {
    lines.add(
      HubWhatIfLine(
        kind: HubWhatIfKind.expense,
        label: w.expenseChange > 0
            ? 'Spend ${_rs(w.expenseChange)} more a month'
            : 'Spend ${_rs(-w.expenseChange)} less a month',
        delta: -w.expenseChange,
        how: 'Taken straight off (or added to) the month\'s profit.',
      ),
    );
  }

  return HubWhatIfResult(base: b.profit30, lines: lines);
}

// ─────────────────────────────── loader ───────────────────────────────────

/// Normalised procedure key: trimmed, single spaces, lower case.
String hubProcKey(String s) =>
    s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Future<HubWhatIfBase> loadHubWhatIf({
  required AppDatabase db,
  required CashRepository cash,
  required String? branchId,
  required HubForecast forecast,
  required HubScores scores,
}) async {
  if (!forecast.ready) {
    return HubWhatIfBase(
      ready: false,
      startsOn: forecast.startsOn,
      dataDays: forecast.dataDays,
    );
  }
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  final from = DateTime(d0.year, d0.month, d0.day - 90);
  // shorter when the clinic has less than 90 days of records
  final span = math.min(90, math.max(1, forecast.dataDays));
  final perMonth = 30 / span;

  Expression<bool> inScope(GeneratedColumn<String> c) =>
      branchId == null ? const Constant(true) : c.equals(branchId);

  // ── bills and their lines ──
  final bills =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                t.issuedAt.isBiggerOrEqualValue(from) &
                t.issuedAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();
  final billOf = {for (final i in bills) i.id: i};
  final items = <InvoiceItemRow>[];
  final ids = billOf.keys.toList();
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, math.min(i + 500, ids.length));
    items.addAll(
      await (db.select(
        db.invoiceItems,
      )..where((t) => t.invoiceId.isIn(chunk))).get(),
    );
  }
  final linesOf = <int, List<InvoiceItemRow>>{};
  for (final it in items) {
    (linesOf[it.invoiceId] ??= []).add(it);
  }

  final catalog = {
    for (final t in await (db.select(
      db.treatments,
    )..where((t) => t.isDeleted.equals(false))).get())
      hubProcKey(t.name): t.price,
  };

  final units = <String, int>{};
  final money = <String, double>{};
  final names = <String, String>{};
  for (final e in linesOf.entries) {
    final inv = billOf[e.key]!;
    final lines = e.value;
    int qty(InvoiceItemRow it) => it.qty < 1 ? 1 : it.qty;
    // A line's amount is normally its total; older bills may hold the
    // price of one — whichever adds up to the bill's subtotal wins.
    final asTotal = lines.fold<int>(0, (s, it) => s + it.amount);
    final asEach = lines.fold<int>(0, (s, it) => s + it.amount * qty(it));
    final each = asTotal != inv.subtotal && asEach == inv.subtotal;
    // share the bill's discount across its lines
    final factor = inv.subtotal > 0 ? inv.total / inv.subtotal : 1.0;
    for (final it in lines) {
      final name = it.description.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty) continue;
      final k = hubProcKey(name);
      final total = each ? it.amount * qty(it) : it.amount;
      units[k] = (units[k] ?? 0) + qty(it);
      money[k] = (money[k] ?? 0.0) + total * factor;
      names.putIfAbsent(k, () => name);
    }
  }
  final procs = [
    for (final k in units.keys)
      if ((money[k] ?? 0.0) > 0)
        HubProc(
          key: k,
          name: names[k]!,
          perMonth: units[k]! * perMonth,
          avgPrice: money[k]! / units[k]!,
          samples: units[k]!,
          listPrice: catalog[k],
        ),
  ]..sort((a, b) => b.monthly.compareTo(a.monthly));

  // ── what gets paid, and commission ──
  final pays =
      await (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(from) &
                t.paidAt.isSmallerThanValue(d0) &
                inScope(t.branchId),
          ))
          .get();
  final collected90 = pays.fold<int>(0, (s, p) => s + p.amount);
  final billed90 = bills.fold<int>(0, (s, i) => s + i.total);
  final collectRate = billed90 <= 0
      ? 1.0
      : math.min(1.0, collected90 / billed90);

  bool inRange(DateTime t) => !t.isBefore(from) && t.isBefore(d0);
  final got = <String, int>{};
  final pct = <String, double>{};
  final who = <String, String>{};
  for (
    var m = DateTime(from.year, from.month, 1);
    m.isBefore(d0);
    m = DateTime(m.year, m.month + 1, 1)
  ) {
    final sheet = await cash.commission(m, branchId);
    for (final l in sheet.lines) {
      if (l.unassigned) continue;
      final k = dentistKey(l.dentist);
      got[k] =
          (got[k] ?? 0) +
          l.payments
              .where((x) => inRange(x.paidAt))
              .fold<int>(0, (s, x) => s + x.amount);
      pct[k] = l.percent; // months run oldest first → today's rate wins
      who[k] = l.dentist;
    }
  }
  var commission = 0.0;
  for (final k in got.keys) {
    commission += got[k]! * (pct[k] ?? 0.0) / 100;
  }
  final dentists = [
    for (final k in got.keys)
      if (got[k]! > 0)
        HubDentistShare(
          key: k,
          name: who[k]!,
          perMonth: got[k]! * perMonth,
          percent: pct[k] ?? 0.0,
        ),
  ]..sort((a, b) => b.perMonth.compareTo(a.perMonth));

  // ── open days ──
  final open = [
    for (var w = 1; w <= 7; w++)
      if (!forecast.closedWeekdays.contains(w) &&
          forecast.weekdayMean.length >= w &&
          forecast.weekdayMean[w - 1] > 0)
        forecast.weekdayMean[w - 1],
  ];
  final ahead = List<int>.filled(7, 0);
  for (var i = 0; i < 30; i++) {
    ahead[DateTime(d0.year, d0.month, d0.day + i).weekday - 1]++;
  }

  final s = scores.inputs;
  return HubWhatIfBase(
    ready: true,
    startsOn: forecast.startsOn,
    dataDays: forecast.dataDays,
    confidence: forecast.confidence,
    in30: forecast.in30,
    out30: forecast.out30,
    commissionRate: collected90 <= 0 ? 0.0 : commission / collected90,
    collectRate: collectRate,
    procs: procs,
    dentists: dentists,
    closedWeekdays: forecast.closedWeekdays,
    openDayMean: open.isEmpty
        ? 0.0
        : open.reduce((a, b) => a + b) / open.length,
    weekdaysAhead: ahead,
    capacityMinutes: s.capacityMinutes,
    bookedMinutes: s.bookedMinutes,
    collected30: s.collected,
    chairs: scores.chairCount,
    chairsSet: scores.chairsAllSet,
  );
}
