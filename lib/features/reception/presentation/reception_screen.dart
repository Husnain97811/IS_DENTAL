import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/core/utils/screen_keeper.dart';
import 'package:is_dental/features/calls/data/call_board.dart';
import 'package:is_dental/features/calls/data/patient_call.dart';
import 'package:is_dental/features/hub/data/activity_log.dart';
import 'package:is_dental/features/showcase/data/showcase_cases.dart';
import 'package:is_dental/features/showcase/presentation/widgets/cropped_photo.dart';

import '../data/announcer.dart';
import '../data/cloud_voice.dart';
import '../data/reception_logic.dart';
import '../data/reception_mode.dart';
import '../data/reception_settings.dart';

// TV palette — dark, high contrast, readable from across the waiting room.
const _bg1 = Color(0xFF061019);
const _bg2 = Color(0xFF0F2A3E);
const _panel = Color(0xFF0E2233);
const _line = Color(0xFF22415A);
const _teal = Color(0xFF13E0C4);
const _ice = Color(0xFF38BDF8);
const _text = Color(0xFFF2F8FB);
const _soft = Color(0xFFA9C1D1);
const _dim = Color(0xFF6E8CA0);
const _alert = Color(0xFFFF6B81);
const _warn = Color(0xFFF5B84B);

/// The waiting-room screen. Opens without a login on a computer the owner
/// turned into a reception screen; leaving needs the owner's password.
///
/// Patient call and Showcase take turns every 5 seconds. A new call jumps
/// straight to the call screen, flashes the name, chimes, announces the
/// full name, and holds for 15 seconds.
class ReceptionScreen extends ConsumerStatefulWidget {
  const ReceptionScreen({super.key});
  @override
  ConsumerState<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends ConsumerState<ReceptionScreen> {
  static const _slide = Duration(seconds: 5);
  static const _hold = Duration(seconds: 15);

  late final _announcer = Announcer(
    voice: CloudVoice(ref.read(cloudServiceProvider).ensureSignedIn),
  );
  final _prefetched = <String>{};
  final _tracker = AnnounceTracker();
  final _rnd = math.Random();
  final _focus = FocusNode(debugLabel: 'reception');

  Timer? _tick;
  bool _showcase = false; // which half of the rotation is on screen
  String? _caseId;
  DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final _flash = <String, DateTime>{}; // call id → flash until
  String? _trackedDay;
  String _clinic = '';
  DateTime _now = DateTime.now();
  DateTime _lastMouse = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    ScreenKeeper.enter();
    ref.read(appDatabaseProvider).clinicName().then((n) {
      if (mounted) setState(() => _clinic = n ?? '');
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _batch?.cancel();
    _announcer.dispose();
    _focus.dispose();
    ScreenKeeper.leave();
    super.dispose();
  }

  /// Every second: the clock, flashes ending, and every 5 s the rotation.
  int _secs = 0;
  void _onTick() {
    if (!mounted) return;
    _now = DateTime.now();
    _flash.removeWhere((_, until) => until.isBefore(_now));
    _secs++;
    if (_secs % 10 == 0) _autoCall();
    if (_now.isAfter(_holdUntil) && _secs % _slide.inSeconds == 0) {
      final cases = _availableCases();
      if (cases.isEmpty) {
        _showcase = false;
      } else {
        _showcase = !_showcase;
        if (_showcase) {
          _caseId = nextCase([for (final c in cases) c.id], _caseId, _rnd);
        }
      }
    }
    setState(() {});
  }

  // the latest queues from build(), for automatic calling
  List<DoctorQueue> _queues = const [];
  Set<String> _arrivedIds = const {};
  final _autoTried = <String, DateTime>{};
  bool _autoBusy = false;

  /// Calls the next patient by itself when the owner turned it on: the
  /// doctor is free and the appointment time has come. Runs only on the
  /// reception screen, so one computer decides; if two screens try at the
  /// same moment the cloud lets only one call through.
  Future<void> _autoCall() async {
    if (_autoBusy) return;
    final mode = ref.read(receptionModeProvider).value;
    if (mode == null) return;
    final s = ref.read(receptionSettingsProvider(mode.branchKey)).value;
    final board = ref.read(callBoardProvider);
    if (s == null || !s.autoCall || !board.online) return;
    final now = DateTime.now();
    final todo = autoCalls(
      queues: _queues,
      stillArrived: _arrivedIds,
      now: now,
      recentlyTried: _autoTried,
    );
    if (todo.isEmpty) return;
    _autoBusy = true;
    try {
      final ctl = ref.read(callBoardProvider.notifier);
      for (final (q, p) in todo) {
        _autoTried[p.appointmentUuid] = now;
        await ctl.callNext(q, p, by: 'DentOS (automatic)');
      }
    } finally {
      _autoBusy = false;
      _autoTried.removeWhere(
        (_, t) => now.difference(t) > const Duration(minutes: 5),
      );
    }
  }

  List<ShowcaseCase> _availableCases() {
    final mode = ref.read(receptionModeProvider).value;
    if (mode == null) return const [];
    final picked = ref
        .read(receptionSettingsProvider(mode.branchKey))
        .value
        ?.cases;
    if (picked == null || picked.isEmpty) return const [];
    final all = ref.read(allShowcaseCasesProvider).value ?? const [];
    // only cases whose photos are on this computer (Drive or transfer)
    return [
      for (final c in all)
        if (picked.contains(c.id) && c.isLocal) c,
    ];
  }

  /// New calls → jump to the call screen, flash, chime + voice, hold.
  void _onCalls(CallBoard board, ReceptionMode mode) {
    if (!board.ready) return;
    if (_trackedDay != board.day) {
      _tracker.reset();
      _trackedDay = board.day;
    }
    final now = DateTime.now();
    // only this screen's branch is announced (whole clinic when key is '')
    final fresh = _tracker
        .update(board.calls, now)
        .where(
          (c) =>
              mode.branchKey.isEmpty ||
              c.branchId == null ||
              c.branchId == mode.branchKey,
        )
        .toList();
    if (fresh.isEmpty) return;
    setState(() {
      _showcase = false;
      _holdUntil = now.add(_hold);
      _secs = 0;
      for (final c in fresh) {
        _flash[c.id] = now.add(_hold);
      }
    });
    // Calls that land within a moment of each other (4 doctors at 10:00,
    // or automatic calling) are announced together: one chime, then each.
    _pending.addAll(fresh);
    _batch?.cancel();
    _batch = Timer(const Duration(milliseconds: 700), () => _flushCalls(mode));
  }

  final _pending = <PatientCall>[];
  Timer? _batch;

  void _flushCalls(ReceptionMode mode) {
    if (!mounted || _pending.isEmpty) return;
    final settings = ref.read(receptionSettingsProvider(mode.branchKey)).value;
    final calls = [
      for (final c in _pending)
        (c.patientName, settings?.roomOf(c.dentist) ?? ''),
    ];
    _pending.clear();
    // keep the call screen up while the names are read out
    final estimate = Duration(
      seconds: 6 + calls.length * (mode.sayTwice ? 6 : 3),
    );
    final until = DateTime.now().add(estimate);
    if (until.isAfter(_holdUntil)) _holdUntil = until;
    // keep the flashing names lit until they have all been spoken
    _flash.updateAll((_, t) => t.isBefore(until) ? until : t);
    _announcer.announceMany(mode, calls).then((_) {
      if (!mounted) return;
      final after = DateTime.now().add(const Duration(seconds: 6));
      if (after.isAfter(_holdUntil)) _holdUntil = after;
    });
  }

  // ── leaving ──
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyQ &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      _askExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int _wrong = 0;
  DateTime _lockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _askExit() async {
    final db = ref.read(appDatabaseProvider);
    final modeCtl = ref.read(receptionModeProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _ExitDialog(
        lockedUntil: _lockedUntil,
        check: (pw) async {
          if (DateTime.now().isBefore(_lockedUntil)) return false;
          final good = await checkOwnerPassword(db, pw);
          if (good) {
            _wrong = 0;
          } else {
            _wrong++;
            unawaited(
              logActivity(
                db,
                'reception_exit_failed',
                userName: 'Reception screen',
                detail: 'Wrong owner password',
              ),
            );
            if (_wrong >= 5) {
              _wrong = 0;
              _lockedUntil = DateTime.now().add(const Duration(minutes: 5));
            }
          }
          return good;
        },
      ),
    );
    _focus.requestFocus();
    if (ok != true) return;
    unawaited(
      logActivity(db, 'reception_off', userName: 'Owner', detail: _clinic),
    );
    await modeCtl.disable(); // router goes to the login screen
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(receptionModeProvider).value;
    if (mode == null) {
      return const Scaffold(backgroundColor: _bg1);
    }
    final ent = ref.watch(entitlementsProvider);
    final board = ref.watch(callBoardProvider);
    final arrivals = ref.watch(todayArrivalsProvider).value ?? const [];
    final settings =
        ref.watch(receptionSettingsProvider(mode.branchKey)).value ??
        ReceptionSettings.empty;
    ref.watch(allShowcaseCasesProvider); // keep the cases loaded
    final lic = ref.watch(licenseControllerProvider).value?.license;

    ref.listen<CallBoard>(callBoardProvider, (_, next) => _onCalls(next, mode));

    // this branch's patients (whole clinic when the key is '')
    final mine = mode.branchKey.isEmpty
        ? arrivals
        : [
            for (final a in arrivals)
              if (a.branchId == null || a.branchId == mode.branchKey) a,
          ];
    final doctors = receptionDoctors(
      settings,
      busyToday: [
        for (final a in mine) a.dentist,
        for (final c in board.calls) c.dentist,
      ],
    );
    final queues = [
      for (final d in doctors)
        buildQueue(dentist: d, calls: board.calls, arrived: mine),
    ];

    final cases = _availableCases();
    _queues = queues;
    _arrivedIds = {for (final a in mine) a.appointmentUuid};

    // Natural voice: save each arrived patient's clip now, so their call
    // plays the moment Next is pressed (and still plays if the internet
    // drops later).
    if (mode.naturalVoice != null) {
      for (final a in mine) {
        if (_prefetched.add(a.appointmentUuid)) {
          _announcer.prefetch(mode, a.name, settings.roomOf(a.dentist));
        }
      }
    }

    ShowcaseCase? shown;
    if (_showcase && cases.isNotEmpty) {
      shown = cases.firstWhere(
        (c) => c.id == _caseId,
        orElse: () => cases.first,
      );
    }

    final daysLeft = lic?.expiresAt.difference(_now).inDays;
    final mouseIdle = _now.difference(_lastMouse) > const Duration(seconds: 3);

    return Scaffold(
      backgroundColor: _bg1,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: mouseIdle ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (_) => _lastMouse = DateTime.now(),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_bg1, _bg2],
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 3.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(board, daysLeft),
                SizedBox(height: 2.5.h),
                Expanded(
                  child: !ent.patientCall
                      ? _message(
                          Icons.lock_outline_rounded,
                          'The reception screen is not on this plan',
                          'Ask the clinic owner to renew with Premium, or '
                              'Standard with the reception add-on.',
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: shown != null
                              ? _ShowcaseSlide(
                                  key: ValueKey('case-${shown.id}'),
                                  c: shown,
                                  clinic: _clinic,
                                )
                              : _CallSlide(
                                  key: const ValueKey('calls'),
                                  queues: queues,
                                  rooms: settings.rooms,
                                  flash: _flash.keys.toSet(),
                                  ready: board.ready,
                                ),
                        ),
                ),
                SizedBox(height: 1.5.h),
                _bottomBar(cases.length, shown != null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(CallBoard board, int? daysLeft) {
    final offline = !board.online && (board.ready || !board.reachable);
    return Row(
      children: [
        Container(
          width: 5.5.h,
          height: 5.5.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_ice, _teal]),
            borderRadius: BorderRadius.circular(1.4.h),
          ),
          child: Icon(Icons.medical_services_rounded, size: 3.h, color: _bg1),
        ),
        SizedBox(width: 1.2.w),
        Expanded(
          child: Text(
            _clinic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.display,
              color: _text,
              fontSize: 3.4.h,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (daysLeft != null && daysLeft <= 7) ...[
          Container(
            padding: EdgeInsets.symmetric(horizontal: 1.w, vertical: 0.7.h),
            decoration: BoxDecoration(
              color: _warn.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(3.h),
              border: Border.all(color: _warn.withValues(alpha: .5)),
            ),
            child: Text(
              daysLeft <= 0
                  ? 'Subscription ends today'
                  : 'Subscription ends in $daysLeft day${daysLeft == 1 ? '' : 's'}',
              style: TextStyle(
                color: _warn,
                fontSize: 1.9.h,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 1.2.w),
        ],
        if (offline) ...[
          Tooltip(
            message: 'No internet',
            child: Icon(
              Icons.signal_wifi_bad_rounded,
              size: 4.h,
              color: _alert,
            ),
          ),
          SizedBox(width: 1.2.w),
        ],
        Text(
          callTime(_now),
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: _text,
            fontSize: 3.4.h,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(int caseCount, bool onShowcase) => Row(
    children: [
      if (caseCount > 0) ...[
        _dot(!onShowcase),
        SizedBox(width: 0.6.w),
        _dot(onShowcase),
      ],
      const Spacer(),
      // Leaving needs the owner's password. Also Ctrl + Shift + Q.
      Opacity(
        opacity: .35,
        child: IconButton(
          tooltip: 'Leave the reception screen',
          onPressed: _askExit,
          icon: Icon(Icons.lock_outline_rounded, size: 2.6.h, color: _dim),
        ),
      ),
    ],
  );

  Widget _dot(bool on) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: on ? 2.6.h : 1.h,
    height: 1.h,
    decoration: BoxDecoration(
      color: on ? _teal : _line,
      borderRadius: BorderRadius.circular(1.h),
    ),
  );

  Widget _message(IconData icon, String title, String body) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 9.h, color: _dim),
        SizedBox(height: 2.h),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: _text,
            fontSize: 4.h,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: _soft, fontSize: 2.4.h),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════ call slide ══
class _CallSlide extends StatelessWidget {
  const _CallSlide({
    super.key,
    required this.queues,
    required this.rooms,
    required this.flash,
    required this.ready,
  });
  final List<DoctorQueue> queues;
  final Map<String, String> rooms; // doctor → room
  final Set<String> flash;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    if (queues.isEmpty) {
      return Center(
        child: Text(
          ready ? 'Welcome — please have a seat' : 'Getting ready…',
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: _soft,
            fontSize: 4.5.h,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final n = queues.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) SizedBox(width: 1.6.w),
          Expanded(
            child: _DoctorColumn(
              q: queues[i],
              columns: n,
              room: shownRoom(rooms[queues[i].dentist] ?? ''),
              flashing:
                  queues[i].current != null &&
                  flash.contains(queues[i].current!.id),
            ),
          ),
        ],
      ],
    );
  }
}

class _DoctorColumn extends StatelessWidget {
  const _DoctorColumn({
    required this.q,
    required this.columns,
    required this.room,
    required this.flashing,
  });
  final DoctorQueue q;
  final int columns;
  final String room; // "Room 5", or ''
  final bool flashing;

  @override
  Widget build(BuildContext context) {
    // the fewer the columns, the bigger the names
    final doc = switch (columns) {
      1 => 6.h,
      2 => 5.h,
      _ => 4.2.h,
    };
    final now = switch (columns) {
      1 => 10.h,
      2 => 8.h,
      _ => 6.4.h,
    };
    final nextTop = switch (columns) {
      1 => 4.6.h,
      2 => 3.9.h,
      _ => 3.3.h,
    };
    final nextRest = switch (columns) {
      1 => 3.8.h,
      2 => 3.3.h,
      _ => 2.8.h,
    };
    final upcoming = q.waiting.take(5).toList();

    return Container(
      padding: EdgeInsets.fromLTRB(2.h, 2.4.h, 2.h, 2.h),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(3.h),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            shownDoctor(q.dentist),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.display,
              color: _teal,
              fontSize: doc,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (room.isNotEmpty) ...[
            SizedBox(height: 0.6.h),
            Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 2.h, vertical: 0.6.h),
                decoration: BoxDecoration(
                  color: _ice.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(3.h),
                  border: Border.all(color: _ice.withValues(alpha: .5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.meeting_room_rounded, size: 2.6.h, color: _ice),
                    SizedBox(width: 0.8.h),
                    Text(
                      room,
                      style: TextStyle(
                        color: _ice,
                        fontSize: 2.6.h,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: 2.h),
          _NowCard(name: q.current?.patientName, size: now, flashing: flashing),
          SizedBox(height: 2.6.h),
          Text(
            'NEXT',
            style: TextStyle(
              color: _dim,
              fontSize: 2.h,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          SizedBox(height: 1.h),
          if (upcoming.isEmpty)
            Text(
              'No one waiting',
              style: TextStyle(color: _dim, fontSize: nextRest),
            )
          else
            for (var i = 0; i < upcoming.length; i++)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 0.7.h),
                child: Row(
                  children: [
                    Container(
                      width: 4.4.h,
                      height: 4.4.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0 ? _ice.withValues(alpha: .18) : null,
                        shape: BoxShape.circle,
                        border: Border.all(color: i == 0 ? _ice : _line),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: i == 0 ? _ice : _soft,
                          fontSize: 2.1.h,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(width: 1.6.h),
                    Expanded(
                      child: Text(
                        upcoming[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: i == 0 ? _text : _soft,
                          fontSize: i == 0 ? nextTop : nextRest,
                          fontWeight: i == 0
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// "ON CHAIR" card. Pulses while a fresh call is being announced.
class _NowCard extends StatefulWidget {
  const _NowCard({
    required this.name,
    required this.size,
    required this.flashing,
  });
  final String? name;
  final double size;
  final bool flashing;
  @override
  State<_NowCard> createState() => _NowCardState();
}

class _NowCardState extends State<_NowCard>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    if (widget.flashing) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_NowCard old) {
    super.didUpdateWidget(old);
    if (widget.flashing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.flashing && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (_, child) {
      final t = _pulse.value;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 2.h, vertical: 2.4.h),
        decoration: BoxDecoration(
          color: Color.lerp(
            _teal.withValues(alpha: .10),
            _teal.withValues(alpha: .30),
            t,
          ),
          borderRadius: BorderRadius.circular(2.4.h),
          border: Border.all(
            color: Color.lerp(_teal.withValues(alpha: .45), _teal, t)!,
            width: 2,
          ),
          boxShadow: [
            if (widget.flashing)
              BoxShadow(
                color: _teal.withValues(alpha: .35 * t),
                blurRadius: 40,
                spreadRadius: 2,
              ),
          ],
        ),
        child: child,
      );
    },
    child: Column(
      children: [
        Text(
          'ON CHAIR',
          style: TextStyle(
            color: _teal,
            fontSize: 2.h,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          widget.name ?? '—',
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: _text,
            fontSize: widget.size,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════ showcase slide ══
class _ShowcaseSlide extends StatelessWidget {
  const _ShowcaseSlide({super.key, required this.c, required this.clinic});
  final ShowcaseCase c;
  final String clinic;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'BEFORE  &  AFTER',
          style: TextStyle(
            color: _soft,
            fontSize: 2.3.h,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          c.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: _text,
            fontSize: 6.h,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 0.6.h),
        Text(
          c.durationLine,
          style: TextStyle(color: _teal, fontSize: 2.8.h),
        ),
        SizedBox(height: 2.4.h),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              const gap = 24.0;
              var w = (box.maxWidth - gap) / 2;
              var h = w * 3 / 4;
              if (h > box.maxHeight) {
                h = box.maxHeight;
                w = h * 4 / 3;
              }
              Widget photo(XrayRow p, NormRect? crop, String tag, Color bg) =>
                  SizedBox(
                    width: w,
                    height: h,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CroppedPhoto(photo: p, crop: crop, dark: true),
                          Positioned(
                            left: 18,
                            bottom: 18,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 2.h,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  photo(
                    c.before,
                    c.beforeCrop,
                    'BEFORE',
                    Colors.black.withValues(alpha: .6),
                  ),
                  const SizedBox(width: gap),
                  photo(c.after, c.afterCrop, 'AFTER', const Color(0xFF0B8C7C)),
                ],
              );
            },
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          clinic,
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: _text,
            fontSize: 3.h,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 0.6.h),
        Text(
          'Real patient  ·  shared with consent  ·  individual results vary',
          style: TextStyle(color: _dim, fontSize: 1.8.h),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════ exit dialog ══
class _ExitDialog extends StatefulWidget {
  const _ExitDialog({required this.check, required this.lockedUntil});
  final Future<bool> Function(String password) check;
  final DateTime lockedUntil;
  @override
  State<_ExitDialog> createState() => _ExitDialogState();
}

class _ExitDialogState extends State<_ExitDialog> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    if (DateTime.now().isBefore(widget.lockedUntil)) {
      setState(() => _error = 'Too many wrong tries — wait 5 minutes.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.check(_pw.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = 'That is not the owner\'s password.';
      _pw.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return AlertDialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Leave the reception screen?',
        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Only the clinic owner can turn this screen off.',
              style: TextStyle(color: d.text2, fontSize: 10.sp),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pw,
              autofocus: true,
              obscureText: true,
              onSubmitted: (_) => _go(),
              style: TextStyle(fontSize: 10.5.sp),
              decoration: InputDecoration(
                labelText: 'Owner password',
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(fontSize: 10.sp)),
        ),
        FilledButton(
          onPressed: _busy ? null : _go,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Turn off', style: TextStyle(fontSize: 10.sp)),
        ),
      ],
    );
  }
}
