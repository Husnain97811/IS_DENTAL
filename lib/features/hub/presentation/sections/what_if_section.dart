import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../../data/hub_forecast.dart';
import '../../data/hub_whatif.dart';
import '../widgets/hub_ui.dart';

/// What if — change a price, a commission, the open days, add a dentist or
/// change spending, and see next 30 days' profit move.
class WhatIfSection extends ConsumerStatefulWidget {
  const WhatIfSection({super.key, required this.data});
  final HubData data;

  @override
  ConsumerState<WhatIfSection> createState() => _WhatIfSectionState();
}

class _WhatIfSectionState extends ConsumerState<WhatIfSection> {
  late HubWhatIf _w = _blank();
  List<HubSavedWhatIf> _saved = const [];
  bool _savingList = false;

  /// "Spend less" picked — kept apart from the amount, which may still be 0.
  bool _less = false;

  final _staff = TextEditingController();
  final _fixed = TextEditingController();
  final _expense = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _staff.dispose();
    _fixed.dispose();
    _expense.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final raw = await ref
          .read(appDatabaseProvider)
          .getSetting(kWhatIfSavedKey);
      if (mounted) setState(() => _saved = HubSavedWhatIf.decode(raw));
    } catch (_) {
      // nothing saved, or the setting can't be read — the page still works
    }
  }

  Future<void> _storeSaved(List<HubSavedWhatIf> list) async {
    setState(() => _savingList = true);
    try {
      await ref
          .read(appDatabaseProvider)
          .setSetting(kWhatIfSavedKey, HubSavedWhatIf.encode(list));
      if (mounted) setState(() => _saved = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingList = false);
    }
  }

  /// Fills empty picks with sensible starting values, and drops picks that
  /// no longer exist (another branch picked at the top).
  HubWhatIf _fill(HubWhatIf w, HubWhatIfBase b) {
    final proc = b.procs.any((p) => p.key == w.procKey)
        ? w.procKey
        : b.procs.firstOrNull?.key;
    final dentist =
        b.dentists.where((x) => x.key == w.dentistKey).firstOrNull ??
        b.dentists.firstOrNull;
    final closed = b.closedWeekdays.toList()..sort();
    final day = closed.contains(w.weekday) ? w.weekday : closed.firstOrNull;
    return HubWhatIf(
      priceOn: w.priceOn && proc != null,
      procKey: proc,
      priceChange: w.priceChange,
      lost: w.lost,
      rateOn: w.rateOn && dentist != null,
      dentistKey: dentist?.key,
      newPercent: dentist == null
          ? null
          : (w.dentistKey == dentist.key && w.newPercent != null
                ? w.newPercent
                : dentist.percent),
      dayOn: w.dayOn && day != null,
      weekday: day,
      ramp: w.ramp,
      staffPerDay: w.staffPerDay,
      dentistOn: w.dentistOn,
      fill: w.fill,
      dentistPercent: w.dentistPercent,
      dentistFixed: w.dentistFixed,
      expenseOn: w.expenseOn,
      expenseChange: w.expenseChange,
    );
  }

  void _set(HubWhatIf w) => setState(() => _w = w);

  /// Nothing switched on; a new dentist starts at the clinic's usual rate.
  HubWhatIf _blank() {
    final avg = widget.data.whatIf.avgPercent;
    return HubWhatIf(dentistPercent: avg > 0 ? avg.roundToDouble() : 40);
  }

  void _reset() {
    _staff.clear();
    _fixed.clear();
    _expense.clear();
    setState(() {
      _less = false;
      _w = _blank();
    });
  }

  void _apply(HubWhatIf w) {
    _staff.text = w.staffPerDay > 0 ? hubDigits(w.staffPerDay) : '';
    _fixed.text = w.dentistFixed > 0 ? hubDigits(w.dentistFixed) : '';
    _expense.text = w.expenseChange != 0 ? hubDigits(w.expenseChange) : '';
    setState(() {
      _less = w.expenseChange < 0;
      _w = w;
    });
  }

  Future<void> _saveAs(HubWhatIf w) async {
    if (_saved.length >= kWhatIfMaxSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can keep 3 scenarios. Remove one first.'),
        ),
      );
      return;
    }
    final d = context.dent;
    final field = TextEditingController(text: 'Scenario ${_saved.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        void submit() {
          final v = field.text.trim();
          if (v.isNotEmpty) Navigator.of(dialogCtx).pop(v);
        }

        return AlertDialog(
          backgroundColor: d.surface,
          title: Text(
            'Save this scenario',
            style: TextStyle(color: d.text1, fontSize: 13.sp),
          ),
          content: TextField(
            controller: field,
            autofocus: true,
            maxLength: 40,
            style: TextStyle(color: d.text1, fontSize: 11.sp),
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Saturday opening',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('Cancel', style: TextStyle(fontSize: 10.sp)),
            ),
            FilledButton(
              onPressed: submit,
              child: Text('Save', style: TextStyle(fontSize: 10.sp)),
            ),
          ],
        );
      },
    );
    field.dispose();
    if (name == null || !mounted) return;
    await _storeSaved([..._saved, HubSavedWhatIf(name, w)]);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final b = widget.data.whatIf;
    if (!b.ready) return _NotYet(b: b);

    final w = _fill(_w, b);
    final r = hubWhatIf(b, w);
    HubWhatIfLine? line(HubWhatIfKind k) =>
        r.lines.where((l) => l.kind == k).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: 'What if',
          subtitle:
              'Try a decision before you make it · next 30 days, worked out '
              'from your own records',
          trailing: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: w.anyOn ? _reset : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(
                  'Reset',
                  style: TextStyle(
                    fontSize: 9.8.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: w.anyOn && !_savingList ? () => _saveAs(w) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                ),
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(
                  'Save scenario',
                  style: TextStyle(
                    fontSize: 9.8.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_saved.isNotEmpty) ...[
          _SavedBar(
            saved: _saved,
            onOpen: (s) => _apply(_fill(s.choices, b)),
            onRemove: (s) => _storeSaved([
              for (final x in _saved)
                if (!identical(x, s)) x,
            ]),
          ),
          const SizedBox(height: 14),
        ],
        _Result(b: b, r: r),
        const SizedBox(height: 18),
        HubGrid(
          minWidth: 380,
          maxColumns: 3,
          equalHeight: false,
          children: [
            _priceCard(b, w, line(HubWhatIfKind.price)),
            _rateCard(b, w, line(HubWhatIfKind.rate)),
            _dayCard(b, w, line(HubWhatIfKind.day)),
            _dentistCard(b, w, line(HubWhatIfKind.dentist)),
            _expenseCard(w, line(HubWhatIfKind.expense)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Changes are added together and nothing here is saved to your '
          'records. Saved scenarios stay on this computer. The branch picked '
          'at the top applies.',
          style: TextStyle(color: d.text4, fontSize: 9.sp, height: 1.4),
        ),
      ],
    );
  }

  // ───────────────────────────── the five cards ─────────────────────────────

  Widget _priceCard(HubWhatIfBase b, HubWhatIf w, HubWhatIfLine? l) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final proc = b.procs.where((p) => p.key == w.procKey).firstOrNull;
    if (proc == null) {
      return _Control(
        icon: Icons.sell_outlined,
        tone: d.ice,
        title: 'Change a price',
        subtitle: 'Raise or lower one procedure',
        on: false,
        emptyText: 'No procedures were billed in the last 90 days.',
      );
    }
    final newPrice = proc.avgPrice * (1 + w.priceChange);
    return _Control(
      icon: Icons.sell_outlined,
      tone: d.ice,
      title: 'Change a price',
      subtitle: 'Raise or lower one procedure',
      on: w.priceOn,
      onToggle: (v) => _set(w.copyWith(priceOn: v)),
      line: l,
      children: [
        _Picker<String>(
          value: proc.key,
          items: [
            for (final p in b.procs)
              (p.key, '${p.name} · ${p.perMonth.toStringAsFixed(1)} a month'),
          ],
          onChanged: (k) => _set(w.copyWith(procKey: k, priceOn: true)),
        ),
        const SizedBox(height: 8),
        _Note(
          'Now ${hubRs(proc.avgPrice.round(), hidden: hidden)} each after '
          'discounts${proc.listPrice == null ? '' : ' (list price ${hubRs(proc.listPrice!, hidden: hidden)})'}',
        ),
        _SliderRow(
          label: 'Price change',
          valueText:
              '${w.priceChange >= 0 ? '+' : ''}${(w.priceChange * 100).round()}% '
              '· ${hubRs(newPrice.round(), hidden: hidden)}',
          value: w.priceChange,
          min: -.3,
          max: .5,
          divisions: 16,
          onChanged: (v) => _set(w.copyWith(priceChange: v, priceOn: true)),
        ),
        _SliderRow(
          label: 'Patients lost because of it',
          valueText: w.lost == 0
              ? 'None (same patients)'
              : '${(w.lost * 100).round()}%',
          value: w.lost,
          min: 0,
          max: .3,
          divisions: 30,
          onChanged: (v) => _set(w.copyWith(lost: v, priceOn: true)),
        ),
      ],
    );
  }

  Widget _rateCard(HubWhatIfBase b, HubWhatIf w, HubWhatIfLine? l) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final x = b.dentists.where((e) => e.key == w.dentistKey).firstOrNull;
    if (x == null) {
      return _Control(
        icon: Icons.percent_rounded,
        tone: d.teal,
        title: "Change a dentist's commission",
        subtitle: 'Their share of what they bring in',
        on: false,
        emptyText:
            'No payments were linked to a dentist in the last 90 days. Link '
            'bills to visits to use this.',
      );
    }
    final pct = w.newPercent ?? x.percent;
    final top = math.max(70.0, x.percent.ceilToDouble());
    return _Control(
      icon: Icons.percent_rounded,
      tone: d.teal,
      title: "Change a dentist's commission",
      subtitle: 'Their share of what they bring in',
      on: w.rateOn,
      onToggle: (v) => _set(w.copyWith(rateOn: v)),
      line: l,
      children: [
        _Picker<String>(
          value: x.key,
          items: [
            for (final e in b.dentists)
              (e.key, '${e.name} · ${_pctText(e.percent)} now'),
          ],
          onChanged: (k) {
            final n = b.dentists.firstWhere((e) => e.key == k);
            _set(
              w.copyWith(dentistKey: k, newPercent: n.percent, rateOn: true),
            );
          },
        ),
        const SizedBox(height: 8),
        _Note(
          'Brings in about ${hubRs(x.perMonth.round(), hidden: hidden)} a month',
        ),
        _SliderRow(
          label: 'New commission',
          valueText: '${_pctText(pct)} (now ${_pctText(x.percent)})',
          value: pct.clamp(0, top).toDouble(),
          min: 0,
          max: top,
          divisions: top.round(),
          onChanged: (v) =>
              _set(w.copyWith(newPercent: v.roundToDouble(), rateOn: true)),
        ),
      ],
    );
  }

  Widget _dayCard(HubWhatIfBase b, HubWhatIf w, HubWhatIfLine? l) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final closed = b.closedWeekdays.toList()..sort();
    if (closed.isEmpty || w.weekday == null) {
      return _Control(
        icon: Icons.event_available_outlined,
        tone: d.warn,
        title: 'Open an extra day',
        subtitle: 'A day you are closed now',
        on: false,
        emptyText: 'You are open every day of the week.',
      );
    }
    return _Control(
      icon: Icons.event_available_outlined,
      tone: d.warn,
      title: 'Open an extra day',
      subtitle: 'A day you are closed now',
      on: w.dayOn,
      onToggle: (v) => _set(w.copyWith(dayOn: v)),
      line: l,
      children: [
        _Picker<int>(
          value: w.weekday!,
          items: [
            for (final c in closed)
              (
                c,
                '${hubWeekdayName(c)}s · ${b.weekdaysAhead[c - 1]} in the next 30 days',
              ),
          ],
          onChanged: (v) => _set(w.copyWith(weekday: v, dayOn: true)),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'How busy, against a usual day',
          valueText:
              '${(w.ramp * 100).round()}% · '
              '${hubRs((b.openDayMean * w.ramp).round(), hidden: hidden)} a day',
          value: w.ramp,
          min: .2,
          max: 1,
          divisions: 16,
          onChanged: (v) => _set(w.copyWith(ramp: v, dayOn: true)),
        ),
        _AmountField(
          controller: _staff,
          label: 'Extra staff cost per day',
          onChanged: (v) => _set(w.copyWith(staffPerDay: v, dayOn: true)),
        ),
      ],
    );
  }

  Widget _dentistCard(HubWhatIfBase b, HubWhatIf w, HubWhatIfLine? l) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    return _Control(
      icon: Icons.person_add_alt_1_outlined,
      tone: d.ok,
      title: 'Add a dentist',
      subtitle: 'Fill free chair time',
      on: w.dentistOn,
      onToggle: (v) => _set(w.copyWith(dentistOn: v)),
      line: l,
      children: [
        _Note(
          '${b.freeHours.round()} free chair hours in the last 30 days · '
          '${b.chairs} chair${b.chairs == 1 ? '' : 's'}'
          '${b.chairsSet ? '' : ' (worked out)'} · a booked hour brings '
          '${hubRs(b.perChairHour.round(), hidden: hidden)}',
        ),
        _SliderRow(
          label: 'Free time they fill',
          valueText:
              '${(w.fill * 100).round()}% · ${(b.freeHours * w.fill).round()} hours',
          value: w.fill,
          min: .1,
          max: 1,
          divisions: 18,
          onChanged: (v) => _set(w.copyWith(fill: v, dentistOn: true)),
        ),
        _SliderRow(
          label: 'Their commission',
          valueText: _pctText(w.dentistPercent),
          value: w.dentistPercent.clamp(0, 70).toDouble(),
          min: 0,
          max: 70,
          divisions: 70,
          onChanged: (v) => _set(
            w.copyWith(dentistPercent: v.roundToDouble(), dentistOn: true),
          ),
        ),
        _AmountField(
          controller: _fixed,
          label: 'Fixed monthly pay (if any)',
          onChanged: (v) => _set(w.copyWith(dentistFixed: v, dentistOn: true)),
        ),
      ],
    );
  }

  Widget _expenseCard(HubWhatIf w, HubWhatIfLine? l) {
    final d = context.dent;
    final more = !_less;
    final amount = w.expenseChange.abs();
    return _Control(
      icon: Icons.receipt_long_outlined,
      tone: d.alert,
      title: 'Change spending',
      subtitle: 'Rent, salaries, supplies — per month',
      on: w.expenseOn,
      onToggle: (v) => _set(w.copyWith(expenseOn: v)),
      line: l,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final up in [true, false])
              ChoiceChip(
                label: Text(
                  up ? 'Spend more' : 'Spend less',
                  style: TextStyle(
                    fontSize: 9.8.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                selected: more == up,
                selectedColor: (up ? d.alert : d.ok).withValues(alpha: .18),
                onSelected: (_) {
                  _less = !up;
                  _set(
                    w.copyWith(
                      expenseChange: up ? amount : -amount,
                      expenseOn: true,
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        _AmountField(
          controller: _expense,
          label: 'Amount per month',
          onChanged: (v) =>
              _set(w.copyWith(expenseChange: more ? v : -v, expenseOn: true)),
        ),
      ],
    );
  }
}

String _pctText(double p) =>
    p == p.roundToDouble() ? '${p.round()}%' : '${p.toStringAsFixed(1)}%';

// ───────────────────────────── result ─────────────────────────────

class _Result extends StatelessWidget {
  const _Result({required this.b, required this.r});
  final HubWhatIfBase b;
  final HubWhatIfResult r;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final change = r.change;
    final tone = change > 0
        ? d.ok
        : change < 0
        ? d.alert
        : d.text2;
    final big = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 20.sp,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );

    Widget figure(String label, int v, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: d.text3, fontSize: 9.6.sp),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            hubRs(v, hidden: hidden),
            style: big.copyWith(color: color),
          ),
        ),
      ],
    );

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EXPECTED PROFIT · NEXT 30 DAYS',
          style: TextStyle(
            color: d.text3,
            fontSize: 9.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: .9,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: figure('As things are', r.base, d.text1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward_rounded, color: d.text3),
            ),
            Expanded(
              child: figure(
                'With your changes',
                r.result,
                r.lines.isEmpty ? d.text3 : (r.result < 0 ? d.alert : tone),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HubPill(
          r.lines.isEmpty
              ? 'Switch on a change below to see its effect'
              : '${change >= 0 ? '+' : '–'} ${hubRs(change.abs(), hidden: hidden)} a month '
                    '(${r.base == 0 ? '—' : '${change >= 0 ? '+' : '–'}${(change.abs() / r.base.abs() * 100).round()}%'})',
          r.lines.isEmpty ? d.text3 : tone,
          maxLines: 2,
        ),
        if (r.warnings.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final w in r.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: d.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      w,
                      style: TextStyle(
                        color: d.text2,
                        fontSize: 9.4.sp,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: HubTwoUp(
              breakAt: 980,
              leftFlex: 5,
              rightFlex: 6,
              left: left,
              right: _Waterfall(r: r),
            ),
          ),
          HubHow(
            'What\'s coming expects ${hubRs(b.in30)} to come in over the '
            'next 30 days. At your usual ${_pctText(b.commissionRate * 100)} '
            'commission that is ${hubRs(b.commission30)} to dentists, and '
            'spending at your usual pace is ${hubRs(b.out30)}. That leaves '
            '${hubRs(b.profit30)}. Each change you switch on is added to it; '
            'its own "How we worked this out" is on its card. About '
            '${(b.collectRate * 100).round()}% of what you bill gets paid, '
            'which price changes and a new dentist take into account.',
          ),
        ],
      ),
    );
  }
}

/// Starting profit → each change → the result, as floating bars.
class _Waterfall extends StatelessWidget {
  const _Waterfall({required this.r});
  final HubWhatIfResult r;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final rows = <(String, int, int, Color, String)>[];
    rows.add((
      'As things are',
      0,
      r.base,
      d.ice,
      hubRs(r.base, hidden: hidden),
    ));
    var run = r.base;
    for (final l in r.lines) {
      rows.add((
        l.label,
        run,
        run + l.delta,
        l.delta >= 0 ? d.ok : d.alert,
        '${l.delta >= 0 ? '+' : '–'} ${hubRs(l.delta.abs(), hidden: hidden)}',
      ));
      run += l.delta;
    }
    if (r.lines.isNotEmpty) {
      rows.add((
        'With your changes',
        0,
        r.result,
        d.teal,
        hubRs(r.result, hidden: hidden),
      ));
    }
    var lo = 0, hi = 1;
    for (final x in rows) {
      lo = math.min(lo, math.min(x.$2, x.$3));
      hi = math.max(hi, math.max(x.$2, x.$3));
    }

    return Column(
      children: [
        for (final x in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    x.$1,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: d.text2,
                      fontSize: 9.4.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: SizedBox(
                    height: 22,
                    child: CustomPaint(
                      painter: _BarPainter(
                        from: x.$2,
                        to: x.$3,
                        lo: lo,
                        hi: hi,
                        color: x.$4,
                        zero: d.line,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: Text(
                    x.$5,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 9.6.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.from,
    required this.to,
    required this.lo,
    required this.hi,
    required this.color,
    required this.zero,
  });

  final int from, to, lo, hi;
  final Color color, zero;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (hi - lo).toDouble();
    double x(int v) => span <= 0 ? 0.0 : (v - lo) / span * size.width;
    // the zero line, when losses push the scale below it
    if (lo < 0) {
      canvas.drawLine(
        Offset(x(0), 0),
        Offset(x(0), size.height),
        Paint()
          ..color = zero
          ..strokeWidth = 1.5,
      );
    }
    final a = x(math.min(from, to)), b = x(math.max(from, to));
    final rect = Rect.fromLTRB(a, 3, math.max(b, a + 3), size.height - 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.from != from ||
      o.to != to ||
      o.lo != lo ||
      o.hi != hi ||
      o.color != color ||
      o.zero != zero;
}

// ───────────────────────────── building blocks ─────────────────────────────

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.on,
    this.onToggle,
    this.line,
    this.children = const [],
    this.emptyText,
  });

  final IconData icon;
  final Color tone;
  final String title, subtitle;
  final bool on;

  /// Null = this change can't be used (see [emptyText]).
  final ValueChanged<bool>? onToggle;
  final HubWhatIfLine? line;
  final List<Widget> children;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final l = line;
    return Container(
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: on ? tone.withValues(alpha: .55) : d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
            child: Row(
              children: [
                hubIconTile(d, icon, tone, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          color: d.text1,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(color: d.text3, fontSize: 9.2.sp),
                      ),
                    ],
                  ),
                ),
                Switch(value: on, onChanged: onToggle),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),
          if (onToggle == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Text(
                emptyText ?? '',
                style: TextStyle(
                  color: d.text3,
                  fontSize: 9.8.sp,
                  height: 1.45,
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
              child: Opacity(
                opacity: on ? 1 : .6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (l == null ? d.text4 : (l.delta >= 0 ? d.ok : d.alert))
                    .withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Profit, next 30 days',
                      style: TextStyle(color: d.text2, fontSize: 9.6.sp),
                    ),
                  ),
                  Text(
                    l == null
                        ? 'Switch on to see'
                        : '${l.delta >= 0 ? '+' : '–'} ${hubRs(l.delta.abs(), hidden: hidden)}',
                    style: TextStyle(
                      color: l == null
                          ? d.text3
                          : (l.delta >= 0 ? d.ok : d.alert),
                      fontSize: 10.6.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (l != null) HubHow(l.how) else const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(color: d.text3, fontSize: 9.4.sp, height: 1.4),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label, valueText;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: d.text2, fontSize: 9.6.sp),
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 9.8.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: d.ice,
              thumbColor: d.ice,
              inactiveTrackColor: d.line,
              overlayColor: d.ice.withValues(alpha: .12),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: d.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          menuMaxHeight: 380,
          dropdownColor: d.surface,
          borderRadius: BorderRadius.circular(12),
          icon: Icon(Icons.expand_more_rounded, size: 19, color: d.text3),
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.$1,
                child: Text(
                  i.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: d.text1, fontSize: 9.8.sp),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// "Rs ____" whole-rupee field; commas are fine, anything else is ignored.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
          LengthLimitingTextInputFormatter(11),
        ],
        style: TextStyle(color: d.text1, fontSize: 10.4.sp),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: d.text3, fontSize: 9.8.sp),
          prefixText: 'Rs ',
          prefixStyle: TextStyle(color: d.text3, fontSize: 10.4.sp),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: d.line),
          ),
        ),
        onChanged: (t) => onChanged(int.tryParse(t.replaceAll(',', '')) ?? 0),
      ),
    );
  }
}

class _SavedBar extends StatelessWidget {
  const _SavedBar({
    required this.saved,
    required this.onOpen,
    required this.onRemove,
  });

  final List<HubSavedWhatIf> saved;
  final ValueChanged<HubSavedWhatIf> onOpen;
  final ValueChanged<HubSavedWhatIf> onRemove;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Saved:',
          style: TextStyle(color: d.text3, fontSize: 9.6.sp),
        ),
        for (final s in saved)
          InputChip(
            avatar: Icon(Icons.bookmark_rounded, size: 16, color: d.ice),
            label: Text(
              s.name,
              style: TextStyle(
                color: d.text1,
                fontSize: 9.6.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            tooltip: 'Open "${s.name}"',
            onPressed: () => onOpen(s),
            onDeleted: () => onRemove(s),
            deleteButtonTooltipMessage: 'Remove',
          ),
      ],
    );
  }
}

class _NotYet extends StatelessWidget {
  const _NotYet({required this.b});
  final HubWhatIfBase b;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final have = b.dataDays.clamp(0, kForecastMinDays);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HubSectionTitle(
          title: 'What if',
          subtitle: 'Try a decision before you make it',
        ),
        HubCard(
          icon: Icons.science_outlined,
          tone: d.ice,
          title: 'What if starts on ${hubDate(b.startsOn)}',
          subtitle: 'It starts from the same forecasts as What\'s coming',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Testing a price, a commission or an extra day needs to '
                  'know your usual month first. Once there are '
                  '$kForecastMinDays days of payments and appointments, you '
                  'can try changes here and see the effect on profit.',
                  style: TextStyle(
                    color: d.text2,
                    fontSize: 10.2.sp,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: have / kForecastMinDays,
                          minHeight: 10,
                          backgroundColor: d.line,
                          valueColor: AlwaysStoppedAnimation(d.ice),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      '$have of $kForecastMinDays days',
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
