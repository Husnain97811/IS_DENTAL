import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../../data/hub_security.dart';
import '../../data/hub_watch.dart';
import '../widgets/hub_ui.dart';

/// Watch list — discounts, cancelled bills, removed payments, deleted
/// expenses, price and rate changes, who took the money, who signed in.
class WatchListSection extends StatelessWidget {
  const WatchListSection({
    super.key,
    required this.data,
    required this.period,
    required this.periodPicker,
  });

  final HubData data;
  final HubPeriod period;
  final Widget periodPicker;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final w = data.watch;
    final hidden = HubScope.of(context).hidden;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: 'Watch list',
          subtitle: '${period.describe} · things worth a second look',
          trailing: periodPicker,
        ),
        HubGrid(
          minWidth: 210,
          maxColumns: 5,
          children: [
            HubKpi(
              label: 'Discounts given',
              amount: w.discountTotal,
              valueColor: w.discountTotal > 0 ? d.warn : null,
              sub: w.discountCount == 0
                  ? 'No discounts'
                  : '${w.discountCount} bill${w.discountCount == 1 ? '' : 's'} · '
                        '${(w.discountShare * 100).toStringAsFixed(1)}% of billing',
            ),
            HubKpi(
              label: 'Bills cancelled',
              value: '${w.cancelledCount}',
              valueColor: w.cancelledCount > 0 ? d.alert : null,
              sub: w.cancelledCount == 0
                  ? 'None cancelled'
                  : '${hubRs(w.cancelledTotal, hidden: hidden)} in total',
            ),
            HubKpi(
              label: 'Payments removed',
              value: '${w.removedCount}',
              valueColor: w.removedCount > 0 ? d.alert : null,
              sub: w.removedCount == 0
                  ? 'None removed'
                  : '${hubRs(w.removedTotal, hidden: hidden)} taken off',
            ),
            HubKpi(
              label: 'Expenses deleted',
              value: '${w.deletedCount}',
              valueColor: w.deletedCount > 0 ? d.warn : null,
              sub: w.deletedCount == 0
                  ? 'None deleted'
                  : '${hubRs(w.deletedTotal, hidden: hidden)} in total',
            ),
            HubKpi(
              label: 'Failed sign-ins',
              value: '${w.failedSignIns}',
              valueColor: w.failedSignIns >= 3 ? d.alert : null,
              sub:
                  '${w.afterHoursSignIns} sign-in${w.afterHoursSignIns == 1 ? '' : 's'} '
                  'outside opening hours',
            ),
          ],
        ),
        const SizedBox(height: 18),
        HubTwoUp(
          left: _Discounts(w: w),
          right: _TakenBy(w: w),
        ),
        const SizedBox(height: 18),
        _Changes(w: w),
        const SizedBox(height: 18),
        HubTwoUp(
          left: _SignIns(w: w),
          right: _Visits(
            w: w,
            noShows: w.noShows,
            cancelled: w.cancelledVisits,
          ),
        ),
      ],
    );
  }
}

class _Discounts extends StatelessWidget {
  const _Discounts({required this.w});
  final HubWatch w;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final top = w.discountByDentist.isEmpty
        ? 1
        : w.discountByDentist.first.total;
    return HubCard(
      icon: Icons.local_offer_outlined,
      tone: d.warn,
      title: 'Discounts',
      subtitle: 'Money taken off bills · 30% or more is marked',
      child: w.discounts.isEmpty
          ? const HubEmpty(
              'No discounts in this period.',
              icon: Icons.local_offer_outlined,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final x in w.discountByDentist)
                    HubShareRow(
                      label: x.name,
                      amount: x.total,
                      fraction: x.total / top,
                      color: d.warn,
                      note: '${x.count} bill${x.count == 1 ? '' : 's'}',
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'BIGGEST DISCOUNTS',
                    style: TextStyle(
                      color: d.text4,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                  for (final x in w.discounts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  x.patient,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: d.text1,
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Invoice ${x.invoiceNo} · ${hubShortDate(x.at)}'
                                  '${x.dentist.isEmpty ? '' : ' · ${x.dentist}'}'
                                  '${x.by.isEmpty ? '' : ' · given by ${x.by}'}',
                                  style: TextStyle(
                                    color: d.text3,
                                    fontSize: 9.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          HubPill(
                            '${(x.share * 100).round()}% off',
                            x.big ? d.alert : d.text3,
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 110,
                            child: Text(
                              hubRs(x.amount, hidden: hidden),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _TakenBy extends StatelessWidget {
  const _TakenBy({required this.w});
  final HubWatch w;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final total = w.takenBy.fold<int>(0, (s, x) => s + x.total);
    final top = w.takenBy.isEmpty ? 1 : w.takenBy.first.total;
    return HubCard(
      icon: Icons.badge_outlined,
      tone: d.ice,
      title: 'Who took the money',
      subtitle: 'Payments by the staff member who recorded them',
      child: w.takenBy.isEmpty
          ? const HubEmpty(
              'No payments in this period.',
              icon: Icons.badge_outlined,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(
                children: [
                  for (final x in w.takenBy)
                    HubShareRow(
                      label: x.name,
                      amount: x.total,
                      fraction: x.total / top,
                      color: d.ice,
                      note:
                          '${x.count} payment${x.count == 1 ? '' : 's'} · '
                          '${total == 0 ? 0 : (x.total / total * 100).round()}%',
                    ),
                ],
              ),
            ),
    );
  }
}

class _Changes extends StatelessWidget {
  const _Changes({required this.w});
  final HubWatch w;

  static (IconData, Color) _look(HubChangeKind k, DentColors d) => switch (k) {
    HubChangeKind.invoiceCancelled => (Icons.receipt_long_outlined, d.alert),
    HubChangeKind.paymentRemoved => (Icons.money_off_rounded, d.alert),
    HubChangeKind.expenseDeleted => (Icons.delete_outline_rounded, d.warn),
    HubChangeKind.rateChanged => (Icons.percent_rounded, d.ice),
    HubChangeKind.priceEdited => (Icons.sell_outlined, d.ice),
    HubChangeKind.userRemoved => (Icons.person_remove_outlined, d.warn),
    HubChangeKind.signInFailed => (Icons.lock_outline_rounded, d.alert),
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    return HubCard(
      icon: Icons.manage_search_rounded,
      tone: d.alert,
      title: 'Cancelled, removed and changed',
      subtitle: 'Newest first · names are who did it',
      child: w.changes.isEmpty
          ? const HubEmpty(
              'Nothing was cancelled, removed or changed in this period.',
              icon: Icons.check_circle_outline_rounded,
            )
          : Column(
              children: [
                for (final c in w.changes)
                  () {
                    final (icon, tone) = _look(c.kind, d);
                    return Container(
                      padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: d.line)),
                      ),
                      child: Row(
                        children: [
                          hubIconTile(d, icon, tone, size: 34),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: d.text1,
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  [
                                    if (c.detail.isNotEmpty) c.detail,
                                    if (c.who.isNotEmpty) 'by ${c.who}',
                                  ].join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: d.text3,
                                    fontSize: 9.2.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (c.amount != null)
                                Text(
                                  hubRs(c.amount!, hidden: hidden),
                                  style: TextStyle(
                                    color: d.text1,
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              Text(
                                '${hubShortDate(c.at)} · ${hubClock(c.at)}',
                                style: TextStyle(
                                  color: d.text3,
                                  fontSize: 9.sp,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }(),
              ],
            ),
    );
  }
}

class _SignIns extends StatelessWidget {
  const _SignIns({required this.w});
  final HubWatch w;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return HubCard(
      icon: Icons.login_rounded,
      tone: d.ice,
      title: 'Sign-ins',
      subtitle:
          'Recorded from this update on · outside hours = 30 min before opening or after closing',
      child: w.signIns.isEmpty
          ? const HubEmpty(
              'No sign-ins recorded in this period yet.',
              icon: Icons.login_rounded,
            )
          : Column(
              children: [
                for (final s in w.signIns)
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: d.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 10.2.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                [
                                  '${s.count} sign-in${s.count == 1 ? '' : 's'}',
                                  if (s.devices.isNotEmpty)
                                    'computer ${(s.devices.toList()..sort()).join(', ')}',
                                  if (s.last != null)
                                    'last ${hubShortDate(s.last!)} ${hubClock(s.last!)}',
                                ].join(' · '),
                                style: TextStyle(
                                  color: d.text3,
                                  fontSize: 9.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (s.afterHours > 0) ...[
                          HubPill('${s.afterHours} outside hours', d.warn),
                          const SizedBox(width: 6),
                        ],
                        if (s.failed > 0)
                          HubPill('${s.failed} failed', d.alert),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Visits extends StatelessWidget {
  const _Visits({
    required this.w,
    required this.noShows,
    required this.cancelled,
  });
  final HubWatch w;
  final int noShows, cancelled;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return HubCard(
      icon: Icons.insights_rounded,
      tone: d.teal,
      title: 'Hub visits & missed appointments',
      subtitle:
          '$noShows no-show${noShows == 1 ? '' : 's'} · '
          '$cancelled cancelled appointment${cancelled == 1 ? '' : 's'}',
      child: w.hubVisits.isEmpty
          ? const HubEmpty(
              'Nobody opened the Hub in this period.',
              icon: Icons.insights_rounded,
            )
          : Column(
              children: [
                for (final e in w.hubVisits)
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: d.line)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: d.text4),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${hubEventLabel(e.kind)} · ${e.userName}'
                            '${e.device.isEmpty ? '' : ' · computer ${e.device}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: d.text2, fontSize: 9.6.sp),
                          ),
                        ),
                        Text(
                          '${hubShortDate(e.happenedAt)} · ${hubClock(e.happenedAt)}',
                          style: TextStyle(color: d.text3, fontSize: 9.sp),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
