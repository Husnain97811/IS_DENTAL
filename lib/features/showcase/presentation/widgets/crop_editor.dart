import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../patients/data/photo_compare_image.dart';
import '../../../patients/data/xray_vault.dart';
import '../../data/showcase_cases.dart';

/// "Crop to the smile": frame the Before and After photos so only teeth and
/// lips show. The frame is 4:3, the same shape as every post and slide, so
/// what you see here is exactly what gets published.
Future<void> showCropEditor(BuildContext context, ShowcaseCase c) => showDialog(
  context: context,
  builder: (_) => _CropEditor(c: c),
);

const _maxZoom = 6.0;

/// One photo being framed. Position is the crop's centre in 0–1 units of
/// the photo; zoom 1 = the largest 4:3 frame that fits the photo.
class _Frame {
  _Frame(this.row);
  final XrayRow row;
  Uint8List? bytes;
  Size? size; // pixels
  double zoom = 1, cx = .5, cy = .5;

  bool get ready => bytes != null && size != null;

  /// The 4:3 frame at zoom 1, in 0–1 units.
  ({double w, double h}) get _base {
    final a = size!.width / size!.height;
    return a >= 4 / 3 ? (w: (4 / 3) / a, h: 1.0) : (w: 1.0, h: .75 * a);
  }

  NormRect get rect {
    final b = _base;
    final w = b.w / zoom, h = b.h / zoom;
    return (
      x: (cx - w / 2).clamp(0.0, 1 - w),
      y: (cy - h / 2).clamp(0.0, 1 - h),
      w: w,
      h: h,
    );
  }

  /// Keeps the frame inside the photo.
  void clampCentre() {
    final b = _base;
    final w = b.w / zoom, h = b.h / zoom;
    cx = cx.clamp(w / 2, 1 - w / 2);
    cy = cy.clamp(h / 2, 1 - h / 2);
  }

  void loadFrom(NormRect? r) {
    if (r == null) {
      zoom = 1;
      cx = cy = .5;
      return;
    }
    zoom = (_base.w / r.w).clamp(1.0, _maxZoom);
    cx = r.x + r.w / 2;
    cy = r.y + r.h / 2;
    clampCentre();
  }

  /// null when the frame is the untouched default (whole photo, centred).
  String? get saved =>
      zoom < 1.01 && (cx - .5).abs() < .005 && (cy - .5).abs() < .005
      ? null
      : formatCrop(rect);
}

class _CropEditor extends ConsumerStatefulWidget {
  const _CropEditor({required this.c});
  final ShowcaseCase c;
  @override
  ConsumerState<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends ConsumerState<_CropEditor> {
  late final _frames = [_Frame(widget.c.before), _Frame(widget.c.after)];
  int _side = 0;
  double _zoomAtStart = 1;
  bool _saving = false;
  String? _error;

  _Frame get _f => _frames[_side];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vault = ref.read(xrayVaultProvider);
    try {
      for (final f in _frames) {
        final b = await vault.read(f.row);
        final buf = await ui.ImmutableBuffer.fromUint8List(b);
        final desc = await ui.ImageDescriptor.encoded(buf);
        f
          ..bytes = b
          ..size = Size(desc.width.toDouble(), desc.height.toDouble())
          ..loadFrom(parseCrop(f.row.crop));
        desc.dispose();
        buf.dispose();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted)
        setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  void _zoomTo(double z) => setState(() {
    _f.zoom = z.clamp(1.0, _maxZoom);
    _f.clampCentre();
  });

  void _pan(Offset delta, double dw, double dh) => setState(() {
    _f
      ..cx -= delta.dx / dw
      ..cy -= delta.dy / dh
      ..clampCentre();
  });

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final repo = ref.read(xrayRepositoryProvider);
      for (final f in _frames) {
        final v = f.saved;
        if (v != f.row.crop) await repo.setCrop(f.row, v);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            '✓ Framing saved — posts and the slideshow use it now.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final maxW = 100.w < 900 ? 94.w : 58.w;
    final ready = _frames.every((f) => f.ready);

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: EdgeInsets.all((2.w).clamp(12.0, 40.0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: 92.h),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crop to the smile',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: d.text1,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Frame just the teeth and lips, so no face is ever shown in posts or the slideshow.',
                          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(
                          'Before',
                          style: TextStyle(fontSize: 10.sp),
                        ),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('After', style: TextStyle(fontSize: 10.sp)),
                      ),
                    ],
                    selected: {_side},
                    onSelectionChanged: (s) => setState(() => _side = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Text(
                            _error!,
                            style: TextStyle(color: d.alert, fontSize: 10.5.sp),
                          ),
                        ),
                      )
                    : !ready
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : LayoutBuilder(builder: (_, box) => _viewport(box)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.zoom_out_rounded, size: 18, color: d.text3),
                  Expanded(
                    child: Slider(
                      value: _f.zoom,
                      min: 1,
                      max: _maxZoom,
                      onChanged: ready ? _zoomTo : null,
                    ),
                  ),
                  Icon(Icons.zoom_in_rounded, size: 18, color: d.text3),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: ready
                        ? () => setState(() => _f.loadFrom(null))
                        : null,
                    icon: const Icon(Icons.fit_screen_rounded, size: 17),
                    label: Text(
                      'Whole photo',
                      style: TextStyle(fontSize: 10.sp),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: ready
                        ? () => setState(() {
                            final to = _frames[1 - _side];
                            to.loadFrom(_f.rect);
                          })
                        : null,
                    icon: const Icon(Icons.content_copy_rounded, size: 16),
                    label: Text(
                      'Same framing for ${_side == 0 ? 'After' : 'Before'}',
                      style: TextStyle(fontSize: 10.sp),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Drag to move  ·  scroll, pinch or use the slider to zoom',
                      style: TextStyle(color: d.text4, fontSize: 9.sp),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: !ready || _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(130, 44),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Save framing',
                            style: TextStyle(fontSize: 10.5.sp),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The 4:3 window: the photo moves and zooms behind a fixed frame.
  Widget _viewport(BoxConstraints box) {
    final vw = math.min(
      box.maxWidth,
      box.maxHeight.isFinite ? box.maxHeight * 4 / 3 : box.maxWidth,
    );
    final vh = vw * 3 / 4;
    final f = _f;
    final r = f.rect;
    final dw = vw / r.w, dh = vh / r.h;

    return Center(
      child: SizedBox(
        width: vw,
        height: vh,
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _zoomTo(f.zoom * math.exp(-e.scrollDelta.dy / 400));
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              onScaleStart: (_) => _zoomAtStart = f.zoom,
              onScaleUpdate: (s) {
                if (s.scale != 1) _zoomTo(_zoomAtStart * s.scale);
                _pan(s.focalPointDelta, dw, dh);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    Positioned(
                      left: -r.x * dw,
                      top: -r.y * dh,
                      width: dw,
                      height: dh,
                      child: Image.memory(
                        f.bytes!,
                        fit: BoxFit.fill,
                        // decoded once at a fixed size — zooming never re-decodes
                        cacheWidth: math.min(f.size!.width.round(), 3200),
                        gaplessPlayback: true,
                      ),
                    ),
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _ThirdsPainter()),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _side == 0 ? 'BEFORE' : 'AFTER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
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

/// Rule-of-thirds guides and a soft border — helps centre the smile.
class _ThirdsPainter extends CustomPainter {
  const _ThirdsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .45)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3, y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: .8),
    );
  }

  @override
  bool shouldRepaint(_ThirdsPainter oldDelegate) => false;
}
