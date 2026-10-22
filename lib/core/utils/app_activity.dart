import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Someone is using the app" signal from screens that live outside the
/// normal shell (the Reporting Hub). IdleLock listens and restarts its
/// auto sign-out timer. Throttled: at most one ping every 15 seconds.
class AppActivity extends Notifier<int> {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  int build() => 0;

  void ping() {
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(seconds: 15)) return;
    _last = now;
    state++;
  }
}

final appActivityProvider = NotifierProvider<AppActivity, int>(AppActivity.new);
