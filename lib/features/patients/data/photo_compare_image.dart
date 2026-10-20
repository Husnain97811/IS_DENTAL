import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

// ═════════════════════════════════════════════════════════════════════════
//  Before / after pictures, drawn with dart:ui only — no extra package,
//  nothing written to disk.
//
//  buildComparisonPng  — the plain white picture sent to the patient.
//  buildShowcasePng    — branded marketing posts (square, portrait, wide).
// ═════════════════════════════════════════════════════════════════════════

/// A crop of a photo in 0–1 units of its width and height. Showcase crops
/// are always 4:3 in pixels, so they fill a 4:3 panel with no stretching.
typedef NormRect = ({double x, double y, double w, double h});

/// "0.1200,0.3000,0.5000,0.4000" → rect; null/invalid → null (whole photo).
NormRect? parseCrop(String? s) {
  if (s == null || s.isEmpty) return null;
  final p = s.split(',').map(double.tryParse).toList();
  if (p.length != 4 || p.any((v) => v == null)) return null;
  final r = (x: p[0]!, y: p[1]!, w: p[2]!, h: p[3]!);
  final ok =
      r.w > 0.01 &&
      r.h > 0.01 &&
      r.x >= -0.001 &&
      r.y >= -0.001 &&
      r.x + r.w <= 1.001 &&
      r.y + r.h <= 1.001;
  return ok ? r : null;
}

String formatCrop(NormRect r) => [
  r.x,
  r.y,
  r.w,
  r.h,
].map((v) => v.clamp(0.0, 1.0).toStringAsFixed(4)).join(',');

// ─────────────────────────────────────────────── patient comparison ─────
/// One side-by-side picture: clinic name and treatment on top, BEFORE and
/// AFTER panels with their dates, a short note at the bottom.
Future<Uint8List> buildComparisonPng({
  required Uint8List before,
  required Uint8List after,
  required String clinicName,
  required String title,
  required DateTime beforeDate,
  required DateTime afterDate,
  NormRect? beforeCrop,
  NormRect? afterCrop,
}) async {
  const panelW = 960.0, panelH = 720.0, gap = 16.0, pad = 32.0;
  const headH = 132.0, footH = 64.0;
  const w = pad * 2 + panelW * 2 + gap;
  const h = headH + panelH + footH;

  final b = await _decode(before, panelW, beforeCrop);
  final a = await _decode(after, panelW, afterCrop);
  try {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, w, h));
    c.drawRect(
      const ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    _text(
      c,
      clinicName,
      const ui.Offset(pad, 30),
      w - pad * 2,
      _style(38, const ui.Color(0xFF0F172A), weight: ui.FontWeight.w700),
    );
    _text(
      c,
      title,
      const ui.Offset(pad, 82),
      w - pad * 2,
      _style(24, const ui.Color(0xFF475569)),
    );

    const left = ui.Rect.fromLTWH(pad, headH, panelW, panelH);
    const right = ui.Rect.fromLTWH(pad + panelW + gap, headH, panelW, panelH);
    _photo(c, b, left, beforeCrop, radius: 20);
    _photo(c, a, right, afterCrop, radius: 20);
    _pill(
      c,
      'BEFORE  ·  ${_date(beforeDate)}',
      left,
      const ui.Color(0xB3000000),
    );
    _pill(
      c,
      'AFTER  ·  ${_date(afterDate)}',
      right,
      const ui.Color(0xB3000000),
    );

    _text(
      c,
      'Results vary from patient to patient.',
      const ui.Offset(pad, headH + panelH + 20),
      w - pad * 2,
      _style(18, const ui.Color(0xFF94A3B8)),
    );
    return _png(rec, w, h);
  } finally {
    b.dispose();
    a.dispose();
  }
}

// ─────────────────────────────────────────────── showcase posts ─────────
enum ShowcaseFormat {
  square('Square', '1080 × 1080', 'Instagram & Facebook feed', 1080, 1080),
  portrait(
    'Portrait',
    '1080 × 1350',
    'Instagram — fills the screen',
    1080,
    1350,
  ),
  wide('Wide', '1920 × 1080', 'Website, slides & TV', 1920, 1080);

  const ShowcaseFormat(
    this.label,
    this.size,
    this.useFor,
    this.width,
    this.height,
  );
  final String label, size, useFor;
  final int width, height;
  double get aspect => width / height;
}

/// Brand colours offered for posts. The first is DentOS teal.
const kShowcaseAccents = <ui.Color>[
  ui.Color(0xFF0F766E), // teal
  ui.Color(0xFF1D4ED8), // blue
  ui.Color(0xFF6D28D9), // violet
  ui.Color(0xFFBE185D), // rose
  ui.Color(0xFF1F2937), // graphite
];

/// A branded post: coloured background, treatment as the headline, the two
/// photos on a white card, clinic name and contact at the bottom, and a
/// small honest note. Never contains the patient's name.
Future<Uint8List> buildShowcasePng({
  required Uint8List before,
  required Uint8List after,
  NormRect? beforeCrop,
  NormRect? afterCrop,
  required ShowcaseFormat format,
  required String clinicName,
  String contact = '',
  required String treatment,
  required String duration,
  ui.Color accent = const ui.Color(0xFF0F766E),
}) async {
  final w = format.width.toDouble(), h = format.height.toDouble();
  final stacked = format == ShowcaseFormat.portrait;

  // ── layout (all numbers in output pixels) ──
  final double titleSize, panelW, gap, cardPad, top;
  switch (format) {
    case ShowcaseFormat.square:
      titleSize = 64;
      panelW = 468;
      gap = 16;
      cardPad = 16;
      top = 290;
    case ShowcaseFormat.portrait:
      titleSize = 64;
      panelW = 560;
      gap = 16;
      cardPad = 16;
      top = 262;
    case ShowcaseFormat.wide:
      titleSize = 72;
      panelW = 760;
      gap = 24;
      cardPad = 24;
      top = 262;
  }
  final panelH = panelW * 3 / 4;
  final cardW = stacked ? panelW + cardPad * 2 : panelW * 2 + gap + cardPad * 2;
  final cardH = stacked ? panelH * 2 + gap + cardPad * 2 : panelH + cardPad * 2;
  final card = ui.Rect.fromLTWH((w - cardW) / 2, top, cardW, cardH);
  final p1 = ui.Rect.fromLTWH(
    card.left + cardPad,
    card.top + cardPad,
    panelW,
    panelH,
  );
  final p2 = stacked
      ? p1.translate(0, panelH + gap)
      : p1.translate(panelW + gap, 0);

  final b = await _decode(before, panelW, beforeCrop);
  final a = await _decode(after, panelW, afterCrop);
  try {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w, h));

    // background: accent → a deeper shade, with a soft light at the top
    final deep = ui.Color.lerp(accent, const ui.Color(0xFF000000), .35)!;
    c.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(w * .35, h), [
          accent,
          deep,
        ]),
    );
    c.drawCircle(
      ui.Offset(w * .85, -h * .05),
      w * .55,
      ui.Paint()..color = const ui.Color(0x14FFFFFF),
    );

    // headline
    const white = ui.Color(0xFFFFFFFF);
    const soft = ui.Color(0xCCFFFFFF);
    _centered(
      c,
      'BEFORE  &  AFTER',
      64,
      w,
      _style(24, soft, weight: ui.FontWeight.w700, spacing: 6),
    );
    _centered(
      c,
      treatment.isEmpty ? 'Smile transformation' : treatment,
      104,
      w,
      _style(titleSize, white, weight: ui.FontWeight.w800),
    );
    if (duration.isNotEmpty) {
      _centered(c, duration, 104 + titleSize + 18, w, _style(30, soft));
    }

    // white card with the photos
    c.drawRRect(
      ui.RRect.fromRectAndRadius(
        card.shift(const ui.Offset(0, 14)),
        const ui.Radius.circular(34),
      ),
      ui.Paint()
        ..color = const ui.Color(0x40000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 24),
    );
    c.drawRRect(
      ui.RRect.fromRectAndRadius(card, const ui.Radius.circular(34)),
      ui.Paint()..color = white,
    );
    _photo(c, b, p1, beforeCrop, radius: 22);
    _photo(c, a, p2, afterCrop, radius: 22);
    _pill(c, 'BEFORE', p1, const ui.Color(0xCC0F172A));
    _pill(c, 'AFTER', p2, accent);

    // clinic + contact + note, centred in the space under the card
    final note =
        'Real patient  ·  shared with consent  ·  individual results vary';
    final noteY = h - 56;
    final free = noteY - card.bottom;
    final hasContact = contact.trim().isNotEmpty;
    final blockH = hasContact ? 44 + 12 + 30 : 44;
    final y0 = card.bottom + (free - blockH) / 2 - 10;
    _centered(
      c,
      clinicName,
      y0,
      w,
      _style(44, white, weight: ui.FontWeight.w700),
    );
    if (hasContact) {
      _centered(c, contact.trim(), y0 + 56, w, _style(28, soft));
    }
    _centered(
      c,
      note,
      noteY,
      w,
      _style(20, const ui.Color(0x99FFFFFF)),
      margin: 40,
    );

    return _png(rec, w, h);
  } finally {
    b.dispose();
    a.dispose();
  }
}

// ─────────────────────────────────────────────── drawing helpers ────────
/// Decodes only as large as needed: a 12 MP photo is never held at full
/// size to fill a 600 px panel, but a tight crop is decoded large enough
/// to stay sharp.
Future<ui.Image> _decode(Uint8List bytes, double panelW, NormRect? crop) async {
  final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buf);
  final need = panelW * 1.25 / (crop?.w ?? 1);
  final targetW = desc.width > need ? need.round() : null;
  final codec = await desc.instantiateCodec(targetWidth: targetW);
  final frame = await codec.getNextFrame();
  codec.dispose();
  desc.dispose();
  buf.dispose();
  return frame.image;
}

/// Fills [dst] with the crop (or a centre crop like BoxFit.cover).
void _photo(
  ui.Canvas c,
  ui.Image img,
  ui.Rect dst,
  NormRect? crop, {
  double radius = 0,
}) {
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final ui.Rect src;
  if (crop != null) {
    src = ui.Rect.fromLTWH(crop.x * iw, crop.y * ih, crop.w * iw, crop.h * ih);
  } else {
    final scale = math.max(dst.width / iw, dst.height / ih);
    final sw = dst.width / scale, sh = dst.height / scale;
    src = ui.Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);
  }
  c.save();
  c.clipRRect(ui.RRect.fromRectAndRadius(dst, ui.Radius.circular(radius)));
  c.drawRect(dst, ui.Paint()..color = const ui.Color(0xFFE2E8F0));
  c.drawImageRect(
    img,
    src,
    dst,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  c.restore();
}

void _pill(ui.Canvas c, String label, ui.Rect panel, ui.Color bg) {
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: _style(
        22,
        const ui.Color(0xFFFFFFFF),
        weight: ui.FontWeight.w700,
        spacing: 1.6,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final r = ui.Rect.fromLTWH(
    panel.left + 20,
    panel.bottom - tp.height - 38,
    tp.width + 32,
    tp.height + 16,
  );
  c.drawRRect(
    ui.RRect.fromRectAndRadius(r, const ui.Radius.circular(30)),
    ui.Paint()..color = bg,
  );
  tp.paint(c, ui.Offset(r.left + 16, r.top + 8));
  tp.dispose();
}

TextStyle _style(
  double size,
  ui.Color color, {
  ui.FontWeight? weight,
  double? spacing,
}) => TextStyle(
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: spacing,
  height: 1.15,
);

void _text(ui.Canvas c, String s, ui.Offset at, double maxW, TextStyle style) {
  if (s.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: ui.TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxW);
  tp.paint(c, at);
  tp.dispose();
}

/// One line centred across a canvas [canvasW] wide, [margin] kept free on
/// each side (longer text ends in "…").
void _centered(
  ui.Canvas c,
  String s,
  double y,
  double canvasW,
  TextStyle style, {
  double margin = 60,
}) {
  if (s.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: ui.TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: canvasW - margin * 2);
  tp.paint(c, ui.Offset((canvasW - tp.width) / 2, y));
  tp.dispose();
}

Future<Uint8List> _png(ui.PictureRecorder rec, double w, double h) async {
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}

String _date(DateTime d) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}
