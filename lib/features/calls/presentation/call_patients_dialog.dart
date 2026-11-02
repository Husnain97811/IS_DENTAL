import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../data/call_board.dart';
import '../data/patient_call.dart';

/// Opens the Call patients dialog.
Future<void> showCallPatients(BuildContext context) =>
    showDialog(context: context, builder: (_) => const CallPatientsDialog());

/// Call the next patient to a doctor, go back one, or announce again.
///
/// Arrived / Complete on the Appointments screen are untouched — this only
/// decides who is called. Every computer and the reception screen follow
/// within a second or two.
///
/// Mouse: one click on Next. Previous always asks first.
/// Keyboard: → → (twice) = Next, ← ← (twice) = Previous (then Enter / Esc).
class CallPatientsDialog extends ConsumerStatefulWidget {
  const CallPatientsDialog({super.key});
  @override
  ConsumerState<CallPatientsDialog> createState() => _CallPatientsState();
}

class _CallPatientsState extends ConsumerState<CallPatientsDialog> {
  /// Remembered while the app runs, so reception doesn't re-pick each time.
  static String? _lastDentist;

  final _focus = FocusNode(debugLabel: 'call-patients');
  final _tap = DoubleTap();
  String? _dentist;
  String? _hint;
  Timer? _hintTimer;
  String? _error;
  bool _busy = false;

  // the latest values from build(), for the keyboard
  DoctorQueue? _queue;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _dentist = _lastDentist;
    final board = ref.read(callBoardProvider.notifier);
    Future.microtask(board.refresh);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // ── keyboard ──
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored; // no auto-repeat
    final k = e.logicalKey;
    if (k != LogicalKeyboardKey.arrowRight &&
        k != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final right = k == LogicalKeyboardKey.arrowRight;
    if (_tap.press(k, DateTime.now())) {
      _say(null);
      right ? _next() : _back();
    } else {
      _say(
        right
            ? 'Press → again to call the next patient'
            : 'Press ← again to go back to the previous patient',
      );
    }
    return KeyEventResult.handled;
  }

  void _say(String? hint) {
    _hintTimer?.cancel();
    setState(() => _hint = hint);
    if (hint != null) {
      _hintTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _hint = null);
      });
    }
  }

  // ── actions ──
  Future<void> _next() async {
    final q = _queue;
    final p = q?.next;
    if (_busy || !_online || q == null || p == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(callBoardProvider.notifier).callNext(q, p);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    _focus.requestFocus();
  }

  Future<void> _back() async {
    final q = _queue;
    final cur = q?.current;
    if (_busy || !_online || q == null || cur == null) return;
    final board = ref.read(callBoardProvider.notifier);
    final d = context.dent;
    final prev = q.previous;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Go back to the previous patient?',
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          prev == null
              ? '${cur.patientName} goes back to the waiting list, and no '
                    'one will show as on chair.'
              : '${prev.patientName} will show as on chair again, and '
                    '${cur.patientName} goes back to the waiting list.',
          style: TextStyle(fontSize: 10.5.sp, color: d.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: TextStyle(fontSize: 10.sp)),
          ),
          FilledButton(
            autofocus: true, // Enter confirms, Esc cancels
            style: FilledButton.styleFrom(
              backgroundColor: d.warn,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Go back', style: TextStyle(fontSize: 10.sp)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await board.goBack(q);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _repeat() async {
    final q = _queue;
    if (_busy || !_online || q?.current == null) return;
    setState(() => _busy = true);
    final err = await ref.read(callBoardProvider.notifier).repeat(q!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) _say('Announced again on the reception screen');
    _focus.requestFocus();
  }

  /// The signed-in doctor, else the last one used here, else the first
  /// doctor with someone waiting, else the first doctor.
  String? _pickDentist(
    List<String> dentists,
    List<WaitingPatient> arrived,
    String? me,
  ) {
    if (_dentist != null && dentists.contains(_dentist)) return _dentist;
    if (me != null && dentists.contains(me)) return me;
    for (final a in arrived) {
      if (dentists.contains(a.dentist)) return a.dentist;
    }
    return dentists.isEmpty ? null : dentists.first;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final board = ref.watch(callBoardProvider);
    final arrived = ref.watch(todayArrivalsProvider).value ?? const [];
    final session = ref.watch(authControllerProvider);
    final dentists = <String>{
      ...?ref.watch(dentistsProvider).value,
      for (final a in arrived) a.dentist,
      for (final c in board.calls) c.dentist,
    }.where((n) => n.trim().isNotEmpty).toList();

    final me = session?.role == AppRole.clinician ? session?.fullName : null;
    final dentist = _pickDentist(dentists, arrived, me);
    final q = dentist == null
        ? null
        : buildQueue(dentist: dentist, calls: board.calls, arrived: arrived);
    _queue = q;
    _online = board.online;

    final canNext = _online && !_busy && q?.next != null;
    final canBack = _online && !_busy && q?.current != null;

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (46.w).clamp(520.0, 780.0),
          maxHeight: 90.h,
        ),
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(d, board),
                if (!board.ready && board.reachable)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: d.ice,
                      backgroundColor: d.line,
                    ),
                  ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _doctorPicker(d, dentists, dentist),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8),
                    child: q == null
                        ? _emptyNote(d, 'Add a doctor to see their patients.')
                        : _queueView(d, q),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, right: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: d.alert, fontSize: 9.5.sp),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buttons(d, q, canNext, canBack),
                ),
                const SizedBox(height: 10),
                Text(
                  _hint ??
                      'Keyboard: press → twice for Next, ← twice for Previous',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _hint == null ? d.text4 : d.ice,
                    fontSize: 8.5.sp,
                    fontWeight: _hint == null
                        ? FontWeight.w500
                        : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(DentColors d, CallBoard board) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: d.ice.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(Icons.campaign_rounded, size: 21, color: d.ice),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          'Call patients',
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: d.text1,
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (!board.online && (board.ready || !board.reachable))
        Tooltip(
          message: 'No internet',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.signal_wifi_bad_rounded,
              size: 26,
              color: d.alert,
            ),
          ),
        ),
      IconButton(
        tooltip: 'Close',
        icon: Icon(Icons.close_rounded, size: 20, color: d.text3),
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );

  Widget _doctorPicker(DentColors d, List<String> dentists, String? value) =>
      Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: d.line),
        ),
        child: Row(
          children: [
            Icon(Icons.medical_services_outlined, size: 17, color: d.text3),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  focusColor: Colors.transparent,
                  hint: Text(
                    'Choose a doctor',
                    style: TextStyle(fontSize: 10.5.sp, color: d.text4),
                  ),
                  items: [
                    for (final n in dentists)
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          n,
                          style: TextStyle(
                            fontSize: 10.5.sp,
                            color: d.text1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _dentist = v;
                      _error = null;
                    });
                    _lastDentist = v;
                    _tap.reset();
                    _focus.requestFocus();
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _queueView(DentColors d, DoctorQueue q) {
    final cur = q.current;
    final next = q.next;
    final rest = q.waiting.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── on chair ──
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          decoration: BoxDecoration(
            color: d.ice.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: d.ice.withValues(alpha: .35)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(d, 'ON CHAIR', d.ice),
                    const SizedBox(height: 6),
                    Text(
                      cur?.patientName ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: d.text1,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cur == null
                          ? 'No one called yet today'
                          : 'Called at ${callTime(cur.calledAt)}'
                                '${cur.calledBy == null || cur.calledBy!.isEmpty ? '' : ' by ${cur.calledBy}'}',
                      style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                    ),
                  ],
                ),
              ),
              if (cur != null)
                TextButton.icon(
                  onPressed: _online && !_busy ? _repeat : null,
                  style: TextButton.styleFrom(foregroundColor: d.ice),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: Text('Repeat', style: TextStyle(fontSize: 10.sp)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── next ──
        _label(d, 'NEXT', d.text3),
        const SizedBox(height: 6),
        if (next == null)
          _emptyNote(
            d,
            q.current == null
                ? 'No one is waiting for ${q.dentist}. Patients appear here '
                      'when they are marked as arrived.'
                : 'No one else is waiting for ${q.dentist}.',
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: d.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: d.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    next.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${callTime(next.startsAt)}  ·  ${next.procedure}',
                  style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                ),
              ],
            ),
          ),

        // ── waiting after next ──
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 14),
          _label(d, 'WAITING  ·  ${rest.length}', d.text3),
          const SizedBox(height: 4),
          for (var i = 0; i < rest.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: i == rest.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: d.line),
                    ),
                    child: Text(
                      '${i + 2}',
                      style: TextStyle(
                        color: d.text2,
                        fontSize: 8.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rest[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    callTime(rest[i].startsAt),
                    style: TextStyle(color: d.text3, fontSize: 9.sp),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buttons(DentColors d, DoctorQueue? q, bool canNext, bool canBack) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
    );
    final nextName = q?.next?.name;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: canBack ? _back : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: d.text2,
              side: BorderSide(color: d.line),
              minimumSize: const Size(0, 54),
              shape: shape,
            ),
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            label: Text(
              'Previous',
              style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: FilledButton(
            onPressed: canNext ? _next : null,
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
              minimumSize: const Size(0, 54),
              shape: shape,
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          nextName == null ? 'Next' : 'Call $nextName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, size: 22),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _label(DentColors d, String t, Color c) => Text(
    t,
    style: TextStyle(
      color: c,
      fontSize: 8.5.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: 1,
    ),
  );

  Widget _emptyNote(DentColors d, String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: d.line),
    ),
    child: Text(
      t,
      style: TextStyle(color: d.text3, fontSize: 10.sp),
    ),
  );
}
