import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';
import 'package:sizer/sizer.dart';

import 'package:is_dental/features/billing/data/invoice_visits.dart';
import 'package:is_dental/core/utils/run_once.dart';
import '../data/cash_repository.dart';

const _mon = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _short = [
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

String _m(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (x) => '${x[1]},',
);

String _pctText(double p) =>
    p == p.roundToDouble() ? '${p.round()}%' : '${p.toStringAsFixed(1)}%';

/// Monthly payout sheet: what each dentist earned from money collected.
class CommissionView extends ConsumerStatefulWidget {
  const CommissionView({super.key});

  @override
  ConsumerState<CommissionView> createState() => _CommissionViewState();
}

class _CommissionViewState extends ConsumerState<CommissionView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrent {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  void _shift(int by) => setState(() {
    final next = DateTime(_month.year, _month.month + by);
    final n = DateTime.now();
    if (!next.isAfter(DateTime(n.year, n.month))) _month = next;
  });

  Future<void> _editRate(CommissionLine l) async {
    final d = context.dent;
    final c = TextEditingController(
      text: l.percent == 0 ? '' : _pctText(l.percent).replaceAll('%', ''),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Commission for ${l.dentist}',
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share of the money collected from this dentist\'s patients.',
                style: TextStyle(color: d.text3, fontSize: 10.sp),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: percentInput,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  suffixText: '%',
                  hintText: 'e.g. 40',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onSubmitted: (v) =>
                    Navigator.pop(ctx, double.tryParse(v.trim()) ?? -1),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
            ),
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(c.text.trim()) ?? -1),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result < 0 || result > 100) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a percentage between 0 and 100, like 40. The rate was not changed.',
            ),
          ),
        );
      }
      return;
    }
    await ref.read(cashRepositoryProvider).setRate(l.dentist, result);
    syncInBackground(ref);
  }

  void _showPayments(CommissionLine l) {
    final d = context.dent;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: d.surface,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(ctx).height * .85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.unassigned
                                ? 'Payments not linked to a dentist'
                                : '${l.dentist} · ${_mon[_month.month - 1]} ${_month.year}',
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              color: d.text1,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${l.payments.length} payment${l.payments.length == 1 ? '' : 's'} · Rs ${_m(l.collected)} collected'
                            '${l.unassigned ? '' : ' · commission Rs ${_m(l.commission)}'}',
                            style: TextStyle(color: d.text3, fontSize: 10.sp),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close_rounded, color: d.text3),
                    ),
                  ],
                ),
              ),
              if (l.unassigned)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  child: Text(
                    'The app couldn\'t tell which dentist did this work. '
                    'Press Link and pick the visit — the money moves to that '
                    'dentist straight away.',
                    style: TextStyle(color: d.text4, fontSize: 9.6.sp),
                  ),
                ),
              Flexible(
                child: l.payments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          'No payments this month.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: d.text4, fontSize: 10.sp),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: l.payments.length,
                        itemBuilder: (_, i) {
                          final p = l.payments[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: d.line)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.patient,
                                        style: TextStyle(
                                          color: d.text1,
                                          fontSize: 10.5.sp,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${p.paidAt.day} ${_short[p.paidAt.month - 1]} · #${p.invoiceNo}'
                                        '${p.guessed ? ' · matched from nearest visit' : ''}',
                                        style: TextStyle(
                                          color: d.text3,
                                          fontSize: 9.2.sp,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Rs ${_m(p.amount)}',
                                  style: AppTypography.mono(
                                    size: 10.sp,
                                    color: d.text1,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (l.unassigned)
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                    onPressed: () => _linkVisit(ctx, p),
                                    child: Text(
                                      'Link',
                                      style: TextStyle(fontSize: 9.6.sp),
                                    ),
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Change dentist / visit',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _linkVisit(ctx, p),
                                    icon: Icon(
                                      Icons.swap_horiz_rounded,
                                      size: 18,
                                      color: d.text3,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick the visit a payment's invoice belongs to. Linking moves the
  /// money to that visit's dentist (and is synced to the other computers).
  Future<void> _linkVisit(BuildContext listCtx, CommissionPayment p) async {
    final d = context.dent;
    final db = ref.read(appDatabaseProvider);
    final visits = await patientVisits(db, p.patientId, around: p.paidAt);
    if (!mounted) return;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(ctx).height * .8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Which visit was #${p.invoiceNo} for?',
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              color: d.text1,
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${p.patient} · Rs ${_m(p.amount)} paid ${p.paidAt.day} ${_short[p.paidAt.month - 1]}',
                            style: TextStyle(color: d.text3, fontSize: 9.8.sp),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close_rounded, color: d.text3),
                    ),
                  ],
                ),
              ),
              if (visits.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Text(
                    'This patient has no appointment in the $kVisitLookbackDays '
                    'days before this payment. Book the visit in Appointments '
                    '(with the dentist who did the work), then link it here.',
                    style: TextStyle(color: d.text3, fontSize: 10.sp),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (final v in visits)
                        ListTile(
                          onTap: () => Navigator.pop(ctx, v.id),
                          leading: CircleAvatar(
                            radius: 17,
                            backgroundColor: d.ice.withValues(alpha: .14),
                            child: Text(
                              v.dentist.trim().isEmpty
                                  ? '?'
                                  : v.dentist.trim()[0].toUpperCase(),
                              style: TextStyle(
                                color: d.ice,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            v.dentist.trim().isEmpty
                                ? 'No dentist on this visit'
                                : v.dentist.trim(),
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 10.8.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              v.when,
                              if (v.procedure.trim().isNotEmpty)
                                v.procedure.trim(),
                            ].join(' · '),
                            style: TextStyle(color: d.text3, fontSize: 9.4.sp),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: d.text4,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;

    await linkInvoiceToVisit(db, p.invoiceId, picked);
    syncInBackground(ref);
    ref.invalidate(commissionProvider(_month));
    if (listCtx.mounted) Navigator.pop(listCtx); // its totals are now stale
    if (!mounted) return;
    final who = visits.firstWhere((v) => v.id == picked).dentist.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '#${p.invoiceNo} linked to ${who.isEmpty ? 'that visit' : who}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final async = ref.watch(commissionProvider(_month));
    _canPay = ref.watch(canProvider(Perm.manageExpenses));

    final monthNav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => _shift(-1),
          icon: Icon(Icons.chevron_left_rounded, size: 16.sp, color: d.text2),
        ),
        Text(
          '${_mon[_month.month - 1]} ${_month.year}',
          style: TextStyle(
            color: d.text1,
            fontSize: 10.8.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: _isCurrent ? null : () => _shift(1),
          icon: Icon(
            Icons.chevron_right_rounded,
            size: 16.sp,
            color: _isCurrent ? d.line2 : d.text2,
          ),
        ),
      ],
    );

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(60),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
      data: (sheet) {
        final dentists = sheet.lines.where((l) => !l.unassigned).toList();
        final noRate = dentists.where((l) => l.percent == 0).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary(d, sheet),
            SizedBox(height: 2.h),
            DentPanel(
              title: 'Dentist Payouts',
              subtitle: noRate > 0
                  ? '$noRate dentist${noRate == 1 ? ' has' : 's have'} no commission set — click the % to set it'
                  : 'Based on money collected this month · click a row for the payments',
              trailing: monthNav,
              child: sheet.lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(
                        'No payments or appointments this month.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: d.text4, fontSize: 10.5.sp),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        final wide = c.maxWidth >= 760;
                        return Column(
                          children: [
                            if (wide) _headRow(d),
                            for (final l in sheet.lines)
                              wide ? _wideRow(d, l) : _narrowRow(d, l),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _summary(DentColors d, CommissionSheet s) {
    Widget block(String label, int v, Color tone, IconData icon) => Expanded(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 15.sp),
          ),
          SizedBox(width: 1.w.clamp(10.0, 16.0)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: d.text4,
                    fontSize: 9.4.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rs ${_m(v)}',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      color: d.text1,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.all(1.4.w.clamp(18.0, 26.0)),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final items = [
            block(
              'COLLECTED',
              s.totalCollected,
              d.teal,
              Icons.payments_rounded,
            ),
            block(
              'DENTIST COMMISSION',
              s.totalCommission,
              d.warn,
              Icons.badge_rounded,
            ),
            block(
              'STILL TO PAY',
              s.totalDue,
              s.totalDue > 0 ? d.alert : d.ok,
              s.totalDue > 0
                  ? Icons.schedule_rounded
                  : Icons.check_circle_rounded,
            ),
            block(
              'CLINIC KEEPS',
              s.totalCollected - s.totalCommission,
              d.ice,
              Icons.account_balance_rounded,
            ),
          ];
          if (c.maxWidth < 760) {
            return Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(color: d.line, height: 3.h),
                  Row(children: [items[i]]),
                ],
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                items[0],
                VerticalDivider(color: d.line, width: 3.w.clamp(24.0, 44.0)),
                items[1],
                VerticalDivider(color: d.line, width: 3.w.clamp(24.0, 44.0)),
                items[2],
                VerticalDivider(color: d.line, width: 3.w.clamp(24.0, 44.0)),
                items[3],
              ],
            ),
          );
        },
      ),
    );
  }

  TextStyle _head(DentColors d) => TextStyle(
    color: d.text4,
    fontSize: 9.sp,
    fontWeight: FontWeight.w700,
    letterSpacing: .8,
  );

  Widget _headRow(DentColors d) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    child: Row(
      children: [
        Expanded(flex: 4, child: Text('DENTIST', style: _head(d))),
        Expanded(
          flex: 2,
          child: Text('VISITS', textAlign: TextAlign.right, style: _head(d)),
        ),
        Expanded(
          flex: 3,
          child: Text('COLLECTED', textAlign: TextAlign.right, style: _head(d)),
        ),
        Expanded(
          flex: 2,
          child: Text('RATE', textAlign: TextAlign.center, style: _head(d)),
        ),
        Expanded(
          flex: 3,
          child: Text(
            'COMMISSION',
            textAlign: TextAlign.right,
            style: _head(d),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text('PAYOUT', textAlign: TextAlign.right, style: _head(d)),
        ),
        const SizedBox(width: 26),
      ],
    ),
  );

  Widget _avatar(DentColors d, CommissionLine l) => Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: (l.unassigned ? d.text4 : d.ice).withValues(alpha: .14),
      shape: BoxShape.circle,
    ),
    child: l.unassigned
        ? Icon(Icons.help_outline_rounded, size: 13.sp, color: d.text4)
        : Text(
            l.dentist.isEmpty ? '?' : l.dentist.trim()[0].toUpperCase(),
            style: TextStyle(
              color: d.ice,
              fontSize: 11.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
  );

  Widget _rateChip(DentColors d, CommissionLine l) {
    if (l.unassigned) {
      return Text(
        '—',
        textAlign: TextAlign.center,
        style: TextStyle(color: d.text4, fontSize: 10.sp),
      );
    }
    final unset = l.percent == 0;
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _editRate(l),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (unset ? d.warn : d.ice).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (unset ? d.warn : d.ice).withValues(alpha: .4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unset ? 'Set %' : _pctText(l.percent),
                style: TextStyle(
                  color: unset ? d.warn : d.ice,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.edit_rounded,
                size: 9.sp,
                color: unset ? d.warn : d.ice,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _money(DentColors d, int v, {Color? tone, bool bold = false}) => Text(
    'Rs ${_m(v)}',
    textAlign: TextAlign.right,
    style: TextStyle(
      fontFamily: AppFonts.display,
      color: tone ?? d.text1,
      fontSize: bold ? 12.sp : 11.sp,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
    ),
  );

  Widget _wideRow(DentColors d, CommissionLine l) => InkWell(
    onTap: () => _showPayments(l),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 1.2.h),
      decoration: BoxDecoration(
        color: l.unassigned ? d.surface2 : null,
        border: Border(top: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _avatar(d, l),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.unassigned ? 'Not linked to a dentist' : l.dentist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: l.unassigned ? d.text3 : d.text1,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${l.visits}',
              textAlign: TextAlign.right,
              style: AppTypography.mono(size: 10.5.sp, color: d.text2),
            ),
          ),
          Expanded(flex: 3, child: _money(d, l.collected)),
          Expanded(flex: 2, child: _rateChip(d, l)),
          Expanded(
            flex: 3,
            child: l.unassigned
                ? Text(
                    '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: d.text4),
                  )
                : _money(d, l.commission, tone: d.warn, bold: true),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: _payCell(d, l),
            ),
          ),
          SizedBox(
            width: 26,
            child: Icon(
              Icons.chevron_right_rounded,
              size: 14.sp,
              color: d.text4,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _narrowRow(DentColors d, CommissionLine l) => InkWell(
    onTap: () => _showPayments(l),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: l.unassigned ? d.surface2 : null,
        border: Border(top: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          _avatar(d, l),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.unassigned ? 'Not linked to a dentist' : l.dentist,
                  style: TextStyle(
                    color: l.unassigned ? d.text3 : d.text1,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${l.visits} visits · collected Rs ${_m(l.collected)}',
                  style: TextStyle(color: d.text3, fontSize: 9.4.sp),
                ),
              ],
            ),
          ),
          _rateChip(d, l),
          const SizedBox(width: 12),
          if (!l.unassigned)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _money(d, l.commission, tone: d.warn, bold: true),
                const SizedBox(height: 6),
                _payCell(d, l),
              ],
            ),
        ],
      ),
    ),
  );

  // ── payouts ───────────────────────────────────────────────────────────────

  /// Set in build — rows are built inside a LayoutBuilder, where watching
  /// a provider isn't allowed.
  bool _canPay = false;

  /// Paid ✓ · Pay Rs X · Pay Rs X more — or just the amount due for staff
  /// who can't record expenses.
  Widget _payCell(DentColors d, CommissionLine l) {
    if (l.unassigned) {
      return Text(
        '—',
        style: TextStyle(color: d.text4, fontSize: 10.sp),
      );
    }
    if (l.commission <= 0 && l.paid == 0) {
      return Text(
        l.percent == 0 ? 'Set a rate first' : 'Nothing to pay',
        style: TextStyle(color: d.text4, fontSize: 9.6.sp),
      );
    }
    if (l.due <= 0) {
      return Tooltip(
        message: 'Rs ${_m(l.paid)} paid for this month',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: d.ok.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 11.sp, color: d.ok),
              const SizedBox(width: 4),
              Text(
                'Paid',
                style: TextStyle(
                  color: d.ok,
                  fontSize: 9.8.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final label = l.paid > 0
        ? 'Pay Rs ${_m(l.due)} more'
        : 'Pay Rs ${_m(l.due)}';
    if (!_canPay) {
      return Text(
        'Rs ${_m(l.due)} due',
        style: TextStyle(
          color: d.alert,
          fontSize: 10.sp,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: d.ice,
        foregroundColor: AppPalette.onAccent,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      // a double click opens one payout, never two
      onPressed: () => runOnce(
        'payout:${dentistKey(l.dentist)}:${_month.year}-${_month.month}',
        () => _pay(l),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9.8.sp, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _pay(CommissionLine l) async {
    final d = context.dent;
    final repo = ref.read(cashRepositoryProvider);
    final methods = await repo.paymentMethods();
    if (!mounted) return;
    final amount = TextEditingController(text: '${l.due}');
    var method = methods.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: d.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Pay ${l.dentist}',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commission for ${_mon[_month.month - 1]} ${_month.year}'
                  ' · earned Rs ${_m(l.commission)}'
                  '${l.paid > 0 ? ' · already paid Rs ${_m(l.paid)}' : ''}',
                  style: TextStyle(color: d.text3, fontSize: 10.sp),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    prefixText: 'Rs ',
                    labelText: 'Amount',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: method,
                  items: [
                    for (final m in methods)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => setLocal(() => method = v ?? method),
                  decoration: InputDecoration(
                    labelText: 'Paid by',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This is saved as an expense under "$kCommissionCategory", '
                  'so your profit stays correct.',
                  style: TextStyle(color: d.text4, fontSize: 9.2.sp),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: d.ice,
                foregroundColor: AppPalette.onAccent,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Record payout'),
            ),
          ],
        ),
      ),
    );
    final value = int.tryParse(amount.text.trim()) ?? 0;
    if (ok != true || value <= 0) return;

    await repo.payCommission(
      dentist: l.dentist,
      month: _month,
      amount: value,
      method: method,
      branchId: ref.read(activeBranchProvider),
      by: ref.read(authControllerProvider)?.username ?? '',
    );
    syncInBackground(ref);
    ref.invalidate(commissionProvider(_month));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payout of Rs ${_m(value)} to ${l.dentist} recorded'),
        ),
      );
    }
  }
}
