import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/hub/data/hub_security.dart';

import '../data/owner_phones.dart';

/// Connect a phone: Hub PIN → QR → Approve (same code on both screens).
Future<void> showPairPhoneDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _PairPhoneDialog(),
);

enum _Step { pin, scan, approve, finishing, done, failed }

class _PairPhoneDialog extends ConsumerStatefulWidget {
  const _PairPhoneDialog();
  @override
  ConsumerState<_PairPhoneDialog> createState() => _PairPhoneDialogState();
}

class _PairPhoneDialogState extends ConsumerState<_PairPhoneDialog> {
  /// A QR refreshes by itself at most this many times, then the dialog stops.
  static const _maxRefresh = 5;

  final _pinCtrl = TextEditingController();
  final _pinFocus = FocusNode();
  late final OwnerPhonesApi _api;

  _Step _step = _Step.pin;
  bool _busy = false;
  String? _error;

  /// The PIN, kept only while this dialog is open so a QR can refresh.
  String _pin = '';
  User? _owner;

  PairTicket? _ticket;
  PairStatus? _status;
  String _code = '';
  int _refreshes = 0;
  int _secondsLeft = 0;
  String _failure = '';
  String _connectedModel = '';

  Timer? _poll, _tick;
  int _gen = 0; // bumps on every new QR — old answers are ignored
  bool _polling = false;

  /// When the current step runs out (after a phone claimed the code).
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _api = ref.read(ownerPhonesApiProvider); // never touched through ref later
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    final t = _ticket;
    if (t != null && _step != _Step.done && _step != _Step.failed) {
      _api.cancel(t); // the QR dies on the server too
    }
    _pin = '';
    _pinCtrl.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  // ── step 1: the owner's Hub PIN ──────────────────────────────────────
  Future<void> _submitPin() async {
    final pin = _pinCtrl.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'Enter your 4 to 6 digit Hub PIN.');
      return;
    }
    final session = ref.read(authControllerProvider);
    if (session == null || session.role != AppRole.owner) {
      setState(() => _error = 'Only the owner can connect a phone.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final sec = ref.read(hubSecurityProvider);
    final db = ref.read(appDatabaseProvider);
    try {
      final owner = await sec.userFor(session);
      if (!mounted) return;
      if (owner == null || !sec.hasPin(owner)) {
        setState(() {
          _busy = false;
          _error = PhoneApiError('no_pin').message;
        });
        return;
      }
      // Checked here first: a typo is caught at once, with this computer's
      // lockout, before the server counts it.
      final check = await sec.checkPin(owner, session, pin);
      if (!mounted) return;
      if (!check.ok) {
        _pinCtrl.clear();
        setState(() {
          _busy = false;
          _error = check.result == HubCheckResult.locked
              ? PhoneApiError('locked', until: check.until).message
              : PhoneApiError('wrong_pin', triesLeft: check.triesLeft).message;
        });
        return;
      }
      _owner = owner;
      _pin = pin;
      var by = '';
      try {
        by = 'Computer ${(await db.localDevice()).letter}';
      } catch (_) {}
      await _newTicket(by: by);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is PhoneApiError
            ? e.message
            : PhoneApiError('server').message;
      });
    }
  }

  // ── step 2: a fresh QR, watched every 2 seconds ──────────────────────
  Future<void> _newTicket({String by = ''}) async {
    final owner = _owner;
    if (owner == null) return;
    final gen = ++_gen;
    _poll?.cancel();
    _tick?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await _api.retryAfterPinSync(
        owner,
        () => _api.start(_pin, by: by),
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _ticket = t;
        _status = null;
        _code = '';
        _deadline = null;
        _step = _Step.scan;
        _busy = false;
        _secondsLeft = _remaining(t.expiresAt);
      });
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || gen != _gen) return;
        setState(() => _secondsLeft = _remaining(_deadline ?? t.expiresAt));
      });
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _checkStatus(gen),
      );
    } on PhoneApiError catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _busy = false;
        if (_step == _Step.pin) {
          _error = e.message;
        } else {
          _fail(e.message);
        }
      });
    }
  }

  int _remaining(DateTime until) =>
      until.difference(DateTime.now()).inSeconds.clamp(0, 999);

  Future<void> _checkStatus(int gen) async {
    final t = _ticket;
    if (t == null || _polling) return;
    _polling = true;
    try {
      final s = await _api.status(t);
      if (!mounted || gen != _gen) return;
      _apply(s, t);
    } on PhoneApiError catch (e) {
      if (!mounted || gen != _gen) return;
      if (e.code == 'offline' || e.code == 'server') return; // try again in 2 s
      _stop();
      // After Approve, "invalid" means the phone already finished and the
      // one-time code was used up — the phone IS connected.
      if (e.code == 'invalid' && _step == _Step.finishing) {
        ref.invalidate(phonesOverviewProvider);
        setState(() {
          _connectedModel = _status?.model ?? 'The phone';
          _step = _Step.done;
          _pin = '';
        });
        return;
      }
      setState(() => _fail(e.message));
    } finally {
      _polling = false;
    }
  }

  void _apply(PairStatus s, PairTicket t) {
    if (s.status != 'waiting') {
      _deadline = DateTime.now().add(Duration(seconds: s.expiresIn));
    }
    switch (s.status) {
      case 'waiting':
        setState(() => _status = s);
      case 'claimed':
        final key = s.pubkey ?? '';
        setState(() {
          _status = s;
          _code = key.isEmpty ? '' : OwnerPhonesApi.pairCode(t.k, key);
          if (_step == _Step.scan) _step = _Step.approve;
        });
      case 'approved':
        setState(() {
          _status = s;
          _step = _Step.finishing;
        });
      case 'done':
        _stop();
        ref.invalidate(phonesOverviewProvider);
        setState(() {
          _connectedModel = s.model ?? 'The phone';
          _step = _Step.done;
          _pin = '';
        });
      case 'expired':
        _stop();
        if (_step == _Step.scan && _refreshes < _maxRefresh) {
          _refreshes++;
          unawaited(
            _newTicket(),
          ); // a new QR, same PIN, nobody has to type again
        } else {
          setState(
            () => _fail(
              _step == _Step.scan
                  ? 'The code expired. Start again when the phone is ready.'
                  : 'Time ran out before the phone finished. Please start again.',
            ),
          );
        }
      case 'locked':
        _stop();
        setState(
          () => _fail(
            'A wrong owner number was typed on a phone 3 times, so this '
            'pairing was stopped for safety.',
          ),
        );
      case 'rejected':
        _stop();
        setState(() => _fail('The phone was not connected.'));
      default: // cancelled — usually another computer started a new QR
        _stop();
        setState(
          () => _fail(
            'This code was cancelled, maybe because a new one was made on '
            'another computer.',
          ),
        );
    }
  }

  void _stop() {
    _poll?.cancel();
    _tick?.cancel();
  }

  void _fail(String message) {
    _failure = message;
    _step = _Step.failed;
    _busy = false;
  }

  // ── step 3: owner decides ────────────────────────────────────────────
  Future<void> _approve() async {
    final t = _ticket;
    if (t == null) return;
    setState(() => _busy = true);
    try {
      await _api.approve(t);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.finishing;
      });
    } on PhoneApiError catch (e) {
      if (!mounted) return;
      _stop();
      setState(() => _fail(e.message));
    }
  }

  Future<void> _reject() async {
    final t = _ticket;
    if (t == null) return;
    setState(() => _busy = true);
    _stop();
    try {
      await _api.reject(t);
    } catch (_) {}
    if (!mounted) return;
    setState(
      () => _fail('The phone was not connected. Nothing was shared with it.'),
    );
  }

  void _startAgain() {
    _refreshes = 0;
    if (_pin.isNotEmpty && _owner != null) {
      unawaited(_newTicket());
    } else {
      setState(() {
        _step = _Step.pin;
        _error = null;
      });
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Dialog(
      backgroundColor: d.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(d),
              const SizedBox(height: 18),
              _steps(d),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(key: ValueKey(_step), child: _body(d)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(DentColors d) => Row(
    children: [
      Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: d.ice.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.phonelink_lock_rounded, color: d.ice, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect a phone',
              style: TextStyle(
                color: d.text1,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Owner only · up to 2 phones',
              style: TextStyle(color: d.text3, fontSize: 10.sp),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Close',
        onPressed: _busy && _step == _Step.pin
            ? null
            : () => Navigator.of(context).pop(),
        icon: Icon(Icons.close_rounded, color: d.text3),
      ),
    ],
  );

  Widget _steps(DentColors d) {
    final at = switch (_step) {
      _Step.pin => 0,
      _Step.scan => 1,
      _Step.approve || _Step.finishing => 2,
      _Step.done => 3,
      _Step.failed => -1,
    };
    Widget chip(int i, String label) {
      final done = at > i, now = at == i;
      final c = done || now ? d.ice : d.text4;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: now ? d.ice.withValues(alpha: .12) : d.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: now ? d.ice.withValues(alpha: .5) : d.line,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: c,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: done || now ? d.text1 : d.text3,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(0, 'Hub PIN'),
        const SizedBox(width: 8),
        chip(1, 'Scan'),
        const SizedBox(width: 8),
        chip(2, 'Approve'),
      ],
    );
  }

  Widget _body(DentColors d) => switch (_step) {
    _Step.pin => _pinBody(d),
    _Step.scan => _scanBody(d),
    _Step.approve => _approveBody(d),
    _Step.finishing => _finishingBody(d),
    _Step.done => _doneBody(d),
    _Step.failed => _failedBody(d),
  };

  Widget _text(DentColors d, String s, {Color? color, double? size}) => Text(
    s,
    style: TextStyle(
      color: color ?? d.text2,
      fontSize: (size ?? 10.5).sp,
      height: 1.45,
    ),
  );

  Widget _pinBody(DentColors d) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _text(
        d,
        'Enter your Hub PIN — the same PIN that opens the Detailed Reporting '
        'Hub. It is checked on this computer and again by the DentOS server.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _pinCtrl,
        focusNode: _pinFocus,
        autofocus: true,
        obscureText: true,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: TextStyle(
          color: d.text1,
          fontSize: 18.sp,
          letterSpacing: 10,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          counterText: '',
          hintText: '• • • •',
          hintStyle: TextStyle(color: d.text4, fontSize: 16.sp),
          filled: true,
          fillColor: d.surface2,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: d.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: d.ice, width: 1.6),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: d.line),
          ),
        ),
        onSubmitted: (_) => _busy ? null : _submitPin(),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _errorBox(d, _error!),
      ],
      const SizedBox(height: 20),
      Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
              minimumSize: const Size(140, 48),
            ),
            onPressed: _busy ? null : _submitPin,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Text('Continue', style: TextStyle(fontSize: 10.5.sp)),
          ),
        ],
      ),
    ],
  );

  Widget _scanBody(DentColors d) {
    final t = _ticket;
    final s = _status;
    final triesLeft = s?.triesLeft ?? 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: d.line),
            ),
            child: t == null || _busy
                ? const SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : QrImageView(
                    data: t.qrData,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'Code changes in ${_mmss(_secondsLeft)}',
            style: TextStyle(
              color: _secondsLeft <= 20 ? d.alert : d.text3,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _instruction(d, '1', 'Open the DentOS Owner app on your phone.'),
        _instruction(d, '2', 'Tap Connect to clinic and scan this code.'),
        _instruction(d, '3', 'Type the owner mobile number when asked.'),
        // Developer builds only: the QR text for tool/phone_pair_sim.dart.
        if (kDebugMode && t != null && !_busy)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: t.qrData));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Copied for the phone simulator.'),
                  ),
                );
              },
              icon: const Icon(Icons.bug_report_outlined, size: 16),
              label: Text(
                'Copy for simulator (debug only)',
                style: TextStyle(fontSize: 9.5.sp),
              ),
            ),
          ),
        if (triesLeft < 3) ...[
          const SizedBox(height: 10),
          _errorBox(
            d,
            'A wrong owner number was typed on a phone. '
            '$triesLeft ${triesLeft == 1 ? 'try' : 'tries'} left before this code stops.',
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: d.text4),
            const SizedBox(width: 8),
            Expanded(
              child: _text(
                d,
                'The code works once and holds no clinic details.',
                color: d.text3,
                size: 9.5,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _instruction(DentColors d, String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: d.ice.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: Text(
            n,
            style: TextStyle(
              color: d.ice,
              fontSize: 9.5.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _text(d, text, color: d.text1)),
      ],
    ),
  );

  Widget _approveBody(DentColors d) {
    final s = _status;
    final code = _code.length == 6
        ? '${_code.substring(0, 3)} ${_code.substring(3)}'
        : '— — —';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: d.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: d.line),
          ),
          child: Row(
            children: [
              Icon(
                s?.platform == 'ios'
                    ? Icons.phone_iphone_rounded
                    : Icons.phone_android_rounded,
                color: d.ice,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s?.model ?? 'Phone',
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${s?.platformLabel ?? 'Phone'} · owner number ending ${s?.phoneLast4 ?? '••••'}',
                      style: TextStyle(color: d.text3, fontSize: 10.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'CODE ON THIS COMPUTER',
            style: TextStyle(
              color: d.text4,
              fontSize: 9.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            code,
            style: TextStyle(
              color: d.ice,
              fontSize: 28.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _text(
          d,
          'Is the same code showing on the phone? Approve only if it matches '
          'and this is your phone.',
          color: d.text1,
        ),
        const SizedBox(height: 6),
        Text(
          'Waiting ${_mmss(_secondsLeft)}',
          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.alert,
                  side: BorderSide(color: d.alert.withValues(alpha: .45)),
                  minimumSize: const Size(0, 50),
                ),
                onPressed: _busy ? null : _reject,
                icon: const Icon(Icons.block_rounded, size: 18),
                label: Text('No — reject', style: TextStyle(fontSize: 10.5.sp)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size(0, 50),
                ),
                onPressed: _busy || _code.isEmpty ? null : _approve,
                icon: const Icon(Icons.verified_user_rounded, size: 18),
                label: Text(
                  'Yes — approve',
                  style: TextStyle(fontSize: 10.5.sp),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _finishingBody(DentColors d) => Column(
    children: [
      const SizedBox(height: 10),
      const SizedBox(
        width: 44,
        height: 44,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      const SizedBox(height: 18),
      Text(
        'Approved — finishing on the phone…',
        style: TextStyle(
          color: d.text1,
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      _text(d, 'Keep the DentOS Owner app open.', color: d.text3),
      const SizedBox(height: 10),
    ],
  );

  Widget _doneBody(DentColors d) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(Icons.verified_rounded, color: d.ice, size: 56),
      const SizedBox(height: 12),
      Center(
        child: Text(
          '$_connectedModel is connected',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: d.text1,
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 8),
      _text(
        d,
        'If the clinic WhatsApp is connected, the owner number also gets a '
        'WhatsApp alert. You can disconnect this phone any time from '
        'Settings → Connected phones.',
        color: d.text2,
      ),
      const SizedBox(height: 20),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: d.ice,
          foregroundColor: AppPalette.onAccent,
          minimumSize: const Size.fromHeight(50),
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: Text('Done', style: TextStyle(fontSize: 10.5.sp)),
      ),
    ],
  );

  Widget _failedBody(DentColors d) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(Icons.gpp_maybe_rounded, color: d.alert, size: 52),
      const SizedBox(height: 12),
      _errorBox(d, _failure),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: d.text2,
                side: BorderSide(color: d.line),
                minimumSize: const Size(0, 50),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(fontSize: 10.5.sp)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: d.ice,
                foregroundColor: AppPalette.onAccent,
                minimumSize: const Size(0, 50),
              ),
              onPressed: _busy ? null : _startAgain,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Start again', style: TextStyle(fontSize: 10.5.sp)),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _errorBox(DentColors d, String message) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: d.alert.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: d.alert.withValues(alpha: .35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, color: d.alert, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: d.text1, fontSize: 10.sp, height: 1.4),
          ),
        ),
      ],
    ),
  );

  static String _mmss(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
