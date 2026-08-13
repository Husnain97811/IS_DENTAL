import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/dent_colors.dart';

/// ── Loading state ──────────────────────────────────────────
/// A single global loading flag with an optional message.
/// Controlled via [loadingProvider]. Auto-clears after 15s as a
/// safety net so the app can never get stuck behind the overlay.
class LoadingState {
  const LoadingState({this.active = false, this.message});
  final bool active;
  final String? message;

  LoadingState copyWith({bool? active, String? message}) =>
      LoadingState(active: active ?? this.active, message: message);
}

class LoadingController extends Notifier<LoadingState> {
  Timer? _timeout;

  @override
  LoadingState build() {
    ref.onDispose(() => _timeout?.cancel());
    return const LoadingState();
  }

  /// Show the overlay. Auto-hides after [timeout] (default 15s) as a
  /// safety net. Call [hide] yourself when the work finishes.
  void show({String? message, Duration timeout = const Duration(seconds: 15)}) {
    _timeout?.cancel();
    state = LoadingState(active: true, message: message);
    _timeout = Timer(timeout, hide);
  }

  void hide() {
    _timeout?.cancel();
    _timeout = null;
    if (state.active) state = const LoadingState();
  }

  /// Convenience: wrap an async task — shows while it runs, always hides after.
  Future<T> during<T>(
    Future<T> Function() task, {
    String? message,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    show(message: message, timeout: timeout);
    try {
      return await task();
    } finally {
      hide();
    }
  }
}

final loadingProvider = NotifierProvider<LoadingController, LoadingState>(
  LoadingController.new,
);

/// ── The overlay widget ─────────────────────────────────────
/// Wrap your app shell's body ONCE with this. It listens to
/// [loadingProvider] and paints a full-screen blocking spinner
/// when active. Optimized: only the overlay layer rebuilds, not
/// the child underneath.
class LoadingOverlay extends ConsumerWidget {
  const LoadingOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only this widget rebuilds when loading toggles — child is const-held.
    final loading = ref.watch(loadingProvider);
    final d = context.dent;

    return Stack(
      children: [
        child,
        if (loading.active)
          // AbsorbPointer + barrier blocks all interaction underneath.
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 160),
              tween: Tween(begin: 0, end: 1),
              builder: (_, t, __) => Opacity(
                opacity: t,
                child: Container(
                  color: Colors.black.withValues(alpha: .32),
                  alignment: Alignment.center,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: loading.message != null ? 22 : 26,
                      vertical: loading.message != null ? 20 : 26,
                    ),
                    decoration: BoxDecoration(
                      color: d.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .18),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor: AlwaysStoppedAnimation(d.ice),
                          ),
                        ),
                        if (loading.message != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            loading.message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: d.text2,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
