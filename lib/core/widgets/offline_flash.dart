import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

/// A big red "no internet" badge in the middle of the screen for about two
/// seconds, then it fades away by itself.
///
/// It never blocks anything: taps go straight through it, and the work it
/// reports on is already saved on this computer.
///
/// Take the overlay BEFORE closing a dialog, while its context is alive:
/// ```dart
/// final overlay = Overlay.maybeOf(context, rootOverlay: true);
/// ```
void showOfflineFlash(OverlayState overlay) {
  if (!overlay.mounted) return;
  // a badge already showing makes way for the new one
  final old = _current;
  if (old != null && old.mounted) old.remove();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _OfflineFlash(
      onDone: () {
        if (entry.mounted) entry.remove();
        if (identical(_current, entry)) _current = null;
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

OverlayEntry? _current;

const _red = Color(0xFFE5383B);

class _OfflineFlash extends StatefulWidget {
  const _OfflineFlash({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_OfflineFlash> createState() => _OfflineFlashState();
}

class _OfflineFlashState extends State<_OfflineFlash>
    with SingleTickerProviderStateMixin {
  // 0.26 s in + 1.36 s held + 0.38 s out ≈ 2 seconds on screen
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeIn,
  );
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _hold = Timer(const Duration(milliseconds: 1620), () {
      if (!mounted) return;
      _c.reverse().whenComplete(() {
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: FadeTransition(
            opacity: _c,
            child: ScaleTransition(
              scale: Tween<double>(begin: .82, end: 1).animate(_curve),
              child: Semantics(
                liveRegion: true,
                label: 'No internet. Saved on this computer.',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 136,
                      height: 136,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _red,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .9),
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _red.withValues(alpha: .45),
                            blurRadius: 42,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        size: 66,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEB161A22),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No internet',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Saved on this computer. It goes to the cloud '
                              'by itself when the internet is back.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .8),
                                fontSize: 10.5.sp,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
