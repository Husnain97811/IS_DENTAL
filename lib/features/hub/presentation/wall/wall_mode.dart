import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../../data/hub_score.dart';
import '../widgets/health_score.dart';
import '../widgets/hub_ui.dart';

/// Seconds each slide stays up — the choices offered.
const kWallIntervals = [10, 20, 30, 60];

/// Settings key for the chosen interval.
const kWallIntervalKey = 'hub_wall_interval';

/// Wall mode — a calm, large, rotating view of the clinic for a monitor in
/// the owner's office. Amounts stay hidden until the PIN is entered (the
/// screen around it decides — [HubScope.hidden]); leaving needs the PIN too.
class WallMode extends StatefulWidget {
  const WallMode({
    super.key,
    required this.data,
    required this.clinic,
    required this.scope,
    required this.revealUntil,
    required this.seconds,
    required this.paused,
    required this.onSeconds,
    required this.onAskExit,
    required this.onAskReveal,
    required this.onHide,
  });

  final HubData data;
  final String clinic, scope;

  /// Amounts show until then (null = hidden).
  final DateTime? revealUntil;

  /// How long each slide stays up.
  final int seconds;

  /// Stops the rotation (a PIN prompt is open).
  final bool paused;
  final ValueChanged<int> onSeconds;
  final VoidCallback onAskExit, onAskReveal, onHide;

  @override
  State<WallMode> createState() => _WallModeState();
}

class _WallModeState extends State<WallMode>
    with SingleTickerProviderStateMixin {
  static const _slideCount = 6;
  static const _shifts = [
    Offset.zero,
    Offset(6, -4),
    Offset(-5, 5),
    Offset(4, 6),
    Offset(-6, -3),
  ];

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  )..addStatusListener(_onTick);

  final _focus = FocusNode();
  int _index = 0;
  bool _userPaused = false, _controls = false;
  int _shift = 0;
  Timer? _hideControls, _burnIn;

  @override
  void initState() {
    super.initState();
    _burnIn = Timer.periodic(const Duration(minutes: 3), (_) {
      if (mounted) setState(() => _shift = (_shift + 1) % _shifts.length);
    });
    _run();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(WallMode old) {
    super.didUpdateWidget(old);
    if (old.seconds != widget.seconds) {
      _progress.duration = Duration(seconds: widget.seconds);
      _progress.value = 0;
      _run();
    }
    if (old.paused != widget.paused) {
      _run();
      if (!widget.paused) _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _burnIn?.cancel();
    _progress.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTick(AnimationStatus s) {
    if (s == AnimationStatus.completed) _go(1);
  }

  /// Runs or stops the slide timer to match the pause state.
  void _run() {
    if (widget.paused || _userPaused) {
      _progress.stop();
    } else {
      _progress.forward();
    }
  }

  void _go(int step) {
    if (!mounted) return;
    setState(() => _index = (_index + step) % _slideCount);
    _progress.forward(from: 0);
    if (widget.paused || _userPaused) _progress.stop();
  }

  void _togglePause() {
    setState(() => _userPaused = !_userPaused);
    _run();
  }

  void _showControls() {
    if (!_controls) setState(() => _controls = true);
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) {
      _go(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _go(_slideCount - 1);
    } else if (k == LogicalKeyboardKey.space) {
      _togglePause();
    } else if (k == LogicalKeyboardKey.escape) {
      widget.onAskExit();
    } else {
      return KeyEventResult.ignored;
    }
    _showControls();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final slide = switch (_index) {
      0 => _Today(data: widget.data),
      1 => _ChairsNow(today: widget.data.today),
      2 => _Month(data: widget.data),
      3 => _Tomorrow(today: widget.data.today),
      4 => _Alerts(alerts: widget.data.alerts),
      _ => _Health(score: widget.data.scores.clinic),
    };

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _controls ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: (_) => _showControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showControls,
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: AnimatedContainer(
              // a few pixels every 3 minutes, so nothing burns into a TV
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOut,
              transform: Matrix4.translationValues(
                _shifts[_shift].dx,
                _shifts[_shift].dy,
                0,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4.w.clamp(24.0, 72.0),
                  vertical: 3.h.clamp(18.0, 48.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      clinic: widget.clinic,
                      scope: widget.scope,
                      revealUntil: widget.revealUntil,
                    ),
                    SizedBox(height: 3.h.clamp(14.0, 40.0)),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(.02, 0),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_index),
                          child: slide,
                        ),
                      ),
                    ),
                    SizedBox(height: 2.h.clamp(10.0, 28.0)),
                    _BottomBar(
                      index: _index,
                      count: _slideCount,
                      progress: _progress,
                      paused: _userPaused,
                      controls: _controls,
                      revealed: widget.revealUntil != null,
                      seconds: widget.seconds,
                      onPrev: () => _go(_slideCount - 1),
                      onNext: () => _go(1),
                      onPause: _togglePause,
                      onSeconds: widget.onSeconds,
                      onReveal: widget.revealUntil != null
                          ? widget.onHide
                          : widget.onAskReveal,
                      onExit: widget.onAskExit,
                      tone: d.ice,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── helpers ─────────────────────────────

/// "Ayesha Khan" → "Ayesha K." — enough for staff, little for visitors.
String _short(String full) {
  final parts = full.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'Patient';
  if (parts.length == 1) return parts.first;
  return '${parts.first} ${parts.last[0].toUpperCase()}.';
}

/// Amounts inside alert text, masked when numbers are hidden.
String _mask(String s, bool hidden) =>
    hidden ? s.replaceAll(RegExp(r'Rs\s?[\d,]+'), 'Rs ••••') : s;

TextStyle _hero(DentColors d, {Color? color}) => TextStyle(
  fontFamily: AppFonts.display,
  color: color ?? d.text1,
  fontSize: 30.sp,
  fontWeight: FontWeight.w800,
  height: 1.05,
);

TextStyle _big(DentColors d, {Color? color}) => TextStyle(
  fontFamily: AppFonts.display,
  color: color ?? d.text1,
  fontSize: 17.sp,
  fontWeight: FontWeight.w700,
  height: 1.15,
);

TextStyle _body(DentColors d, {Color? color, FontWeight? weight}) => TextStyle(
  color: color ?? d.text2,
  fontSize: 12.sp,
  fontWeight: weight,
  height: 1.35,
);

TextStyle _label(DentColors d) => TextStyle(
  color: d.text3,
  fontSize: 10.5.sp,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.1,
);

class _SlideFrame extends StatelessWidget {
  const _SlideFrame({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final Color tone;
  final String title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            hubIconTile(d, icon, tone, size: 56),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      color: d.text1,
                      fontSize: 21.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(subtitle, style: _body(d, color: d.text3)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Expanded(child: child),
      ],
    );
  }
}

/// A big number with its label, shrinking to fit its box.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub, this.color});

  final String label, value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: _label(d)),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: _hero(d, color: color)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 8),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _body(d, color: d.text3),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _statRow(List<Widget> stats) => Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < stats.length; i++) ...[
      if (i > 0) const SizedBox(width: 22),
      Expanded(child: stats[i]),
    ],
  ],
);

// ───────────────────────────── top / bottom ─────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.clinic,
    required this.scope,
    required this.revealUntil,
  });

  final String clinic, scope;
  final DateTime? revealUntil;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: d.accentGradient,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.insights_rounded,
            color: AppPalette.onAccent,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clinic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: d.text1,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                revealUntil == null
                    ? '$scope · amounts hidden'
                    : '$scope · amounts showing until ${hubClock(revealUntil!)}',
                style: _body(d, color: revealUntil == null ? d.text3 : d.warn),
              ),
            ],
          ),
        ),
        const _Clock(),
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute && mounted) setState(() => _now = n);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          hubClock(_now),
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: d.text1,
            fontSize: 21.sp,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        Text(
          '${hubWeekday(_now)} ${hubDate(_now)}',
          style: _body(d, color: d.text3),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.count,
    required this.progress,
    required this.paused,
    required this.controls,
    required this.revealed,
    required this.seconds,
    required this.onPrev,
    required this.onNext,
    required this.onPause,
    required this.onSeconds,
    required this.onReveal,
    required this.onExit,
    required this.tone,
  });

  final int index, count, seconds;
  final Animation<double> progress;
  final bool paused, controls, revealed;
  final VoidCallback onPrev, onNext, onPause, onReveal, onExit;
  final ValueChanged<int> onSeconds;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WallButton(
          icon: Icons.chevron_left_rounded,
          tip: 'Previous (←)',
          onTap: onPrev,
        ),
        _WallButton(
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          tip: paused ? 'Play (Space)' : 'Pause (Space)',
          onTap: onPause,
        ),
        _WallButton(
          icon: Icons.chevron_right_rounded,
          tip: 'Next (→)',
          onTap: onNext,
        ),
        const SizedBox(width: 6),
        PopupMenuButton<int>(
          tooltip: 'Time per slide',
          color: d.surface,
          onSelected: onSeconds,
          itemBuilder: (_) => [
            for (final s in kWallIntervals)
              PopupMenuItem(
                value: s,
                child: Text(
                  '$s seconds${s == seconds ? '  ✓' : ''}',
                  style: TextStyle(color: d.text1, fontSize: 10.sp),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.timer_outlined, size: 20, color: d.text2),
                const SizedBox(width: 6),
                Text('${seconds}s', style: _body(d)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onReveal,
          style: OutlinedButton.styleFrom(
            foregroundColor: revealed ? d.warn : d.text2,
            side: BorderSide(color: revealed ? d.warn : d.line),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          icon: Icon(
            revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 19,
          ),
          label: Text(
            revealed ? 'Hide amounts' : 'Show amounts',
            style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onExit,
          style: OutlinedButton.styleFrom(
            foregroundColor: d.alert,
            side: BorderSide(color: d.alert.withValues(alpha: .5)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          icon: const Icon(Icons.logout_rounded, size: 19),
          label: Text(
            'Leave wall mode',
            style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: i == index ? 34 : 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: i == index ? tone : d.line,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: AnimatedBuilder(
            animation: progress,
            builder: (context, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.value,
                minHeight: 4,
                backgroundColor: d.line,
                valueColor: AlwaysStoppedAnimation(
                  paused ? d.text4 : tone.withValues(alpha: .7),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: controls ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(ignoring: !controls, child: buttons),
        ),
      ],
    );
  }
}

class _WallButton extends StatelessWidget {
  const _WallButton({
    required this.icon,
    required this.tip,
    required this.onTap,
  });

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    onPressed: onTap,
    iconSize: 28,
    icon: Icon(icon, color: context.dent.text2),
  );
}

// ───────────────────────────── slides ─────────────────────────────

class _Today extends StatelessWidget {
  const _Today({required this.data});
  final HubData data;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final t = data.today;
    final now = DateTime.now();
    final seen = t.count('completed');
    final inClinic = t.count('inChair') + t.count('waiting');
    final toCome = t.count('upcoming');
    final next = t.appts
        .where((a) => a.status == 'upcoming' && a.startsAt.isAfter(now))
        .firstOrNull;
    return _SlideFrame(
      icon: Icons.today_rounded,
      tone: d.ice,
      title: 'Today',
      subtitle: '${hubWeekday(now)} ${hubDate(now)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statRow([
              _Stat(
                label: 'Patients today',
                value: '${t.patients}',
                sub: '$seen seen · $inClinic in the clinic · $toCome to come',
              ),
              _Stat(
                label: 'Collected today',
                value: hubRs(t.collected, hidden: hidden),
                color: d.teal,
                sub: t.collected == 0 ? 'Nothing collected yet' : null,
              ),
            ]),
          ),
          const SizedBox(height: 22),
          _NextLine(
            text: next == null
                ? (toCome == 0
                      ? 'No more bookings today.'
                      : 'Everyone booked is already in.')
                : 'Next: ${hubClock(next.startsAt)} · ${_short(next.patient)}'
                      '${next.procedure.isEmpty ? '' : ' · ${next.procedure}'}'
                      '${next.dentist.isEmpty ? '' : ' · ${next.dentist}'}',
          ),
        ],
      ),
    );
  }
}

class _NextLine extends StatelessWidget {
  const _NextLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: d.ice.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: d.ice, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _body(d, color: d.text1, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChairsNow extends StatelessWidget {
  const _ChairsNow({required this.today});
  final HubToday today;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final now = DateTime.now();
    final inChair = today.appts.where((a) => a.status == 'inChair').toList();
    final waiting = today.appts.where((a) => a.status == 'waiting').toList();
    final next = today.appts
        .where((a) => a.status == 'upcoming' && !a.startsAt.isBefore(now))
        .take(4)
        .toList();

    Widget column(
      String title,
      Color tone,
      List<HubAppt> list,
      String empty,
      String Function(HubAppt) sub, {
      bool Function(HubAppt)? overdue,
    }) => Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: d.line),
      ),
      // more names than fit are clipped, never an overflow stripe
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title.toUpperCase(), style: _label(d))),
                Text('${list.length}', style: _big(d, color: tone)),
              ],
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              Text(empty, style: _body(d, color: d.text3))
            else
              for (final a in list.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _short(a.patient),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _big(d),
                      ),
                      Text(
                        sub(a),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _body(
                          d,
                          color: overdue != null && overdue(a)
                              ? d.alert
                              : d.text3,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );

    String who(HubAppt a) => [
      if (a.procedure.isNotEmpty) a.procedure,
      if (a.dentist.isNotEmpty) a.dentist,
    ].join(' · ');

    return _SlideFrame(
      icon: Icons.event_seat_outlined,
      tone: d.teal,
      title: 'In the clinic now',
      subtitle: 'Who is being seen, who is waiting, who is next',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: column(
              'In the chair',
              d.teal,
              inChair,
              'No one in a chair right now',
              (a) => who(a).isEmpty ? 'Since ${hubClock(a.startsAt)}' : who(a),
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: column(
              'Waiting',
              d.warn,
              waiting,
              'No one waiting',
              (a) {
                final m = now.difference(a.startsAt).inMinutes;
                return m > 0
                    ? 'Booked ${hubClock(a.startsAt)} · $m min past'
                    : 'Booked ${hubClock(a.startsAt)}';
              },
              overdue: (a) => now.difference(a.startsAt).inMinutes > 20,
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: column(
              'Up next',
              d.ice,
              next,
              'No more bookings today',
              (a) =>
                  '${hubClock(a.startsAt)}${who(a).isEmpty ? '' : ' · ${who(a)}'}',
            ),
          ),
        ],
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({required this.data});
  final HubData data;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final t = data.today;
    final f = data.forecast;
    final now = DateTime.now();
    final delta = hubDelta(
      t.monthCollected,
      t.lastMonthToDate,
      'the same days last month',
    );
    final target = f.ready ? f.monthMid : 0;
    final share = target <= 0
        ? null
        : (t.monthCollected / target).clamp(0.0, 1.0);

    return _SlideFrame(
      icon: Icons.calendar_month_rounded,
      tone: d.ok,
      title: hubMonthName(now),
      subtitle: 'Money in so far, and where the month should end',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statRow([
              _Stat(
                label: 'Collected so far',
                value: hubRs(t.monthCollected, hidden: hidden),
                color: d.teal,
                sub: delta?.text,
              ),
              _Stat(
                label: 'Month should end at',
                value: f.ready ? hubRs(f.monthMid, hidden: hidden) : '—',
                sub: f.ready
                    ? 'Likely ${hubRs(f.monthLow, hidden: hidden)} to '
                          '${hubRs(f.monthHigh, hidden: hidden)}'
                    : 'Estimates start on ${hubDate(f.startsOn)}',
              ),
            ]),
          ),
          if (share != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: share.toDouble(),
                      minHeight: 18,
                      backgroundColor: d.line,
                      valueColor: AlwaysStoppedAnimation(d.teal),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  '${(share * 100).round()}% of the way',
                  style: _body(d, color: d.text1, weight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tomorrow extends StatelessWidget {
  const _Tomorrow({required this.today});
  final HubToday today;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final list = today.tomorrow;
    final day = DateTime.now().add(const Duration(days: 1));
    final shown = list.take(8).toList();
    return _SlideFrame(
      icon: Icons.event_note_rounded,
      tone: d.warn,
      title: 'Tomorrow · ${list.length} booking${list.length == 1 ? '' : 's'}',
      subtitle: list.isEmpty
          ? '${hubWeekday(day)} ${hubDate(day)}'
          : '${hubWeekday(day)} ${hubDate(day)} · first at '
                '${hubClock(list.first.startsAt)}, last at '
                '${hubClock(list.last.startsAt)}',
      child: list.isEmpty
          ? Center(
              child: Text(
                'Nothing booked for tomorrow yet.',
                style: _big(d, color: d.text3),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final two = c.maxWidth > 900 && shown.length > 4;
                final half = (shown.length / 2).ceil();
                Widget rows(List<HubAppt> l) => Column(
                  children: [
                    for (final a in l)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: d.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: d.line),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 12.sp * 6, // fits "10:30 PM"
                              child: Text(
                                hubClock(a.startsAt),
                                style: _body(
                                  d,
                                  color: d.ice,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                [
                                  _short(a.patient),
                                  if (a.procedure.isNotEmpty) a.procedure,
                                  if (a.dentist.isNotEmpty) a.dentist,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _body(d, color: d.text1),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                return SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (two)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: rows(shown.sublist(0, half))),
                            const SizedBox(width: 18),
                            Expanded(child: rows(shown.sublist(half))),
                          ],
                        )
                      else
                        rows(shown.take(5).toList()),
                      if (list.length > (two ? 8 : 5))
                        Text(
                          '+ ${list.length - (two ? 8 : 5)} more',
                          style: _body(d, color: d.text3),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.alerts});
  final List<HubAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    if (alerts.isEmpty) {
      return _SlideFrame(
        icon: Icons.verified_rounded,
        tone: d.ok,
        title: 'All clear',
        subtitle: 'Nothing needs you right now',
        child: Center(
          child: Icon(Icons.check_circle_rounded, color: d.ok, size: 140),
        ),
      );
    }
    final shown = alerts.take(5).toList();
    return _SlideFrame(
      icon: Icons.notifications_active_outlined,
      tone: d.alert,
      title: 'Needs you · ${alerts.length}',
      subtitle: 'Open the Hub to act on these',
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in shown)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: d.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border(
                    left: BorderSide(
                      width: 6,
                      color: switch (a.level) {
                        HubLevel.urgent => d.alert,
                        HubLevel.today => d.warn,
                        HubLevel.later => d.ice,
                      },
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mask(a.title, hidden),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(d, color: d.text1, weight: FontWeight.w700),
                    ),
                    Text(
                      _mask(a.detail, hidden),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(d, color: d.text3),
                    ),
                  ],
                ),
              ),
            if (alerts.length > shown.length)
              Text(
                '+ ${alerts.length - shown.length} more in the Hub',
                style: _body(d, color: d.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _Health extends StatelessWidget {
  const _Health({required this.score});
  final HubScore score;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final delta = hubScoreDelta(score);
    final drags = score.drags.take(3).toList();
    return _SlideFrame(
      icon: Icons.monitor_heart_outlined,
      tone: hubScoreTone(d, score.value),
      title: 'Clinic health',
      subtitle: 'Last 30 days, out of 100',
      child: Row(
        children: [
          LayoutBuilder(
            builder: (context, c) => HubScoreRing(
              value: score.value,
              size: c.maxHeight.clamp(160.0, 320.0),
              caption: score.label,
            ),
          ),
          const SizedBox(width: 48),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      score.label,
                      style: _hero(d, color: hubScoreTone(d, score.value)),
                    ),
                    if (delta != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        delta.text,
                        style: _body(
                          d,
                          color: delta.good == null
                              ? d.text3
                              : (delta.good! ? d.ok : d.alert),
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (drags.isEmpty)
                      Text(
                        score.ready
                            ? 'Nothing is pulling the score down.'
                            : 'The score needs a few more weeks of records.',
                        style: _body(d),
                      )
                    else
                      for (final p in drags)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                hubScorePartIcon(p.key),
                                color: d.warn,
                                size: 30,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.label,
                                      style: _body(
                                        d,
                                        color: d.text1,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      p.text(hidden),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: _body(d, color: d.text3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
