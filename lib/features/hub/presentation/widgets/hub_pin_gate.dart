import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_pin.dart';
import '../../data/hub_security.dart';

enum HubGateMode { setup, unlock, reset, change }

enum _Step { password, current, code, pin, confirm }

/// Everything about the Hub PIN in one card: first-time setup (password →
/// PIN → again), unlock, "Forgot PIN?" with a vendor reset code, and
/// change PIN. Five wrong tries lock this computer for five minutes.
class HubPinGate extends ConsumerStatefulWidget {
  const HubPinGate({
    super.key,
    required this.mode,
    required this.user,
    required this.session,
    required this.onDone,
    required this.onExit,
    this.onCancel,
    this.relock = false,
  });

  final HubGateMode mode;
  final User user;
  final AuthSession session;

  /// Unlocked, or a new PIN was saved.
  final VoidCallback onDone;

  /// Leave the Hub.
  final VoidCallback onExit;

  /// Change PIN only — back to the Hub without changing anything.
  final VoidCallback? onCancel;

  /// Locked after a quiet spell (different wording).
  final bool relock;

  @override
  ConsumerState<HubPinGate> createState() => _HubPinGateState();
}

class _HubPinGateState extends ConsumerState<HubPinGate> {
  late HubGateMode _mode = widget.mode;
  late List<_Step> _steps = _stepsFor(_mode);
  int _i = 0;

  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false, _showPassword = false;
  String? _error;
  String _firstPin = '', _code = '';
  DateTime? _lockedUntil;
  Timer? _ticker;
  late final Future<String?> _clinicId = ref
      .read(appDatabaseProvider)
      .currentClinicId();

  _Step get _step => _steps[_i];
  bool get _isPin =>
      _step == _Step.pin || _step == _Step.confirm || _step == _Step.current;

  static List<_Step> _stepsFor(HubGateMode m) => switch (m) {
    HubGateMode.setup => const [_Step.password, _Step.pin, _Step.confirm],
    HubGateMode.unlock => const [_Step.current],
    HubGateMode.reset => const [_Step.code, _Step.pin, _Step.confirm],
    HubGateMode.change => const [_Step.current, _Step.pin, _Step.confirm],
  };

  @override
  void initState() {
    super.initState();
    _refreshLock();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _refreshLock() async {
    final until = await ref.read(hubSecurityProvider).lockedUntil(widget.user);
    if (!mounted) return;
    _setLock(until);
  }

  void _setLock(DateTime? until) {
    _ticker?.cancel();
    setState(() => _lockedUntil = until);
    if (until == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(until)) {
        _ticker?.cancel();
        setState(() {
          _lockedUntil = null;
          _error = null;
        });
        _focus.requestFocus();
      } else {
        setState(() {}); // countdown
      }
    });
  }

  void _go(HubGateMode m) => setState(() {
    _mode = m;
    _steps = _stepsFor(m);
    _i = 0;
    _error = null;
    _firstPin = '';
    _code = '';
    _field.clear();
    _focus.requestFocus();
  });

  void _next() => setState(() {
    _i++;
    _error = null;
    _field.clear();
    _focus.requestFocus();
  });

  void _fail(String msg, {bool clear = true}) => setState(() {
    _error = msg;
    if (clear) _field.clear();
    _focus.requestFocus();
  });

  void _handle(HubCheck c, String wrongWord) {
    switch (c.result) {
      case HubCheckResult.ok:
        return;
      case HubCheckResult.wrong:
        _fail(
          'Wrong $wrongWord · ${c.triesLeft} '
          '${c.triesLeft == 1 ? 'try' : 'tries'} left',
        );
      case HubCheckResult.locked:
        _field.clear();
        _error = null;
        _setLock(c.until);
    }
  }

  Future<void> _submit() async {
    if (_busy || _lockedUntil != null) return;
    final v = _field.text.trim();
    final sec = ref.read(hubSecurityProvider);
    setState(() => _busy = true);
    try {
      switch (_step) {
        case _Step.password:
          if (v.isEmpty) return _fail('Enter your login password.');
          // the password exactly as typed — spaces can be part of it
          final pw = await sec.checkPassword(
            widget.user,
            widget.session,
            _field.text,
          );
          if (pw.ok) return _next();
          _handle(pw, 'password');

        case _Step.current:
          if (v.length < HubPin.minLength) {
            return _fail(
              'Enter your ${HubPin.minLength}–${HubPin.maxLength} digit PIN.',
            );
          }
          final pinCheck = await sec.checkPin(widget.user, widget.session, v);
          if (!pinCheck.ok) return _handle(pinCheck, 'PIN');
          if (_mode == HubGateMode.unlock) return widget.onDone();
          _next();

        case _Step.code:
          final codeCheck = await sec.checkResetCode(widget.user, _field.text);
          if (codeCheck.error != null) {
            return _fail(codeCheck.error!, clear: false);
          }
          _code = _field.text;
          _next();

        case _Step.pin:
          final weak = HubPin.problem(v);
          if (weak != null) return _fail(weak);
          _firstPin = v;
          _next();

        case _Step.confirm:
          if (v != _firstPin) {
            setState(() {
              _i = _steps.indexOf(_Step.pin);
              _firstPin = '';
              _field.clear();
              _error = "The two PINs didn't match. Choose your PIN again.";
            });
            _focus.requestFocus();
            return;
          }
          if (_mode == HubGateMode.reset) {
            final err = await sec.redeemReset(
              widget.user,
              widget.session,
              _code,
              v,
            );
            if (err != null) {
              setState(() {
                _i = 0;
                _error = err;
                _field.text = _code;
              });
              return;
            }
          } else {
            await sec.setPin(
              widget.user,
              widget.session,
              v,
              kind: _mode == HubGateMode.change
                  ? 'hub_pin_changed'
                  : 'hub_pin_set',
            );
          }
          widget.onDone();
      }
    } catch (e) {
      _fail('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────────── text ─────────────────────────────

  String get _title => switch (_step) {
    _Step.password => "First, confirm it's you",
    _Step.current =>
      _mode == HubGateMode.change
          ? 'Enter your current PIN'
          : (widget.relock ? 'The Hub is locked' : 'Enter your Hub PIN'),
    _Step.code => 'Reset your Hub PIN',
    _Step.pin =>
      _mode == HubGateMode.change ? 'Choose a new PIN' : 'Choose your Hub PIN',
    _Step.confirm => 'Enter the PIN again',
  };

  String get _message => switch (_step) {
    _Step.password =>
      'Enter your login password once. Then you will choose a Hub PIN that '
          'protects this screen every time it opens.',
    _Step.current =>
      _mode == HubGateMode.change
          ? 'To change your PIN, enter the one you use now.'
          : (widget.relock
                ? 'Nothing happened for 5 minutes, so the numbers were '
                      'hidden. Enter your PIN to carry on.'
                : 'This screen shows every money figure in the clinic.'),
    _Step.code =>
      'Contact Inover Studio support with your clinic ID and username below. '
          'They will send you a reset code that works once, for one day.',
    _Step.pin => '4 to 6 digits. Avoid 1234, 0000 or your phone number.',
    _Step.confirm => 'Type the same PIN once more so we know it is right.',
  };

  String get _button => switch (_step) {
    _Step.password => 'Continue',
    _Step.current => _mode == HubGateMode.change ? 'Continue' : 'Unlock',
    _Step.code => 'Check code',
    _Step.pin => 'Continue',
    _Step.confirm => 'Save PIN',
  };

  IconData get _icon => switch (_mode) {
    HubGateMode.setup => Icons.shield_outlined,
    HubGateMode.unlock => Icons.lock_outline_rounded,
    HubGateMode.reset => Icons.key_rounded,
    HubGateMode.change => Icons.password_rounded,
  };

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final locked = _lockedUntil != null;
    final left = locked ? _lockedUntil!.difference(DateTime.now()) : null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.fromLTRB(30, 30, 30, 22),
            decoration: BoxDecoration(
              color: d.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: d.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            d.ice.withValues(alpha: .2),
                            d.teal.withValues(alpha: .12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        locked ? Icons.timer_outlined : _icon,
                        color: locked ? d.warn : d.ice,
                        size: 25,
                      ),
                    ),
                    const Spacer(),
                    if (_steps.length > 1) _dots(d),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  locked ? 'Too many wrong tries' : _title,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: d.text1,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  locked
                      ? 'For safety this computer is locked for a few '
                            'minutes. You can try again in '
                            '${left!.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}.'
                      : _message,
                  style: TextStyle(
                    color: d.text2,
                    fontSize: 10.2.sp,
                    height: 1.5,
                  ),
                ),
                if (!locked && _step == _Step.code) ...[
                  const SizedBox(height: 14),
                  _whoAmI(d),
                ],
                const SizedBox(height: 18),
                if (!locked) _input(d),
                if (_error != null && !locked) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 17,
                        color: d.alert,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: d.alert,
                            fontSize: 9.8.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: (_busy || locked) ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppPalette.onAccent,
                            ),
                          )
                        : Text(
                            _button,
                            style: TextStyle(
                              fontSize: 10.6.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                _links(d),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots(DentColors d) => Row(
    children: [
      for (var k = 0; k < _steps.length; k++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(left: 6),
          width: k == _i ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: k <= _i ? d.ice : d.line,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
    ],
  );

  Widget _input(DentColors d) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: d.line),
    );
    final focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: d.ice, width: 1.6),
    );

    if (_step == _Step.code) {
      return TextField(
        controller: _field,
        focusNode: _focus,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        enabled: !_busy,
        style: AppTypography.mono(size: 9.4.sp, color: d.text1),
        decoration: InputDecoration(
          hintText: 'DRH1.…  paste the whole code here',
          hintStyle: TextStyle(color: d.text4, fontSize: 9.6.sp),
          filled: true,
          fillColor: d.surface2,
          border: border,
          enabledBorder: border,
          focusedBorder: focused,
          contentPadding: const EdgeInsets.all(14),
        ),
      );
    }

    if (_step == _Step.password) {
      return TextField(
        controller: _field,
        focusNode: _focus,
        autofocus: true,
        obscureText: !_showPassword,
        enabled: !_busy,
        onSubmitted: (_) => _submit(),
        style: TextStyle(fontSize: 11.sp, color: d.text1),
        decoration: InputDecoration(
          hintText: 'Login password',
          hintStyle: TextStyle(color: d.text4, fontSize: 10.4.sp),
          prefixIcon: Icon(Icons.lock_outline_rounded, color: d.text3),
          suffixIcon: IconButton(
            tooltip: _showPassword ? 'Hide' : 'Show',
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: d.text3,
            ),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
          filled: true,
          fillColor: d.surface2,
          border: border,
          enabledBorder: border,
          focusedBorder: focused,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      );
    }

    // PIN steps
    assert(_isPin);
    return TextField(
      controller: _field,
      focusNode: _focus,
      autofocus: true,
      obscureText: true,
      obscuringCharacter: '●',
      enabled: !_busy,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(HubPin.maxLength),
      ],
      onSubmitted: (_) => _submit(),
      style: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 20.sp,
        letterSpacing: 14,
        color: d.text1,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: '••••',
        hintStyle: TextStyle(
          color: d.text4.withValues(alpha: .5),
          fontSize: 18.sp,
          letterSpacing: 14,
        ),
        filled: true,
        fillColor: d.surface2,
        border: border,
        enabledBorder: border,
        focusedBorder: focused,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  /// Clinic ID + username, to read out to support.
  Widget _whoAmI(DentColors d) => FutureBuilder<String?>(
    future: _clinicId,
    builder: (context, snap) {
      Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: TextStyle(color: d.text3, fontSize: 9.4.sp),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: AppTypography.mono(size: 10.sp, color: d.text1),
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_rounded, size: 16, color: d.text3),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
          ],
        ),
      );
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            row('Clinic ID', snap.data ?? '…'),
            row('Username', widget.user.username),
          ],
        ),
      );
    },
  );

  Widget _links(DentColors d) {
    TextButton link(String text, VoidCallback onTap, {Color? color}) =>
        TextButton(
          onPressed: _busy ? null : onTap,
          style: TextButton.styleFrom(foregroundColor: color ?? d.text2),
          child: Text(
            text,
            style: TextStyle(fontSize: 9.8.sp, fontWeight: FontWeight.w600),
          ),
        );

    final items = <Widget>[];
    switch (_mode) {
      case HubGateMode.unlock:
        items.add(link('Forgot PIN?', () => _go(HubGateMode.reset)));
        items.add(link('Exit Hub', widget.onExit, color: d.alert));
      case HubGateMode.reset:
        items.add(
          link(
            'Back',
            () => _go(
              widget.mode == HubGateMode.reset
                  ? HubGateMode.unlock
                  : widget.mode,
            ),
          ),
        );
        items.add(link('Exit Hub', widget.onExit, color: d.alert));
      case HubGateMode.change:
        items.add(link('Forgot PIN?', () => _go(HubGateMode.reset)));
        items.add(link('Cancel', widget.onCancel ?? widget.onExit));
      case HubGateMode.setup:
        items.add(link('Exit Hub', widget.onExit, color: d.alert));
    }
    return Row(
      mainAxisAlignment: items.length == 1
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceBetween,
      children: items,
    );
  }
}
