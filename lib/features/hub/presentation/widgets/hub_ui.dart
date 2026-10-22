import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';

/// Shared state every Hub widget can read without passing it down:
/// whether amounts are hidden, and how to leave the Hub for a screen.
class HubScope extends InheritedWidget {
  const HubScope({
    super.key,
    required this.hidden,
    required this.onGo,
    required super.child,
  });

  final bool hidden;
  final void Function(HubGo go, {String? arg, String? label}) onGo;

  static HubScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HubScope>()!;

  @override
  bool updateShouldNotify(HubScope old) => old.hidden != hidden;
}

// ─────────────────────────────── formatting ───────────────────────────────

String hubDigits(int v) => v.abs().toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// "Rs 1,24,500"-style amount with its sign; masked when [hidden].
String hubRs(int v, {bool hidden = false}) {
  if (hidden) return 'Rs ••••••';
  return '${v < 0 ? '– ' : ''}Rs ${hubDigits(v)}';
}

const _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _wd = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String hubClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String hubHour(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h ${h24 < 12 ? 'AM' : 'PM'}';
}

String hubDate(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';
String hubShortDate(DateTime d) => '${d.day} ${_mon[d.month - 1]}';
String hubMonthName(DateTime d) => _monLong[d.month - 1];
String hubWeekday(DateTime d) => _wd[d.weekday - 1];

/// "3 min ago", "2 h ago", "4 days ago".
String hubAgo(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  final days = d.inDays;
  return days == 1 ? 'yesterday' : '$days days ago';
}

/// A change against an earlier figure, e.g. "▲ 12% vs last Wed".
class HubDelta {
  const HubDelta(this.text, this.good);
  final String text;

  /// null = neutral.
  final bool? good;
}

HubDelta? hubDelta(int cur, int prev, String vs, {bool upIsGood = true}) {
  if (prev <= 0) return cur > 0 ? HubDelta('New vs $vs', null) : null;
  final pct = ((cur - prev) / prev * 100).round();
  if (pct == 0) return HubDelta('Same as $vs', null);
  final up = pct > 0;
  return HubDelta('${up ? '▲' : '▼'} ${pct.abs()}% vs $vs', up == upIsGood);
}

// ─────────────────────────────── building blocks ──────────────────────────

Widget hubIconTile(
  DentColors d,
  IconData icon,
  Color tone, {
  double size = 40,
}) => Container(
  width: size,
  height: size,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: tone.withValues(alpha: .13),
    borderRadius: BorderRadius.circular(size * .3),
  ),
  child: Icon(icon, size: size * .48, color: tone),
);

/// Amount text that turns into dots when numbers are hidden.
class HubAmount extends StatelessWidget {
  const HubAmount(this.amount, {super.key, required this.style});
  final int amount;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    hubRs(amount, hidden: HubScope.of(context).hidden),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

class HubPill extends StatelessWidget {
  const HubPill(
    this.text,
    this.tone, {
    super.key,
    this.icon,
    this.maxLines = 1,
  });
  final String text;
  final Color tone;
  final IconData? icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone,
              fontSize: 9.2.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A card with an icon, a title line and its content.
class HubCard extends StatelessWidget {
  const HubCard({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
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
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
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
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(color: d.text3, fontSize: 9.4.sp),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: d.line),
          child,
        ],
      ),
    );
  }
}

/// One headline figure: label, value, a line of detail, a change pill and
/// an optional split bar.
class HubKpi extends StatelessWidget {
  const HubKpi({
    super.key,
    required this.label,
    this.amount,
    this.value,
    this.sub,
    this.delta,
    this.segments = const [],
    this.valueColor,
  }) : assert(amount != null || value != null);

  final String label;

  /// Money — hidden with "Hide numbers". Use [value] for counts.
  final int? amount;
  final String? value;
  final String? sub;
  final HubDelta? delta;
  final List<(double, Color)> segments;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final valueStyle = TextStyle(
      fontFamily: AppFonts.display,
      color: valueColor ?? d.text1,
      fontSize: 17.sp,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    final deltaTone = delta?.good == null
        ? d.text3
        : (delta!.good! ? d.ok : d.alert);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: d.text3,
              fontSize: 9.6.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Shrinks a long figure to fit instead of cutting it to "Rs 24,…".
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: amount != null
                ? HubAmount(amount!, style: valueStyle)
                : Text(value!, maxLines: 1, style: valueStyle),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: d.text3, fontSize: 9.2.sp, height: 1.35),
            ),
          ],
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 10),
            HubSegBar(segments),
          ],
          if (delta != null) ...[
            const SizedBox(height: 10),
            HubPill(delta!.text, deltaTone, maxLines: 2),
          ],
        ],
      ),
    );
  }
}

/// A thin bar split into coloured parts (fractions of the whole).
class HubSegBar extends StatelessWidget {
  const HubSegBar(this.segments, {super.key, this.height = 7});
  final List<(double, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final total = segments.fold<double>(0, (s, e) => s + e.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: d.line,
        child: total <= 0
            ? null
            : Row(
                children: [
                  for (final s in segments)
                    if (s.$1 > 0)
                      Expanded(
                        flex: (s.$1 / total * 1000).round().clamp(1, 1000),
                        child: Container(color: s.$2),
                      ),
                ],
              ),
      ),
    );
  }
}

/// Label · amount row with a bar showing its share.
class HubShareRow extends StatelessWidget {
  const HubShareRow({
    super.key,
    required this.label,
    required this.amount,
    required this.fraction,
    required this.color,
    this.note,
  });

  final String label;
  final int amount;
  final double fraction;
  final Color color;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (note != null) ...[
                Text(
                  note!,
                  style: TextStyle(color: d.text3, fontSize: 9.2.sp),
                ),
                const SizedBox(width: 10),
              ],
              HubAmount(
                amount,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1).toDouble(),
              minHeight: 7,
              backgroundColor: d.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class HubEmpty extends StatelessWidget {
  const HubEmpty(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 28, color: d.text4),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: d.text3, fontSize: 10.sp, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Big section heading at the top of each Hub page.
class HubSectionTitle extends StatelessWidget {
  const HubSectionTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title, subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: d.text1,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(color: d.text3, fontSize: 10.sp),
              ),
            ],
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Lays children out in equal columns that wrap on narrow windows.
class HubGrid extends StatelessWidget {
  const HubGrid({
    super.key,
    required this.children,
    this.minWidth = 230,
    this.maxColumns = 5,
    this.gap = 16,
    this.equalHeight = true,
  });

  final List<Widget> children;
  final double minWidth, gap;
  final int maxColumns;

  /// Cards in one row share the tallest card's height, so their tops,
  /// bottoms and bars line up. Children must not contain a LayoutBuilder.
  final bool equalHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (children.isEmpty) return const SizedBox.shrink();
      final cols = (c.maxWidth / minWidth).floor().clamp(1, maxColumns);
      final n = children.length < cols ? children.length : cols;
      if (!equalHeight) {
        final w = (c.maxWidth - gap * (n - 1)) / n;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += n) {
        final row = children.sublist(i, (i + n).clamp(0, children.length));
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < n; j++) ...[
                  if (j > 0) SizedBox(width: gap),
                  Expanded(
                    child: j < row.length ? row[j] : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var k = 0; k < rows.length; k++) ...[
            if (k > 0) SizedBox(height: gap),
            rows[k],
          ],
        ],
      );
    },
  );
}

/// Two panes side by side on wide windows, stacked on narrow ones.
class HubTwoUp extends StatelessWidget {
  const HubTwoUp({
    super.key,
    required this.left,
    required this.right,
    this.breakAt = 980,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  final Widget left, right;
  final double breakAt;
  final int leftFlex, rightFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < breakAt
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 18), right],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: leftFlex, child: left),
              const SizedBox(width: 18),
              Expanded(flex: rightFlex, child: right),
            ],
          ),
  );
}

/// The small "Open …" link in a card's corner. Leaving the Hub asks first.
class HubGoLink extends StatelessWidget {
  const HubGoLink(this.label, this.go, {super.key, this.arg});
  final String label;
  final HubGo go;
  final String? arg;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return TextButton.icon(
      onPressed: () => HubScope.of(context).onGo(go, arg: arg, label: label),
      style: TextButton.styleFrom(foregroundColor: d.ice),
      icon: Icon(Icons.open_in_new_rounded, size: 15, color: d.ice),
      label: Text(
        label,
        style: TextStyle(fontSize: 9.6.sp, fontWeight: FontWeight.w700),
      ),
    );
  }
}
