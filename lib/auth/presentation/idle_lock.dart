import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'auth_controller.dart';

class IdleLock extends ConsumerStatefulWidget {
  const IdleLock({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends ConsumerState<IdleLock> {
  Timer? _t;
  int _mins = 10;

  void _reset() {
    _t?.cancel();
    if (_mins <= 0) return; // 0 = disabled
    _t = Timer(Duration(minutes: _mins), _onIdle);
  }

  void _onIdle() {
    if (ref.read(authControllerProvider) != null) {
      ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  void initState() {
    super.initState();
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

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      onPointerMove: (_) => _reset(),
      onPointerSignal: (_) => _reset(),
      child: widget.child,
    );
  }
}
