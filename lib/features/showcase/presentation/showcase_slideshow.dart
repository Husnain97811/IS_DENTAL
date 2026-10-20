import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../data/showcase_cases.dart';
import 'widgets/cropped_photo.dart';

/// Full-screen slideshow for the waiting-room TV or a reception tablet.
/// Each slide shows the Before, sweeps across to reveal the After, holds,
/// then fades to the next case. Keys: ← → change slide, Space pauses,
/// Esc closes. Controls appear when the mouse moves.
Future<void> openShowcaseSlideshow(
  BuildContext context, {
  required List<ShowcaseCase> cases,
  required String clinicName,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    opaque: true,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, __, ___) =>
        _Slideshow(cases: cases, clinicName: clinicName),
    transitionsBuilder: (_, a, __, child) =>
        FadeTransition(opacity: a, child: child),
  ),
);

const _bg = Color(0xFF0B1220);
const _speeds = [5, 7, 10]; // seconds per slide

class _Slideshow extends ConsumerStatefulWidget {
  const _Slideshow({required this.cases, required this.clinicName});
  final List<ShowcaseCase> cases;
  final String clinicName;
  @override
  ConsumerState<_Slideshow> createState() => _SlideshowState();
}

class _SlideshowState extends ConsumerState<_Slideshow>
    with TickerProviderStateMixin {
  /// One clock per slide: the slide fading out keeps its own (stopped)
  /// clock, so it never jumps back to the Before while it fades.
  late AnimationController _clock;
  final _focus = FocusNode();
  int _i = 0;
  int _speed = 7;
  bool _paused = false, _chrome = true;
  Timer? _hideChrome;

  // phases of one slide (fractions of its time)
  static const _holdBefore = .16, _wipeEnd = .42;

  @override
  void initState() {
    super.initState();
    _clock = _newClock()..forward();
    _showChrome();
  }

  AnimationController _newClock() =>
      AnimationController(
        vsync: this,
        duration: Duration(seconds: _speed),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) _go(1);
      });

  @override
  void dispose() {
    _hideChrome?.cancel();
    _clock.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int step) {
    final old = _clock..stop();
    setState(() {
      _i = (_i + step) % widget.cases.length; // Dart's % is never negative
      _clock = _newClock();
    });
    if (!_paused) _clock.forward();
    // the fading slide still draws with `old` until the fade ends
    Future<void>.delayed(const Duration(milliseconds: 800), old.dispose);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _clock.stop();
    } else {
      _clock.forward();
    }
    _showChrome();
  }

  void _setSpeed(int s) {
    setState(() => _speed = s);
    final progress = _clock.value;
    _clock.duration = Duration(seconds: s);
    if (!_paused) _clock.forward(from: progress);
    _showChrome();
  }

  /// Controls show on mouse move and fade out after 3 s of stillness.
  void _showChrome() {
    if (!_chrome) setState(() => _chrome = true);
    _hideChrome?.cancel();
    _hideChrome = Timer(const Duration(seconds: 3), () {
      if (mounted && !_paused) setState(() => _chrome = false);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _go(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
    } else if (k == LogicalKeyboardKey.space) {
      _togglePause();
    } else {
      return KeyEventResult.ignored;
    }
    _showChrome();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final cases = widget.cases;
    final c = cases[_i];
    final next = cases[(_i + 1) % cases.length];

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: (_) => _showChrome(),
        cursor: _chrome ? SystemMouseCursors.basic : SystemMouseCursors.none,
        child: Scaffold(
          backgroundColor: _bg,
          body: LayoutBuilder(
            builder: (context, box) {
              // the photo frame: as large as fits under the headline
              final frameW = math.min(
                box.maxWidth * .82,
                (box.maxHeight * .62) * 4 / 3,
              );
              return Stack(
                children: [
                  // warms up the next slide's photos so it appears instantly
                  Offstage(
                    child: SizedBox(
                      width: 40,
                      height: 30,
                      child: Row(
                        children: [
                          Expanded(
                            child: CroppedPhoto(
                              photo: next.before,
                              crop: next.beforeCrop,
                              dark: true,
                            ),
                          ),
                          Expanded(
                            child: CroppedPhoto(
                              photo: next.after,
                              crop: next.afterCrop,
                              dark: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      child: _Slide(
                        key: ValueKey(c.id),
                        c: c,
                        frameW: frameW,
                        clock: _clock,
                        clinicName: widget.clinicName,
                        wipeFrom: _holdBefore,
                        wipeTo: _wipeEnd,
                      ),
                    ),
                  ),
                  // progress dots
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 26,
                    child: _Dots(count: cases.length, index: _i),
                  ),
                  // controls
                  Positioned(
                    top: 18,
                    right: 18,
                    child: AnimatedOpacity(
                      opacity: _chrome ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: IgnorePointer(
                        ignoring: !_chrome,
                        child: _controls(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    Widget btn(IconData i, String tip, VoidCallback on) => IconButton(
      tooltip: tip,
      onPressed: on,
      icon: Icon(i, color: Colors.white, size: 22),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.skip_previous_rounded, 'Previous (←)', () => _go(-1)),
          btn(
            _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            _paused ? 'Play (Space)' : 'Pause (Space)',
            _togglePause,
          ),
          btn(Icons.skip_next_rounded, 'Next (→)', () => _go(1)),
          const SizedBox(width: 4),
          for (final s in _speeds)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text(
                  '${s}s',
                  style: TextStyle(
                    fontSize: 9.sp,
                    color: s == _speed ? Colors.black : Colors.white,
                  ),
                ),
                selected: s == _speed,
                onSelected: (_) => _setSpeed(s),
                selectedColor: Colors.white,
                backgroundColor: Colors.transparent,
                side: BorderSide(color: Colors.white.withValues(alpha: .3)),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
            ),
          const SizedBox(width: 4),
          btn(
            Icons.close_rounded,
            'Close (Esc)',
            () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// One slide: headline, the photo frame with the sweep, clinic name.
class _Slide extends StatelessWidget {
  const _Slide({
    super.key,
    required this.c,
    required this.frameW,
    required this.clock,
    required this.clinicName,
    required this.wipeFrom,
    required this.wipeTo,
  });
  final ShowcaseCase c;
  final double frameW, wipeFrom, wipeTo;
  final Animation<double> clock;
  final String clinicName;

  @override
  Widget build(BuildContext context) {
    final frameH = frameW * 3 / 4;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'BEFORE  &  AFTER',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.durationLine,
            style: TextStyle(color: Colors.white70, fontSize: 12.sp),
          ),
          SizedBox(height: frameH * .06),
          Container(
            width: frameW,
            height: frameH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 40,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: AnimatedBuilder(
                animation: clock,
                builder: (_, __) {
                  // hold the Before, sweep across, hold the After
                  final t = Curves.easeInOutCubic.transform(
                    ((clock.value - wipeFrom) / (wipeTo - wipeFrom)).clamp(
                      0.0,
                      1.0,
                    ),
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CroppedPhoto(
                        photo: c.before,
                        crop: c.beforeCrop,
                        dark: true,
                      ),
                      ClipRect(
                        clipper: _Reveal(t),
                        child: CroppedPhoto(
                          photo: c.after,
                          crop: c.afterCrop,
                          dark: true,
                        ),
                      ),
                      if (t > 0 && t < 1)
                        Positioned(
                          left: frameW * t - 1.5,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 3,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        left: 18,
                        top: 18,
                        child: Opacity(
                          opacity: (1 - t).clamp(0.0, 1.0),
                          child: _tag('BEFORE', Colors.black54),
                        ),
                      ),
                      Positioned(
                        right: 18,
                        top: 18,
                        child: Opacity(
                          opacity: t.clamp(0.0, 1.0),
                          child: _tag('AFTER', const Color(0xFF0F766E)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          SizedBox(height: frameH * .07),
          Text(
            clinicName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Real patients · shared with their consent',
            style: TextStyle(color: Colors.white38, fontSize: 9.sp),
          ),
        ],
      ),
    );
  }

  Widget _tag(String t, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      t,
      style: TextStyle(
        color: Colors.white,
        fontSize: 10.sp,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    ),
  );
}

/// Shows the left [t] share of the After photo (the sweep).
class _Reveal extends CustomClipper<Rect> {
  const _Reveal(this.t);
  final double t;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);
  @override
  bool shouldReclip(_Reveal old) => old.t != t;
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count, index;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    if (count > 24) {
      return Center(
        child: Text(
          '${index + 1} / $count',
          style: TextStyle(color: Colors.white54, fontSize: 9.sp),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index ? Colors.white : Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
