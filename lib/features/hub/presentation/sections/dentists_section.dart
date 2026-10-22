import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../widgets/hub_ui.dart';

/// Dentists — visits, no-shows, money collected, average bill and the
/// commission each one is owed for the period.
class DentistsSection extends StatelessWidget {
  const DentistsSection({
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
    final list = data.dentists;

    HubDentist? top(int Function(HubDentist) by) {
      HubDentist? best;
      for (final x in list) {
        if (by(x) > 0 && (best == null || by(x) > by(best))) best = x;
      }
      return best;
    }

    final busiest = top((x) => x.completed);
    final highest = top((x) => x.avgBill);
    HubDentist? mostNoShows;
    for (final x in list) {
      if (x.noShows == 0) continue;
      if (mostNoShows == null || x.noShowRate > mostNoShows.noShowRate) {
        mostNoShows = x;
      }
    }
    final due = list.fold<int>(0, (s, x) => s + (x.due > 0 ? x.due : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: 'Dentists',
          subtitle: period.describe,
          trailing: periodPicker,
        ),
        if (list.isEmpty)
          HubCard(
            icon: Icons.groups_outlined,
            tone: d.ice,
            title: 'No dentist activity yet',
            child: const HubEmpty(
              'Appointments and payments with a dentist name appear here.',
              icon: Icons.groups_outlined,
            ),
          )
        else ...[
          HubGrid(
            minWidth: 230,
            maxColumns: 4,
            children: [
              HubKpi(
                label: 'Busiest dentist',
                value: busiest?.name ?? '—',
                sub: busiest == null
                    ? 'No finished visits yet'
                    : '${busiest.completed} visits finished',
              ),
              HubKpi(
                label: 'Highest average bill',
                value: highest?.name ?? '—',
                sub: highest == null
                    ? 'Nothing collected yet'
                    : '${hubRs(highest.avgBill, hidden: HubScope.of(context).hidden)} per visit',
              ),
              HubKpi(
                label: 'Most no-shows',
                value: mostNoShows?.name ?? 'None',
                valueColor: mostNoShows == null ? d.ok : null,
                sub: mostNoShows == null
                    ? 'Every booked patient came'
                    : '${mostNoShows.noShows} no-show'
                          '${mostNoShows.noShows == 1 ? '' : 's'} · '
                          '${(mostNoShows.noShowRate * 100).round()}% of visits',
              ),
              if (period.month == null)
                HubKpi(
                  label: 'Commission still to pay',
                  value: '—',
                  sub:
                      'Payouts are monthly — pick This month, Last month '
                      'or one whole month to see it',
                )
              else
                HubKpi(
                  label: 'Commission still to pay',
                  amount: due,
                  valueColor: due > 0 ? d.warn : null,
                  sub: due > 0
                      ? 'Pay from Expenses → Dentist payouts'
                      : 'Everyone is paid up',
                ),
            ],
          ),
          const SizedBox(height: 18),
          HubCard(
            icon: Icons.groups_outlined,
            tone: d.ice,
            title: 'Each dentist',
            subtitle: 'Collected = money received on their patients’ bills',
            trailing: const HubGoLink('Payouts', HubGo.expenses),
            child: LayoutBuilder(
              builder: (context, c) => c.maxWidth >= 880
                  ? _Table(list: list)
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: d.line),
                          _DentistTile(x: list[i]),
                        ],
                      ],
                    ),
            ),
          ),
          if (data.unassigned > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: d.warn.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: d.warn.withValues(alpha: .3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_off_rounded, color: d.warn, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${hubRs(data.unassigned, hidden: HubScope.of(context).hidden)} '
                      'collected in this period is not linked to any dentist, so '
                      'nobody earns commission on it. Link it in Dentist payouts.',
                      style: TextStyle(
                        color: d.text2,
                        fontSize: 9.8.sp,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const HubGoLink('Fix', HubGo.expenses),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.list});
  final List<HubDentist> list;

  static const _flex = [26, 12, 11, 17, 14, 15, 15];

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final maxCollected = list.fold<int>(
      1,
      (m, x) => x.collected > m ? x.collected : m,
    );

    Widget head(String t, int i, {bool end = false}) => Expanded(
      flex: _flex[i],
      child: Text(
        t,
        textAlign: end ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: d.text4,
          fontSize: 9.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
        ),
      ),
    );

    return Column(
      children: [
        Container(
          color: d.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              head('DENTIST', 0),
              head('VISITS', 1, end: true),
              head('NO-SHOWS', 2, end: true),
              head('COLLECTED', 3, end: true),
              head('AVG BILL', 4, end: true),
              head('COMMISSION', 5, end: true),
              head('STILL TO PAY', 6, end: true),
            ],
          ),
        ),
        for (final x in list)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: d.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: _flex[0],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        x.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 10.2.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: x.collected / maxCollected,
                            minHeight: 5,
                            backgroundColor: d.line,
                            valueColor: AlwaysStoppedAnimation(d.teal),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _cell(d, _flex[1], '${x.completed} / ${x.booked}'),
                _cell(
                  d,
                  _flex[2],
                  x.noShows == 0
                      ? '0'
                      : '${x.noShows} · ${(x.noShowRate * 100).round()}%',
                  color: x.noShowRate >= .15 ? d.alert : null,
                ),
                _money(d, _flex[3], x.collected, bold: true),
                _money(d, _flex[4], x.avgBill),
                Expanded(
                  flex: _flex[5],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      HubAmount(
                        x.commission,
                        style: TextStyle(color: d.text1, fontSize: 10.sp),
                      ),
                      Text(
                        x.percent == 0
                            ? 'no rate set'
                            : '${x.percent.toStringAsFixed(x.percent % 1 == 0 ? 0 : 1)}%',
                        style: TextStyle(color: d.text4, fontSize: 9.2.sp),
                      ),
                    ],
                  ),
                ),
                if (x.paidKnown)
                  _money(
                    d,
                    _flex[6],
                    x.due > 0 ? x.due : 0,
                    bold: true,
                    color: x.due > 0 ? d.warn : d.ok,
                  )
                else
                  _cell(d, _flex[6], '—'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(DentColors d, int flex, String text, {Color? color}) => Expanded(
    flex: flex,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(color: color ?? d.text2, fontSize: 10.sp),
    ),
  );

  Widget _money(
    DentColors d,
    int flex,
    int v, {
    bool bold = false,
    Color? color,
  }) => Expanded(
    flex: flex,
    child: Align(
      alignment: Alignment.centerRight,
      child: HubAmount(
        v,
        style: TextStyle(
          color: color ?? d.text1,
          fontSize: 10.sp,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
  );
}

/// Narrow-window version of one table row.
class _DentistTile extends StatelessWidget {
  const _DentistTile({required this.x});
  final HubDentist x;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    Widget fact(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: d.text3, fontSize: 9.6.sp),
            ),
          ),
          value,
        ],
      ),
    );
    final style = TextStyle(
      color: d.text1,
      fontSize: 10.sp,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            x.name,
            style: TextStyle(
              color: d.text1,
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          fact(
            'Visits finished / booked',
            Text('${x.completed} / ${x.booked}', style: style),
          ),
          fact(
            'No-shows',
            Text(
              '${x.noShows} · ${(x.noShowRate * 100).round()}%',
              style: style.copyWith(
                color: x.noShowRate >= .15 ? d.alert : null,
              ),
            ),
          ),
          fact('Collected', HubAmount(x.collected, style: style)),
          fact('Average bill', HubAmount(x.avgBill, style: style)),
          fact('Commission', HubAmount(x.commission, style: style)),
          fact(
            'Still to pay',
            x.paidKnown
                ? HubAmount(
                    x.due > 0 ? x.due : 0,
                    style: style.copyWith(color: x.due > 0 ? d.warn : d.ok),
                  )
                : Text('—', style: style),
          ),
        ],
      ),
    );
  }
}
