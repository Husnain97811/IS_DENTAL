import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../widgets/hub_ui.dart';

/// Right now — today's pulse, what needs the owner, and the chairs.
class RightNowSection extends StatelessWidget {
  const RightNowSection({super.key, required this.data});
  final HubData data;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final t = data.today;
    final now = DateTime.now();
    final lastWeekDay = hubWeekday(now.subtract(const Duration(days: 7)));
    final monthShort = hubMonthName(now).substring(0, 3);
    final other = t.collected - t.collectedCash;
    final seen = t.count('completed'),
        inChair = t.count('inChair'),
        waiting = t.count('waiting'),
        toCome = t.count('upcoming'),
        noShows = t.count('noShow');
    final margin = t.monthCollected <= 0
        ? null
        : (t.monthNet / t.monthCollected * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: 'Right now',
          subtitle:
              '${hubWeekday(now)} ${hubDate(now)} · what needs you and '
              'what is happening in the chairs',
        ),
        HubGrid(
          minWidth: 220,
          children: [
            HubKpi(
              label: 'Collected today',
              amount: t.collected,
              sub: t.collected == 0
                  ? 'Nothing collected yet today'
                  : 'Cash ${hubRs(t.collectedCash, hidden: hidden)} · '
                        'other ${hubRs(other, hidden: hidden)}',
              delta: hubDelta(
                t.collected,
                t.lastWeekSameTime,
                'last ${lastWeekDay.substring(0, 3)}',
              ),
              segments: [
                (t.collectedCash.toDouble(), d.teal),
                (other.toDouble(), d.ice),
              ],
            ),
            HubKpi(
              label: 'Patients today',
              value: '${t.patients}',
              sub:
                  '$seen seen · $inChair in chair · $waiting waiting · '
                  '$toCome to come',
              delta: noShows == 0
                  ? null
                  : HubDelta(
                      '$noShows no-show${noShows == 1 ? '' : 's'}',
                      false,
                    ),
              segments: [
                (seen.toDouble(), d.teal),
                (inChair.toDouble(), d.ice),
                (waiting.toDouble(), d.warn),
                (toCome.toDouble(), d.text4.withValues(alpha: .45)),
              ],
            ),
            HubKpi(
              label: 'Collected this month',
              amount: t.monthCollected,
              sub: '1–${now.day} ${hubMonthName(now)}',
              delta: hubDelta(
                t.monthCollected,
                t.lastMonthToDate,
                'same days last month',
              ),
              // filled = how far past the same days last month
              segments: t.lastMonthToDate <= 0
                  ? [(1.0, d.teal)]
                  : [
                      (
                        t.monthCollected.clamp(0, t.lastMonthToDate).toDouble(),
                        d.teal,
                      ),
                      (
                        (t.lastMonthToDate - t.monthCollected)
                            .clamp(0, t.lastMonthToDate)
                            .toDouble(),
                        d.line,
                      ),
                    ],
            ),
            HubKpi(
              label: 'Net profit · $monthShort',
              amount: t.monthNet,
              valueColor: t.monthNet < 0 ? d.alert : null,
              sub:
                  'After ${hubRs(t.monthExpenses, hidden: hidden)} of expenses',
              delta: margin == null
                  ? null
                  : HubDelta(
                      margin >= 0
                          ? 'You keep $margin% of what comes in'
                          : 'Spending more than collected',
                      margin >= 0,
                    ),
              // kept vs spent, out of what came in
              segments: [
                ((t.monthNet > 0 ? t.monthNet : 0).toDouble(), d.teal),
                (t.monthExpenses.toDouble(), d.warn),
              ],
            ),
            HubKpi(
              label: 'Still owed to you',
              amount: t.owedTotal,
              valueColor: t.owedTotal > 0 ? d.warn : null,
              sub: t.owedCount == 0
                  ? 'Every invoice is paid'
                  : '${t.owedCount} invoice${t.owedCount == 1 ? '' : 's'} · '
                        '${hubRs(t.owedOver60, hidden: hidden)} over 60 days',
              segments: t.owedTotal == 0
                  ? [(1.0, d.ok)]
                  : [
                      ((t.owedTotal - t.owedOver60).toDouble(), d.warn),
                      (t.owedOver60.toDouble(), d.alert),
                    ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        HubTwoUp(
          breakAt: 1080,
          leftFlex: 5,
          rightFlex: 6,
          left: _NeedsYou(alerts: data.alerts),
          right: _Chairs(today: t),
        ),
      ],
    );
  }
}

// ───────────────────────────── Needs you ─────────────────────────────

class _NeedsYou extends StatelessWidget {
  const _NeedsYou({required this.alerts});
  final List<HubAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    int n(HubLevel l) => alerts.where((a) => a.level == l).length;
    final parts = [
      if (n(HubLevel.urgent) > 0) '${n(HubLevel.urgent)} urgent',
      if (n(HubLevel.today) > 0) '${n(HubLevel.today)} today',
      if (n(HubLevel.later) > 0) '${n(HubLevel.later)} when you can',
    ];
    return HubCard(
      icon: Icons.notifications_active_outlined,
      tone: alerts.isEmpty ? d.ok : d.alert,
      title: 'Needs you',
      subtitle: parts.isEmpty ? 'All clear' : parts.join(' · '),
      child: alerts.isEmpty
          ? const HubEmpty(
              'Nothing needs you right now.\nThe clinic is running smoothly.',
              icon: Icons.check_circle_outline_rounded,
            )
          : Column(
              children: [
                for (var i = 0; i < alerts.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: d.line),
                  _AlertRow(alert: alerts[i]),
                ],
              ],
            ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});
  final HubAlert alert;

  static IconData icon(String k) => switch (k) {
    'cash' => Icons.point_of_sale_rounded,
    'wa' => Icons.chat_outlined,
    'sync' => Icons.sync_problem_rounded,
    'licence' => Icons.verified_outlined,
    'request' => Icons.event_available_outlined,
    'wait' => Icons.hourglass_bottom_rounded,
    'bill' => Icons.receipt_long_outlined,
    'noshow' => Icons.person_off_outlined,
    'owed' => Icons.account_balance_wallet_outlined,
    'payout' => Icons.payments_outlined,
    'lock' => Icons.lock_outline_rounded,
    _ => Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final (tone, word) = switch (alert.level) {
      HubLevel.urgent => (d.alert, 'Urgent'),
      HubLevel.today => (d.warn, 'Today'),
      HubLevel.later => (d.ice, 'When you can'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          hubIconTile(d, icon(alert.icon), tone, size: 38),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      alert.title,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 10.4.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    HubPill(word, tone),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  alert.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: d.text3,
                    fontSize: 9.4.sp,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => HubScope.of(
              context,
            ).onGo(alert.go, arg: alert.arg, label: alert.action),
            style: OutlinedButton.styleFrom(
              foregroundColor: tone,
              side: BorderSide(color: tone.withValues(alpha: .4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: Text(
              alert.action,
              style: TextStyle(fontSize: 9.4.sp, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Today in the chairs ─────────────────────────

class _Chairs extends StatelessWidget {
  const _Chairs({required this.today});
  final HubToday today;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final visits = today.appts.where((a) => a.status != 'cancelled').toList();
    final lanes = <String, List<HubAppt>>{};
    for (final a in visits) {
      (lanes[a.dentist.isEmpty ? 'No dentist' : a.dentist] ??= []).add(a);
    }
    final names = lanes.keys.toList()
      ..sort((a, b) => lanes[b]!.length.compareTo(lanes[a]!.length));

    return HubCard(
      icon: Icons.schedule_rounded,
      tone: d.ice,
      title: 'Today in the chairs',
      subtitle:
          '${hubHour(today.dayStart)} – ${hubHour(today.dayEnd)} · '
          'the red line is now',
      trailing: const HubGoLink('Appointments', HubGo.appointments),
      child: visits.isEmpty
          ? const HubEmpty(
              'No appointments today.',
              icon: Icons.event_busy_outlined,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HoursRow(start: today.dayStart, end: today.dayEnd),
                  const SizedBox(height: 6),
                  for (final n in names)
                    _Lane(
                      name: n,
                      appts: lanes[n]!,
                      start: today.dayStart,
                      end: today.dayEnd,
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      for (final s in const [
                        'completed',
                        'inChair',
                        'waiting',
                        'upcoming',
                        'noShow',
                      ])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _statusColor(d, s),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _statusWord(s),
                              style: TextStyle(color: d.text3, fontSize: 9.sp),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

Color _statusColor(DentColors d, String s) => switch (s) {
  'completed' => d.teal,
  'inChair' => d.ice,
  'waiting' => d.warn,
  'noShow' => d.alert.withValues(alpha: .55),
  _ => d.text4.withValues(alpha: .35),
};

String _statusWord(String s) => switch (s) {
  'completed' => 'Done',
  'inChair' => 'In chair',
  'waiting' => 'Waiting',
  'noShow' => 'No-show',
  'cancelled' => 'Cancelled',
  _ => 'Coming',
};

const _laneLabel = 128.0;

class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.start, required this.end});
  final int start, end;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hours = (end - start) ~/ 60;
    final step = hours > 10 ? 2 : 1;
    return Row(
      children: [
        const SizedBox(width: _laneLabel),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var h = 0; h < hours; h += step)
                    Positioned(
                      left: c.maxWidth * h / hours,
                      child: Text(
                        hubHour(start + h * 60),
                        style: TextStyle(color: d.text4, fontSize: 9.sp),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane({
    required this.name,
    required this.appts,
    required this.start,
    required this.end,
  });

  final String name;
  final List<HubAppt> appts;
  final int start, end;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final span = (end - start).toDouble();
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final done = appts.where((a) => a.status == 'completed').length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: _laneLabel,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 9.8.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$done of ${appts.length} done',
                    style: TextStyle(color: d.text3, fontSize: 9.2.sp),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                double x(int minutes) =>
                    (w * (minutes - start) / span).clamp(0.0, w);
                return Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: d.surface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final a in appts)
                        () {
                          final s = a.startsAt.hour * 60 + a.startsAt.minute;
                          final left = x(s);
                          final width = (x(s + a.minutes) - left).clamp(6.0, w);
                          final upcoming = a.status == 'upcoming';
                          final fill = _statusColor(d, a.status);
                          return Positioned(
                            left: left,
                            top: 4,
                            bottom: 4,
                            width: width - 2,
                            child: Tooltip(
                              message:
                                  '${hubClock(a.startsAt)} · ${a.patient}\n'
                                  '${a.procedure.isEmpty ? '' : '${a.procedure} · '}'
                                  '${_statusWord(a.status)}',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: fill,
                                  borderRadius: BorderRadius.circular(7),
                                  border: upcoming
                                      ? Border.all(color: d.line)
                                      : null,
                                ),
                                child: width < 56
                                    ? null
                                    : Text(
                                        a.patient.split(' ').first,
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        style: TextStyle(
                                          color:
                                              upcoming || a.status == 'noShow'
                                              ? d.text1
                                              : AppPalette.onAccent,
                                          fontSize: 9.sp,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        }(),
                      if (nowMin > start && nowMin < end)
                        Positioned(
                          left: x(nowMin) - 1,
                          top: -3,
                          bottom: -3,
                          width: 2,
                          child: Container(color: d.alert),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
