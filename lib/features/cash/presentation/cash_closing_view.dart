import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';
import 'package:sizer/sizer.dart';

import '../data/cash_repository.dart';

const _mon = [
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
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _m(int v) {
  final neg = v < 0;
  final s = v.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (x) => '${x[1]},',
  );
  return neg ? '-$s' : s;
}

String _prettyDay(DateTime d) =>
    '${_wd[d.weekday - 1]}, ${d.day} ${_mon[d.month - 1]} ${d.year}';

String _time(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

int _num(TextEditingController c) =>
    int.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

/// Pakistani notes, largest first. Coins are entered as one total.
const _notes = [5000, 1000, 500, 100, 50, 20, 10];

/// End-of-day cash count: expected vs counted, with the difference flagged.
class CashClosingView extends ConsumerStatefulWidget {
  const CashClosingView({super.key});

  @override
  ConsumerState<CashClosingView> createState() => _CashClosingViewState();
}

class _CashClosingViewState extends ConsumerState<CashClosingView> {
  DateTime _day = _today();
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  final _float = TextEditingController();
  final _counted = TextEditingController();
  final _taken = TextEditingController();
  final _note = TextEditingController();
  final _noteCtrls = {for (final n in _notes) n: TextEditingController()};
  final _coins = TextEditingController();

  List<({DateTime day, int cashPayments})> _missedBefore = const [];
  bool _byNotes = false;
  bool _saving = false;
  String? _filledFor; // the day the fields were last filled for
  String? _error;

  @override
  void initState() {
    super.initState();
    // Opened from the Dashboard's "not closed" card → jump to that day.
    final target = ref.read(dayCloseTargetProvider);
    if (target != null) {
      _day = parseDayKey(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(dayCloseTargetProvider.notifier).set(null);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _float,
      _counted,
      _taken,
      _note,
      _coins,
      ..._noteCtrls.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fill the fields once per day: from the saved closing, or suggestions.
  void _fill(CashDay cd) {
    final key = dayKey(cd.day);
    if (_filledFor == key) return;
    _filledFor = key;
    final c = cd.closing;
    _float.text = '${c?.openingFloat ?? cd.suggestedFloat}';
    _counted.text = c == null ? '' : '${c.counted}';
    _taken.text = c == null ? '' : '${c.takenOut}';
    _note.text = c?.note ?? '';
    for (final t in _noteCtrls.values) {
      t.clear();
    }
    _coins.clear();
    _byNotes = false;
    _error = null;
  }

  void _sumNotes() {
    var total = _num(_coins);
    _noteCtrls.forEach((n, c) => total += n * _num(c));
    _counted.text = total == 0 ? '' : '$total';
    setState(() {});
  }

  void _go(int days) => setState(() {
    final next = _day.add(Duration(days: days));
    if (!next.isAfter(_today())) _day = next;
  });

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: _today(),
    );
    if (picked != null && mounted) {
      setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save(CashDay cd) async {
    final counted = _num(_counted);
    final float = _num(_float);
    final diff = counted - cd.expectedWith(float);
    if (_counted.text.trim().isEmpty) {
      setState(() => _error = 'Enter the cash you counted.');
      return;
    }
    if (diff != 0 && _note.text.trim().isEmpty) {
      setState(
        () => _error =
            'The cash is ${diff < 0 ? 'short' : 'over'} — add a short note explaining why.',
      );
      return;
    }
    if (_num(_taken) > counted) {
      setState(() => _error = 'You can\'t take out more than you counted.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(cashRepositoryProvider)
          .close(
            cashDay: cd,
            branchId: ref.read(activeBranchProvider),
            openingFloat: float,
            counted: counted,
            takenOut: _num(_taken),
            note: _note.text,
            by: ref.read(authControllerProvider)?.username ?? '',
          );
      syncInBackground(ref);
      ref.invalidate(cashDayProvider(dayKey(cd.day)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Day closed · ${_prettyDay(cd.day)}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final key = dayKey(_day);
    final async = ref.watch(cashDayProvider(key));
    // Watched here in build (not inside the LayoutBuilder below).
    _missedBefore =
        ref.watch(unclosedDaysProvider(key)).value ??
        const <({DateTime day, int cashPayments})>[];

    // Already open (Billing keeps its tab alive) and the Dashboard asks for
    // another day → switch to it.
    ref.listen<String?>(dayCloseTargetProvider, (_, next) {
      if (next == null) return;
      setState(() => _day = parseDayKey(next));
      Future.microtask(
        () => ref.read(dayCloseTargetProvider.notifier).set(null),
      );
    });

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1000;
        final form = async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(60),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
          data: (cd) {
            _fill(cd);
            return _form(d, cd);
          },
        );
        final history = _HistoryPanel(
          selected: key,
          onPick: (day) => setState(() => _day = day),
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              form,
              SizedBox(height: 2.h),
              history,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: form),
            SizedBox(width: 1.4.w),
            Expanded(flex: 2, child: history),
          ],
        );
      },
    );
  }

  // ── the closing form ──────────────────────────────────────────────────────

  Widget _form(DentColors d, CashDay cd) {
    final float = _num(_float);
    final expected = cd.expectedWith(float);
    final hasCount = _counted.text.trim().isNotEmpty;
    final counted = _num(_counted);
    final diff = counted - expected;
    final left = counted - _num(_taken);
    final isToday = dayKey(_day) == dayKey(_today());

    final dayNav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: () => _go(-1),
          icon: Icon(Icons.chevron_left_rounded, color: d.text2, size: 16.sp),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _pick,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_rounded, size: 12.sp, color: d.ice),
                const SizedBox(width: 6),
                Text(
                  isToday ? 'Today' : _prettyDay(_day),
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: isToday ? null : () => _go(1),
          icon: Icon(
            Icons.chevron_right_rounded,
            color: isToday ? d.line2 : d.text2,
            size: 16.sp,
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(cashDayProvider(dayKey(_day))),
          icon: Icon(Icons.refresh_rounded, color: d.text3, size: 13.sp),
        ),
      ],
    );

    return DentPanel(
      title: 'Close the Day',
      subtitle: _prettyDay(cd.day),
      trailing: dayNav,
      child: Padding(
        padding: EdgeInsets.all(1.4.w.clamp(16.0, 28.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._earlierNotClosed(d, cd),
            if (cd.closing != null) ...[
              _banner(
                d,
                cd.changedSinceClosing ? d.warn : d.ok,
                cd.changedSinceClosing
                    ? Icons.report_problem_rounded
                    : Icons.verified_rounded,
                cd.changedSinceClosing
                    ? 'Payments or expenses changed after this day was closed. '
                          'Expected cash is now Rs ${_m(expected)} — save again to update.'
                    : 'Closed by ${cd.closing!.closedByName.isEmpty ? '—' : cd.closing!.closedByName}'
                          ' at ${_time(cd.closing!.closedAt)}. You can correct it and save again.',
              ),
              SizedBox(height: 1.6.h),
            ],

            // ── expected ──
            _label(d, 'WHAT SHOULD BE IN THE DRAWER'),
            SizedBox(height: 1.h),
            _line(
              d,
              'Opening cash',
              trailing: SizedBox(
                width: 150,
                child: _moneyField(d, _float, dense: true),
              ),
              hint: cd.suggestedFloat > 0
                  ? 'Left in the drawer last time: Rs ${_m(cd.suggestedFloat)}'
                  : 'Cash already in the drawer this morning',
            ),
            _line(
              d,
              '+  Cash received',
              amount: cd.cashIn,
              hint:
                  '${cd.cashPayments} cash payment${cd.cashPayments == 1 ? '' : 's'}',
              tone: d.teal,
            ),
            _line(
              d,
              '−  Cash expenses paid',
              amount: cd.cashOut,
              hint: 'Expenses recorded with method "Cash"',
              tone: d.warn,
            ),
            Divider(color: d.line, height: 2.h),
            _line(d, '=  Expected cash', amount: expected, bold: true),
            if (cd.otherMethods.isNotEmpty) ...[
              SizedBox(height: 1.2.h),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Not in the drawer:',
                    style: TextStyle(color: d.text4, fontSize: 9.5.sp),
                  ),
                  for (final e in cd.otherMethods.entries)
                    _chip(d, '${e.key} · Rs ${_m(e.value)}', d.ice),
                ],
              ),
            ],

            SizedBox(height: 2.6.h),

            // ── counted ──
            Row(
              children: [
                Expanded(child: _label(d, 'CASH YOU COUNTED')),
                TextButton.icon(
                  onPressed: () => setState(() => _byNotes = !_byNotes),
                  icon: Icon(
                    _byNotes ? Icons.keyboard_rounded : Icons.payments_outlined,
                    size: 12.sp,
                    color: d.ice,
                  ),
                  label: Text(
                    _byNotes ? 'Type total instead' : 'Count by notes',
                    style: TextStyle(color: d.ice, fontSize: 9.8.sp),
                  ),
                ),
              ],
            ),
            SizedBox(height: 0.6.h),
            if (_byNotes)
              _notesGrid(d)
            else
              _moneyField(d, _counted, big: true),

            SizedBox(height: 2.h),
            if (hasCount) _difference(d, diff),

            SizedBox(height: 2.4.h),
            _label(d, 'AFTER COUNTING'),
            SizedBox(height: 1.h),
            _line(
              d,
              'Taken out / handed to owner',
              trailing: SizedBox(
                width: 150,
                child: _moneyField(d, _taken, dense: true),
              ),
              hint: 'Cash removed from the drawer now (banked, handed over)',
            ),
            if (hasCount)
              _line(
                d,
                'Left in drawer for tomorrow',
                amount: left < 0 ? 0 : left,
                tone: d.ice,
              ),
            SizedBox(height: 1.4.h),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: d.text1, fontSize: 10.5.sp),
              decoration: InputDecoration(
                labelText: hasCount && diff != 0
                    ? 'Note (required — why is it ${diff < 0 ? 'short' : 'over'}?)'
                    : 'Note (optional)',
                labelStyle: TextStyle(color: d.text3, fontSize: 10.sp),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 1.2.h),
              Text(
                _error!,
                style: TextStyle(color: d.alert, fontSize: 10.sp),
              ),
            ],
            SizedBox(height: 2.h),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  padding: EdgeInsets.symmetric(
                    horizontal: 2.w.clamp(18.0, 32.0),
                    vertical: 16,
                  ),
                ),
                onPressed: _saving ? null : () => _save(cd),
                icon: Icon(Icons.lock_clock_rounded, size: 13.sp),
                label: Text(
                  _saving
                      ? 'Saving…'
                      : cd.closing == null
                      ? 'Close the day'
                      : 'Update closing',
                  style: TextStyle(
                    fontSize: 10.8.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Fri 16 Oct isn't closed" — opening cash comes from the last closing,
  /// so a skipped day makes today's numbers unreliable.
  List<Widget> _earlierNotClosed(DentColors d, CashDay cd) {
    final missed = _missedBefore;
    if (missed.isEmpty) return const [];
    final oldest = missed.first.day;
    final text = missed.length == 1
        ? '${_prettyDay(oldest)} isn\'t closed. Close it first so the opening '
              'cash here is correct.'
        : '${missed.length} earlier days aren\'t closed (oldest ${_prettyDay(oldest)}). '
              'Close them first so the opening cash here is correct.';
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: d.alert.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: d.alert.withValues(alpha: .3)),
        ),
        child: Row(
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 14.sp, color: d.alert),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: d.text2, fontSize: 10.sp),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _day = oldest),
              child: Text(
                'Go to ${oldest.day} ${_mon[oldest.month - 1]}',
                style: TextStyle(
                  color: d.alert,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 1.6.h),
    ];
  }

  Widget _difference(DentColors d, int diff) {
    final ok = diff == 0;
    final tone = ok ? d.ok : (diff < 0 ? d.alert : d.warn);
    return Container(
      padding: EdgeInsets.all(1.2.w.clamp(14.0, 22.0)),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_rounded
                : (diff < 0
                      ? Icons.trending_down_rounded
                      : Icons.trending_up_rounded),
            color: tone,
            size: 20.sp,
          ),
          SizedBox(width: 1.w.clamp(10.0, 16.0)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok
                      ? 'Balanced'
                      : diff < 0
                      ? 'Short by Rs ${_m(-diff)}'
                      : 'Over by Rs ${_m(diff)}',
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: tone,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ok
                      ? 'The counted cash matches exactly.'
                      : diff < 0
                      ? 'Less cash than expected. Check for a payment taken by another method, or cash given out without an expense.'
                      : 'More cash than expected. Check for a cash payment not entered in the app.',
                  style: TextStyle(color: d.text3, fontSize: 9.6.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesGrid(DentColors d) {
    Widget cell(String label, TextEditingController c) => Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: d.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TextStyle(
                color: d.text2,
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '×',
            style: TextStyle(color: d.text4, fontSize: 10.sp),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _sumNotes(),
              style: TextStyle(color: d.text1, fontSize: 10.5.sp),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in _notes) cell(_m(n), _noteCtrls[n]!),
            Container(
              width: 170,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: d.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: d.line),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(
                      'Coins',
                      style: TextStyle(
                        color: d.text2,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Rs',
                    style: TextStyle(color: d.text4, fontSize: 10.sp),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _coins,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _sumNotes(),
                      style: TextStyle(color: d.text1, fontSize: 10.5.sp),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '0',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 1.h),
        Text(
          'Total counted: Rs ${_m(_num(_counted))}',
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: d.text1,
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── small pieces ──────────────────────────────────────────────────────────

  Widget _moneyField(
    DentColors d,
    TextEditingController c, {
    bool big = false,
    bool dense = false,
  }) => TextField(
    controller: c,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (_) => setState(() {}),
    textAlign: dense ? TextAlign.right : TextAlign.left,
    style: TextStyle(
      fontFamily: big ? AppFonts.display : null,
      color: d.text1,
      fontSize: big ? 18.sp : 11.sp,
      fontWeight: big ? FontWeight.w700 : FontWeight.w600,
    ),
    decoration: InputDecoration(
      isDense: dense,
      prefixText: 'Rs ',
      prefixStyle: TextStyle(color: d.text3, fontSize: big ? 14.sp : 10.sp),
      hintText: big ? 'Total cash in the drawer' : '0',
      hintStyle: TextStyle(color: d.text4, fontSize: big ? 12.sp : 10.sp),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  Widget _label(DentColors d, String t) => Text(
    t,
    style: TextStyle(
      color: d.text4,
      fontSize: 9.4.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );

  Widget _line(
    DentColors d,
    String label, {
    int? amount,
    Widget? trailing,
    String? hint,
    Color? tone,
    bool bold = false,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: 0.8.h),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: bold ? d.text1 : d.text2,
                  fontSize: bold ? 12.sp : 11.sp,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (hint != null)
                Text(
                  hint,
                  style: TextStyle(color: d.text4, fontSize: 9.2.sp),
                ),
            ],
          ),
        ),
        trailing ??
            Text(
              'Rs ${_m(amount ?? 0)}',
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: tone ?? d.text1,
                fontSize: bold ? 15.sp : 12.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
      ],
    ),
  );

  Widget _banner(DentColors d, Color tone, IconData icon, String text) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14.sp, color: tone),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: d.text2, fontSize: 10.sp),
              ),
            ),
          ],
        ),
      );

  Widget _chip(DentColors d, String t, Color tone) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      t,
      style: TextStyle(
        color: tone,
        fontSize: 9.4.sp,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Recent closings
// ═════════════════════════════════════════════════════════════════════════════

class _HistoryPanel extends ConsumerWidget {
  const _HistoryPanel({required this.selected, required this.onPick});
  final String selected;
  final void Function(DateTime day) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final rows =
        ref.watch(cashHistoryProvider).value ?? const <CashClosingRow>[];
    final missed =
        ref.watch(unclosedDaysProvider(dayKey(DateTime.now()))).value ??
        const <({DateTime day, int cashPayments})>[];

    // Closed days and missed days together, newest first.
    final items = <({String day, CashClosingRow? row, int cashPayments})>[
      for (final r in rows) (day: r.day, row: r, cashPayments: 0),
      for (final m in missed)
        (day: dayKey(m.day), row: null, cashPayments: m.cashPayments),
    ]..sort((a, b) => b.day.compareTo(a.day));

    // This month's short / over totals.
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    var short = 0, over = 0, shortDays = 0;
    for (final r in rows.where((r) => r.day.startsWith(prefix))) {
      final diff = r.counted - r.expected;
      if (diff < 0) {
        short += -diff;
        shortDays++;
      } else {
        over += diff;
      }
    }

    return DentPanel(
      title: 'Recent Closings',
      subtitle: missed.isNotEmpty
          ? '${missed.length} day${missed.length == 1 ? '' : 's'} not closed in the last week'
          : rows.isEmpty
          ? 'No day closed yet'
          : 'This month: ${shortDays == 0 ? 'never short' : 'short Rs ${_m(short)} on $shortDays day${shortDays == 1 ? '' : 's'}'}'
                '${over > 0 ? ' · over Rs ${_m(over)}' : ''}',
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                children: [
                  Icon(Icons.lock_clock_outlined, size: 24.sp, color: d.text4),
                  const SizedBox(height: 10),
                  Text(
                    'Close each day here: count the cash and the app\n'
                    'tells you instantly if anything is missing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: d.text4, fontSize: 10.sp),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (final it in items.take(30))
                  it.row != null
                      ? _row(context, d, it.row!)
                      : _missedRow(d, it.day, it.cashPayments),
              ],
            ),
    );
  }

  Widget _missedRow(DentColors d, String key, int cashPayments) {
    final day = parseDayKey(key);
    final isSel = key == selected;
    return InkWell(
      onTap: () => onPick(day),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 1.1.h),
        decoration: BoxDecoration(
          color: isSel
              ? d.ice.withValues(alpha: .07)
              : d.alert.withValues(alpha: .05),
          border: Border(top: BorderSide(color: d.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _prettyDay(day),
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    cashPayments == 0
                        ? 'Cash expenses paid · cash never counted'
                        : '$cashPayments cash payment${cashPayments == 1 ? '' : 's'} · cash never counted',
                    style: TextStyle(color: d.text3, fontSize: 9.2.sp),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: d.alert.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Not closed',
                style: TextStyle(
                  color: d.alert,
                  fontSize: 9.2.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, DentColors d, CashClosingRow r) {
    final diff = r.counted - r.expected;
    final day = parseDayKey(r.day);
    final tone = diff == 0 ? d.ok : (diff < 0 ? d.alert : d.warn);
    final isSel = r.day == selected;
    return InkWell(
      onTap: () => onPick(day),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 1.1.h),
        decoration: BoxDecoration(
          color: isSel ? d.ice.withValues(alpha: .07) : null,
          border: Border(top: BorderSide(color: d.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _prettyDay(day),
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Expected Rs ${_m(r.expected)} · counted Rs ${_m(r.counted)}'
                    '${r.closedByName.isEmpty ? '' : ' · ${r.closedByName}'}',
                    style: TextStyle(color: d.text3, fontSize: 9.2.sp),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                diff == 0
                    ? 'Balanced'
                    : diff < 0
                    ? 'Short ${_m(-diff)}'
                    : 'Over ${_m(diff)}',
                style: TextStyle(
                  color: tone,
                  fontSize: 9.2.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
