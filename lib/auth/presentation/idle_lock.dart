import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';

class IdleLock extends ConsumerStatefulWidget {
  const IdleLock({
    super.key,
    required this.child,
    this.timeout = const Duration(minutes: 10),
  });
  final Widget child;
  final Duration timeout;
  @override
  ConsumerState<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends ConsumerState<IdleLock> {
  Timer? _t;
  void _reset() {
    _t?.cancel();
    _t = Timer(widget.timeout, _onIdle);
  }

  void _onIdle() {
    if (ref.read(authControllerProvider) != null) {
      ref
          .read(authControllerProvider.notifier)
          .logout(); // router sends to /login
    }
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _reset(),
    onPointerMove: (_) => _reset(),
    onPointerSignal: (_) => _reset(),
    child: widget.child,
  );
}
