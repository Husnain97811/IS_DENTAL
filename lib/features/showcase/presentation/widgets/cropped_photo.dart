import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../patients/data/photo_compare_image.dart';
import '../../../patients/data/xray_vault.dart';

/// A patient photo (decrypted in memory) filling its box — either the saved
/// marketing crop or a centre crop. Give it a 4:3 box (AspectRatio 4/3):
/// crops are 4:3, so they fill it with no stretching.
class CroppedPhoto extends ConsumerWidget {
  const CroppedPhoto({
    super.key,
    required this.photo,
    this.crop,
    this.dark = false,
  });
  final XrayRow photo;
  final NormRect? crop;

  /// Placeholder colours for dark backgrounds (slideshow).
  final bool dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final bg = dark ? const Color(0xFF1E293B) : d.surface2;
    final fg = dark ? Colors.white38 : d.text4;
    if (!photo.isLocal) {
      return _Placeholder(
        bg: bg,
        fg: fg,
        icon: Icons.devices_other_rounded,
        text: 'On another computer',
      );
    }
    final bytes = ref.watch(
      xrayBytesProvider((
        uuid: photo.uuid,
        path: photo.filePath,
        enc: photo.isEncrypted,
      )),
    );
    return bytes.when(
      loading: () => Container(
        color: bg,
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: fg),
        ),
      ),
      error: (e, _) => _Placeholder(
        bg: bg,
        fg: fg,
        icon: Icons.lock_outline_rounded,
        text: 'Can\'t open here',
      ),
      data: (b) => LayoutBuilder(
        builder: (context, box) =>
            _image(context, b, box.maxWidth, box.maxHeight),
      ),
    );
  }

  Widget _image(BuildContext context, Uint8List b, double bw, double bh) {
    // The slideshow lays a slide out at zero size for a moment (first frame,
    // a slide sliding in). Nothing to draw yet — and a cacheWidth of 0 is
    // what threw "cacheWidth > 0" and left the screen black.
    if (bw <= 0 || bh <= 0) return const SizedBox.shrink();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final c = crop;
    // No crop, a broken crop (zero width/height), or an unbounded box → a
    // plain centre crop.
    if (c == null || c.w <= 0 || c.h <= 0 || !bw.isFinite || !bh.isFinite) {
      return Image.memory(
        b,
        fit: BoxFit.cover,
        width: bw.isFinite ? bw : null,
        height: bh.isFinite ? bh : null,
        cacheWidth: _px(bw, dpr, 2400),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _broken(context),
      );
    }
    // The saved crop is 4:3. In a box of another shape (the wide slideshow
    // frame) it COVERS the box, centred — trimmed at the edges, never
    // stretched. In a 4:3 box this is exactly the crop.
    final rw = math.max(bw, bh * 4 / 3), rh = rw * 3 / 4;
    // the whole photo is drawn large enough that the crop is rw × rh
    final dw = rw / c.w, dh = rh / c.h;
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            left: -c.x * dw + (bw - rw) / 2,
            top: -c.y * dh + (bh - rh) / 2,
            width: dw,
            height: dh,
            child: Image.memory(
              b,
              fit: BoxFit.fill,
              cacheWidth: _px(dw, dpr, 3200),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _broken(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Decode width in real pixels — never 0 or less (Flutter asserts on it),
  /// never more than [max], null when the box has no fixed width.
  static int? _px(double logical, double dpr, int max) {
    if (!logical.isFinite) return null;
    final px = (logical * dpr).round();
    return px < 1 ? null : math.min(px, max);
  }

  /// A photo file that can't be decoded shows a placeholder, not a crash.
  Widget _broken(BuildContext context) {
    final d = context.dent;
    return _Placeholder(
      bg: dark ? const Color(0xFF1E293B) : d.surface2,
      fg: dark ? Colors.white38 : d.text4,
      icon: Icons.broken_image_outlined,
      text: 'Photo can\'t be shown',
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.text,
  });
  final Color bg, fg;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    color: bg,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: fg),
        const SizedBox(height: 4),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: fg, fontSize: 8.sp),
        ),
      ],
    ),
  );
}
