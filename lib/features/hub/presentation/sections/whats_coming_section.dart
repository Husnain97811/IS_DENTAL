import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../../data/hub_forecast.dart';
import '../widgets/hub_ui.dart';

/// What's coming — month end, the next week, money in vs out, owed money
/// likely to come back, regulars drifting away, busy hours, the year.
class WhatsComingSection extends StatefulWidget {
  const WhatsComingSection({super.key, required this.data});
  final HubData data;

  @override
  State<WhatsComingSection> createState() => _WhatsComingSectionState();
}

class _WhatsComingSectionState extends State<WhatsComingSection> {
  HubHorizon _h = HubHorizon.month;

  @override
  Widget build(BuildContext context) {
    final f = widget.data.forecast;
    final d = context.dent;
    if (!f.ready) return _NotYet(f: f);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: "What's coming",
          subtitle:
              'Worked out from ${f.dataDays} days of your own records — '
              'estimates, not promises',
          trailing: _Confidence(level: f.confidence),
        ),
        _Outlook(f: f, horizon: _h, onHorizon: (h) => setState(() => _h = h)),
        const SizedBox(height: 18),
        _MonthEnd(f: f),
        const SizedBox(height: 18),
        _Week(f: f),
        const SizedBox(height: 18),
        HubTwoUp(
          left: _InOut(f: f),
          right: _OwedBack(f: f),
        ),
        const SizedBox(height: 18),
        HubTwoUp(
          left: _AtRisk(f: f),
          right: _Heat(f: f),
          leftFlex: 5,
          rightFlex: 6,
        ),
        const SizedBox(height: 18),
        _Year(f: f),
        const SizedBox(height: 6),
        Text(
          'All figures follow the branch picked at the top. '
          'Hide numbers hides them here too.',
          style: TextStyle(color: d.text4, fontSize: 9.sp),
        ),
      ],
    );
  }
}

// ───────────────────────────── outlook (pick how far ahead) ─────────────────

class _Outlook extends StatelessWidget {
  const _Outlook({
    required this.f,
    required this.horizon,
    required this.onHorizon,
  });

  final HubForecast f;
  final HubHorizon horizon;
  final ValueChanged<HubHorizon> onHorizon;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final o = hubOutlook(f, horizon);
    final title = horizon == HubHorizon.today
        ? 'Today should bring in about ${hubRs(o.mid, hidden: hidden)}'
        : 'Next ${horizon.label.toLowerCase()}: about ${hubRs(o.mid, hidden: hidden)}';

    Widget stat(String label, Widget value, String sub) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: d.text3, fontSize: 9.4.sp),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: value,
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(color: d.text4, fontSize: 9.sp),
          ),
        ],
      ),
    );
    final big = TextStyle(
      fontFamily: AppFonts.display,
      color: d.text1,
      fontSize: 14.sp,
      fontWeight: FontWeight.w800,
    );

    return HubCard(
      icon: Icons.travel_explore_rounded,
      tone: d.ice,
      title: title,
      subtitle:
          'Likely between ${hubRs(o.low, hidden: hidden)} and '
          '${hubRs(o.high, hidden: hidden)}',
      trailing: _Confidence(level: o.confidence),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in HubHorizon.values)
                  _Chip(
                    label: h.label,
                    on: h == horizon,
                    onTap: () => onHorizon(h),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: HubGrid(
              minWidth: 190,
              maxColumns: 4,
              gap: 12,
              children: [
                stat(
                  'Expected to come in',
                  Text(
                    hubRs(o.mid, hidden: hidden),
                    style: big.copyWith(color: d.teal),
                  ),
                  '${o.openDays} open day${o.openDays == 1 ? '' : 's'}',
                ),
                stat(
                  'Expected visits',
                  Text('${o.visits}', style: big),
                  'at your usual booking pace',
                ),
                stat(
                  'Usual spending',
                  Text(
                    hubRs(o.spend, hidden: hidden),
                    style: big.copyWith(color: d.warn),
                  ),
                  f.expenseMonths == 0
                      ? 'no expenses recorded yet'
                      : 'from your last ${f.expenseMonths} month${f.expenseMonths == 1 ? '' : 's'}',
                ),
                stat(
                  'Left over',
                  Text(
                    hubRs(o.net, hidden: hidden),
                    style: big.copyWith(color: o.net < 0 ? d.alert : d.ok),
                  ),
                  'coming in minus spending',
                ),
              ],
            ),
          ),
          _How(
            horizon.days <= 31
                ? 'Each open day ahead is filled with what that weekday usually '
                      'brings in over the last 8 weeks (closed days count as '
                      'nothing). The range uses a quieter and a busier week. '
                      'Visits use the usual number of bookings per weekday.'
                : 'The same weekday pace, carried forward day by day for '
                      '${horizon.label}. It assumes your recent pace simply '
                      'continues — no growth, no new chairs or dentists. The '
                      'range widens with how much your months usually differ, '
                      'so the further ahead, the rougher the number.',
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Material(
      color: on ? d.ice.withValues(alpha: .15) : d.surface2,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? d.ice : d.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? d.ice : d.text2,
              fontSize: 9.8.sp,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// "How we worked this out" — the plain-words method under each estimate.
class _How extends StatelessWidget {
  const _How(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        iconColor: d.text3,
        collapsedIconColor: d.text3,
        title: Text(
          'How we worked this out',
          style: TextStyle(
            color: d.ice,
            fontSize: 9.6.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          Text(
            text,
            style: TextStyle(color: d.text2, fontSize: 9.6.sp, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Confidence extends StatelessWidget {
  const _Confidence({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    const words = ['', 'Rough', 'Fair', 'Good', 'Strong', 'Very strong'];
    return Tooltip(
      message:
          'Grows with how much history there is and how steady your days are',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: d.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confidence',
              style: TextStyle(color: d.text3, fontSize: 9.4.sp),
            ),
            const SizedBox(width: 10),
            for (var i = 1; i <= 5; i++)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: i <= level ? d.teal : d.line,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 6),
            Text(
              words[level.clamp(0, 5)],
              style: TextStyle(
                color: d.text1,
                fontSize: 9.6.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotYet extends StatelessWidget {
  const _NotYet({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final have = f.dataDays.clamp(0, kForecastMinDays);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HubSectionTitle(
          title: "What's coming",
          subtitle: 'Estimates worked out from your own records',
        ),
        HubCard(
          icon: Icons.auto_graph_rounded,
          tone: d.ice,
          title: 'Forecasts start on ${hubDate(f.startsOn)}',
          subtitle:
              'The Hub needs $kForecastMinDays days of your records first',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Guessing from a few weeks would give numbers that look '
                  'sure but are not. Once there are $kForecastMinDays days '
                  'of payments and appointments, this page shows the month-'
                  'end estimate, the coming week, money in and out, owed '
                  'money coming back, regulars at risk, busy hours and the '
                  'year ahead.',
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

// ───────────────────────────── month end ─────────────────────────────

class _MonthEnd extends StatelessWidget {
  const _MonthEnd({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final now = DateTime.now();
    final month = hubMonthName(now);
    final delta = hubDelta(f.monthMid, f.lastMonthTotal, 'last month');

    return HubCard(
      icon: Icons.auto_graph_rounded,
      tone: d.ice,
      title: '$month will end at about ${hubRs(f.monthMid, hidden: hidden)}',
      subtitle:
          'Likely between ${hubRs(f.monthLow, hidden: hidden)} and '
          '${hubRs(f.monthHigh, hidden: hidden)} · '
          '${hubRs(f.monthSoFar, hidden: hidden)} collected so far',
      trailing: delta == null
          ? null
          : HubPill(
              delta.text,
              delta.good == null ? d.text3 : (delta.good! ? d.ok : d.alert),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _MonthPainter(
                  f: f,
                  today: now.day,
                  hidden: hidden,
                  actual: d.teal,
                  ahead: d.ice,
                  grid: d.line,
                  label: d.text3,
                  textStyle: TextStyle(color: d.text3, fontSize: 9.sp),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _legend(d, d.teal, 'Collected so far', dashed: false),
                _legend(
                  d,
                  d.ice,
                  'Expected for the rest of the month',
                  dashed: true,
                ),
              ],
            ),
          ),
          const _How(
            'We took each weekday over the last 8 weeks (only days the clinic '
            'was open) and worked out what that weekday usually brings in. '
            'Every day left this month is filled with its usual amount — today '
            'counts as whichever is more: what came in already or a usual day. '
            'The range uses a quieter-than-usual week (low) and a busier one '
            '(high) for each weekday.',
          ),
        ],
      ),
    );
  }

  static Widget _legend(
    DentColors d,
    Color c,
    String text, {
    required bool dashed,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 3,
        decoration: BoxDecoration(
          color: dashed ? c.withValues(alpha: .6) : c,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(color: d.text3, fontSize: 9.2.sp),
      ),
    ],
  );
}

class _MonthPainter extends CustomPainter {
  _MonthPainter({
    required this.f,
    required this.today,
    required this.hidden,
    required this.actual,
    required this.ahead,
    required this.grid,
    required this.label,
    required this.textStyle,
  });

  final HubForecast f;
  final int today;
  final bool hidden;
  final Color actual, ahead, grid, label;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final days = f.projected.length;
    if (days == 0) return;
    const left = 8.0, bottom = 22.0, top = 10.0, right = 8.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    final maxV = math
        .max(1, [f.monthHigh, ...f.cumulative].reduce(math.max))
        .toDouble();
    double x(int day) => left + (day - 1) / math.max(1, days - 1) * w;
    double y(num v) => top + h - (v / maxV) * h;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final yy = top + h * i / 3;
      canvas.drawLine(Offset(left, yy), Offset(left + w, yy), gridPaint);
    }

    void text(String s, Offset at, {TextAlign align = TextAlign.center}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.center
          ? at.dx - tp.width / 2
          : (align == TextAlign.right ? at.dx - tp.width : at.dx);
      final maxX = math.max(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx.clamp(0.0, maxX), at.dy));
    }

    for (final dd in {1, 8, 15, 22, days}) {
      text('$dd', Offset(x(dd), size.height - 16));
    }

    // range at month end
    final rangePaint = Paint()
      ..color = ahead.withValues(alpha: .18)
      ..style = PaintingStyle.fill;
    final lastX = x(days);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(lastX - 7, y(f.monthHigh), lastX + 7, y(f.monthLow)),
        const Radius.circular(6),
      ),
      rangePaint,
    );

    // expected path (dashed)
    final dash = Paint()
      ..color = ahead
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;
    final pts = <Offset>[
      Offset(x(today), y(f.cumulative.isEmpty ? 0 : f.cumulative.last)),
      for (var dd = today + 1; dd <= days; dd++)
        Offset(x(dd), y(f.projected[dd - 1])),
    ];
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final len = (b - a).distance;
      const on = 6.0, off = 5.0;
      var t = 0.0;
      while (t < len) {
        final s = a + (b - a) * (t / len);
        final e = a + (b - a) * (math.min(t + on, len) / len);
        canvas.drawLine(s, e, dash);
        t += on + off;
      }
    }

    // collected so far (solid)
    final path = Path();
    for (var i = 0; i < f.cumulative.length; i++) {
      final p = Offset(x(i + 1), y(f.cumulative[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = actual
        ..strokeWidth = 3.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = actual;
    if (f.cumulative.isNotEmpty) {
      canvas.drawCircle(Offset(x(today), y(f.cumulative.last)), 5, dot);
    }
    canvas.drawCircle(Offset(lastX, y(f.monthMid)), 5, Paint()..color = ahead);
    if (!hidden) {
      text(
        '≈ ${hubRs(f.monthMid)}',
        Offset(lastX - 10, y(f.monthMid) - 22),
        align: TextAlign.right,
      );
    }
  }

  @override
  bool shouldRepaint(_MonthPainter old) =>
      old.f != f || old.hidden != hidden || old.actual != actual;
}

// ───────────────────────────── next 7 days ─────────────────────────────

class _Week extends StatelessWidget {
  const _Week({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final light = f.week.where((w) => w.light).length;
    final top = f.week.fold<double>(
      1,
      (m, w) => math.max(m, math.max(w.booked.toDouble(), w.usual)),
    );

    return HubCard(
      icon: Icons.date_range_rounded,
      tone: d.teal,
      title: 'Next 7 days',
      subtitle: light == 0
          ? 'Bookings look normal for the week ahead'
          : '$light light day${light == 1 ? '' : 's'} — room to book more patients',
      trailing: const HubGoLink('Appointments', HubGo.appointments),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: HubGrid(
              minWidth: 128,
              maxColumns: 7,
              gap: 10,
              children: [
                for (final w in f.week)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: w.light
                          ? d.warn.withValues(alpha: .08)
                          : d.surface2,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: w.light ? d.warn.withValues(alpha: .4) : d.line,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${hubWeekday(w.day).substring(0, 3)} ${w.day.day}',
                          style: TextStyle(
                            color: d.text1,
                            fontSize: 10.2.sp,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (w.closed)
                          SizedBox(
                            height: 56,
                            child: Center(
                              child: Text(
                                'Closed',
                                style: TextStyle(
                                  color: d.text4,
                                  fontSize: 9.6.sp,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          SizedBox(
                            height: 56,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _bar(w.booked / top, d.ice),
                                const SizedBox(width: 6),
                                _bar(w.usual / top, d.line),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${w.booked} booked',
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 9.6.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'usual ${w.usual.toStringAsFixed(w.usual < 10 ? 1 : 0)}',
                            style: TextStyle(color: d.text3, fontSize: 9.sp),
                          ),
                          Text(
                            '~${hubRs(w.usualMoney, hidden: hidden)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: d.text3, fontSize: 9.sp),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const _How(
            '"Booked" is every appointment already in the book for that day. '
            '"Usual" is how many visits that weekday had on average over the '
            'last 8 weeks, and the amount is what that weekday usually brings '
            'in. A day booked under 60% of usual is marked as room to fill.',
          ),
        ],
      ),
    );
  }

  static Widget _bar(double f, Color c) => Expanded(
    child: FractionallySizedBox(
      heightFactor: f.clamp(.04, 1).toDouble(),
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: c,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
    ),
  );
}

// ───────────────────────────── money in vs out ─────────────────────────────

class _InOut extends StatelessWidget {
  const _InOut({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final top = math.max(1, math.max(f.in30, f.out30));
    return HubCard(
      icon: Icons.swap_vert_rounded,
      tone: d.teal,
      title: 'Next 30 days: money in vs money out',
      subtitle: f.net30 >= 0
          ? 'More should come in than go out'
          : 'Usual spending is higher than usual income',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Column(
              children: [
                HubShareRow(
                  label: 'Expected to come in',
                  amount: f.in30,
                  fraction: f.in30 / top,
                  color: d.teal,
                ),
                HubShareRow(
                  label: 'Usual monthly spending',
                  amount: f.out30,
                  fraction: f.out30 / top,
                  color: d.warn,
                  note: f.expenseMonths == 0
                      ? 'no expenses yet'
                      : 'avg of ${f.expenseMonths} month${f.expenseMonths == 1 ? '' : 's'}',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Left over',
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 10.4.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    HubAmount(
                      f.net30,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: f.net30 < 0 ? d.alert : d.ok,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const _How(
            'Coming in: every open day of the next 30 at its usual weekday '
            'amount. Going out: the average of your recorded expenses over the '
            'last three whole months (rent, salaries, supplies, payouts…).',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── owed money coming back ─────────────────────

class _OwedBack extends StatelessWidget {
  const _OwedBack({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final total = f.owedTotal;
    return HubCard(
      icon: Icons.replay_circle_filled_outlined,
      tone: d.warn,
      title: 'Owed money coming back',
      subtitle: total == 0
          ? 'Nobody owes the clinic anything'
          : (f.owedHistory == 0
                ? 'Not enough paid-off bills yet to judge'
                : 'About ${hubRs(f.owedLikely, hidden: hidden)} of '
                      '${hubRs(total, hidden: hidden)} is likely to be paid'),
      trailing: const HubGoLink('Billing', HubGo.billing),
      child: Column(
        children: [
          if (total == 0)
            const HubEmpty('Every bill is paid.', icon: Icons.verified_outlined)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: Column(
                children: [
                  for (final o in f.owedBack)
                    if (o.owed > 0)
                      HubShareRow(
                        label: o.label,
                        amount: o.owed,
                        fraction: f.owedHistory == 0 ? 0 : o.rate,
                        color: o.rate >= .5
                            ? d.ok
                            : (o.rate >= .25 ? d.warn : d.alert),
                        note: f.owedHistory == 0
                            ? null
                            : '${(o.rate * 100).round()}% usually paid',
                      ),
                ],
              ),
            ),
          _How(
            f.owedHistory == 0
                ? 'We need at least 15 bills that are 3–12 months old to see how '
                      'your patients usually pay. Until then this only shows what '
                      'is owed.'
                : 'We looked at ${f.owedHistory} of your bills from 3 to 12 '
                      'months ago and saw how much of the money still owed at '
                      'each age was paid later. Bars show that share for each '
                      'age — older debts come back less often.',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── regulars at risk ─────────────────────────────

class _AtRisk extends StatelessWidget {
  const _AtRisk({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return HubCard(
      icon: Icons.person_search_outlined,
      tone: d.alert,
      title: f.atRiskTotal == 0
          ? 'No regulars at risk'
          : '${f.atRiskTotal} regular${f.atRiskTotal == 1 ? '' : 's'} may not come back',
      subtitle: 'Late for their usual visit, nothing booked',
      child: Column(
        children: [
          if (f.atRisk.isEmpty)
            const HubEmpty(
              'Every regular patient is on their usual rhythm.',
              icon: Icons.favorite_border_rounded,
            )
          else
            for (final p in f.atRisk)
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
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 10.2.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${p.code} · ${p.visits} visits · usually every '
                            '${p.usualGap} days',
                            style: TextStyle(color: d.text3, fontSize: 9.sp),
                          ),
                        ],
                      ),
                    ),
                    if (p.phone.isNotEmpty) ...[
                      SelectableText(
                        p.phone,
                        style: TextStyle(color: d.text2, fontSize: 9.6.sp),
                      ),
                      const SizedBox(width: 12),
                    ],
                    HubPill('${p.daysSince} days since', d.alert),
                  ],
                ),
              ),
          const _How(
            'A regular is someone with at least 3 separate courses of '
            'treatment. We take the usual gap between their visits; once they '
            'are half that gap late (and at least a month), with nothing '
            'booked, they show here. Patients away for over two years are left '
            'out. A call usually brings them back.',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── busy hours ─────────────────────────────

class _Heat extends StatelessWidget {
  const _Heat({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hours = f.heatTo - f.heatFrom;
    var top = 0.0;
    var best = (w: 0, h: 0), quiet = (w: 0, h: 0);
    var quietV = double.infinity;
    for (var w = 0; w < f.heat.length; w++) {
      final rowTotal = f.heat[w].fold<double>(0, (s, v) => s + v);
      for (var h = 0; h < f.heat[w].length; h++) {
        final v = f.heat[w][h];
        if (v > top) {
          top = v;
          best = (w: w, h: h);
        }
        // quiet = least booked hour on a day the clinic is actually used
        if (rowTotal > 0 && v < quietV) {
          quietV = v;
          quiet = (w: w, h: h);
        }
      }
    }

    String slot(({int w, int h}) s) =>
        '${days[s.w]} ${hubHour((f.heatFrom + s.h) * 60)}';

    return HubCard(
      icon: Icons.grid_on_rounded,
      tone: d.ice,
      title: 'When the chairs are full',
      subtitle: top == 0
          ? 'Not enough bookings yet'
          : 'Busiest ${slot(best)} · quietest ${slot(quiet)}',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40),
                    for (var h = 0; h < hours; h++)
                      Expanded(
                        child: Text(
                          h % 2 == 0
                              ? hubHour((f.heatFrom + h) * 60).split(' ').first
                              : '',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: d.text4, fontSize: 9.sp),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (var w = 0; w < f.heat.length; w++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            days[w],
                            style: TextStyle(color: d.text3, fontSize: 9.2.sp),
                          ),
                        ),
                        for (var h = 0; h < hours; h++)
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${days[w]} ${hubHour((f.heatFrom + h) * 60)}: '
                                  '${f.heat[w][h].toStringAsFixed(1)} bookings a week',
                              child: Container(
                                height: 24,
                                margin: const EdgeInsets.all(1.5),
                                decoration: BoxDecoration(
                                  color: top == 0 || f.heat[w][h] == 0
                                      ? d.surface2
                                      : d.ice.withValues(
                                          alpha:
                                              .15 + .85 * (f.heat[w][h] / top),
                                        ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const _How(
            'Each square is the average number of bookings that start in that '
            'hour on that weekday, over the last 8 weeks. Darker means busier. '
            'Light squares in opening hours are the slots to offer first.',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── year ahead ─────────────────────────────

class _Year extends StatelessWidget {
  const _Year({required this.f});
  final HubForecast f;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final year = DateTime.now().year;
    const names = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final top = math.max(1, f.months.fold<int>(0, math.max)).toDouble();
    final vsLast = hubDelta(f.yearMid, f.lastYearTotal, '${year - 1}');

    return HubCard(
      icon: Icons.calendar_month_rounded,
      tone: d.teal,
      title: '$year should end at about ${hubRs(f.yearMid, hidden: hidden)}',
      subtitle:
          'Likely between ${hubRs(f.yearLow, hidden: hidden)} and '
          '${hubRs(f.yearHigh, hidden: hidden)}',
      trailing: vsLast == null
          ? null
          : HubPill(
              vsLast.text,
              vsLast.good == null ? d.text3 : (vsLast.good! ? d.ok : d.alert),
            ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 12; i++)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${hubMonthName(DateTime(year, i + 1))}: '
                            '${hubRs(f.months[i], hidden: hidden)}'
                            '${i < f.monthIndex ? '' : ' (expected)'}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor: math.max(
                                    .03,
                                    f.months[i] / top,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: i < f.monthIndex
                                          ? d.teal
                                          : (i == f.monthIndex
                                                ? d.ice
                                                : d.ice.withValues(alpha: .3)),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(5),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                names[i],
                                style: TextStyle(
                                  color: i == f.monthIndex ? d.ice : d.text4,
                                  fontSize: 9.sp,
                                  fontWeight: i == f.monthIndex
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const _How(
            'Months already over show what was actually collected. This month '
            'uses the month-end estimate above. Every later month uses the '
            'average of your last three whole months; the range widens by how '
            'much your months usually vary.',
          ),
        ],
      ),
    );
  }
}
