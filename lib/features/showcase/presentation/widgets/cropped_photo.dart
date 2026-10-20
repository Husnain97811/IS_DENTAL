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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final c = crop;
    if (c == null || !bw.isFinite || !bh.isFinite) {
      return Image.memory(
        b,
        fit: BoxFit.cover,
        width: bw.isFinite ? bw : null,
        height: bh.isFinite ? bh : null,
        cacheWidth: bw.isFinite ? math.min((bw * dpr).round(), 2400) : null,
        gaplessPlayback: true,
      );
    }
    // the whole photo is drawn large enough that the crop fills the box
    final dw = bw / c.w, dh = bh / c.h;
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            left: -c.x * dw,
            top: -c.y * dh,
            width: dw,
            height: dh,
            child: Image.memory(
              b,
              fit: BoxFit.fill,
              cacheWidth: math.min((dw * dpr).round(), 3200),
              gaplessPlayback: true,
            ),
          ),
        ],
      ),
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
