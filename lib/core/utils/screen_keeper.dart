import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps the screen awake and the window full screen while the Reporting
/// Hub is on a wall monitor. Every call is safe to repeat, and a platform
/// that can't do one of them simply carries on without it.
class ScreenKeeper {
  ScreenKeeper._();

  static bool _windowReady = false;
  static bool _wasFullScreen = false;

  static Future<void> enter() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // no wake lock here — the screen may dim on its own power settings
    }
    try {
      if (!_windowReady) {
        await windowManager.ensureInitialized();
        _windowReady = true;
      }
      _wasFullScreen = await windowManager.isFullScreen();
      if (!_wasFullScreen) await windowManager.setFullScreen(true);
    } catch (_) {
      // the Hub already fills the window; full screen is a bonus
    }
  }

  static Future<void> leave() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    try {
      // only undo what wall mode did
      if (_windowReady && !_wasFullScreen) {
        await windowManager.setFullScreen(false);
      }
    } catch (_) {}
  }
}
