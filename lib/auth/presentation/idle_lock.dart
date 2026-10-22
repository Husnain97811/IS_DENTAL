import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/core/utils/app_activity.dart';
import 'auth_controller.dart';

/// Signs the user out after [idleTimeoutProvider] minutes with no activity.
///
/// Activity = a click, scroll, mouse movement or key press anywhere under
/// this widget, plus pings from screens outside it (the Reporting Hub) via
/// [appActivityProvider].
class IdleLock extends ConsumerStatefulWidget {
  const IdleLock({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends ConsumerState<IdleLock> {
  Timer? _t;
  int _mins = 10;
  DateTime _lastReset = DateTime.fromMillisecondsSinceEpoch(0);

  void _reset() {
    _lastReset = DateTime.now();
    _t?.cancel();
    if (_mins <= 0) return; // 0 = disabled
    _t = Timer(Duration(minutes: _mins), _onIdle);
  }

  /// Mouse hover and key presses fire constantly — restart the timer at
  /// most once a second.
  void _soft() {
    if (DateTime.now().difference(_lastReset) >= const Duration(seconds: 1)) {
      _reset();
    }
  }

  bool _onKey(KeyEvent _) {
    _soft();
    return false; // never swallow the key
  }

  void _onIdle() {
    if (!mounted) return;
    if (ref.read(authControllerProvider) != null) {
      ref.read(authControllerProvider.notifier).logout(auto: true);
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // load the stored value, then start the timer
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final m = await ref.read(appDatabaseProvider).idleTimeoutMinutes();
      if (!mounted) return;
      ref.read(idleTimeoutProvider.notifier).state = m;
      _mins = m;
      _reset();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // restart the timer whenever the setting changes
    ref.listen<int>(idleTimeoutProvider, (_, next) {
      _mins = next;
      _reset();
    });
    // activity reported by screens outside this widget (Reporting Hub)
    ref.listen<int>(appActivityProvider, (_, __) => _reset());

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      onPointerMove: (_) => _soft(),
      onPointerHover: (_) => _soft(),
      onPointerSignal: (_) => _reset(),
      child: widget.child,
    );
  }
}
