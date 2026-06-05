import 'package:flutter/material.dart';
import 'app_palette.dart';

@immutable
class DentColors extends ThemeExtension<DentColors> {
  const DentColors({
    required this.canvas, required this.canvasAlt, required this.surface, required this.surface2, required this.surface3,
    required this.text1, required this.text2, required this.text3, required this.text4,
    required this.line, required this.line2,
    required this.ice, required this.iceSoft, required this.teal, required this.tealDeep,
    required this.ok, required this.warn, required this.alert,
    required this.side0, required this.side1, required this.sideLine,
    required this.shadowSoft, required this.shadowCard, required this.shadowPop,
  });

  final Color canvas, canvasAlt, surface, surface2, surface3;
  final Color text1, text2, text3, text4, line, line2;
  final Color ice, iceSoft, teal, tealDeep, ok, warn, alert;
  final Color side0, side1, sideLine;
  final List<BoxShadow> shadowSoft, shadowCard, shadowPop;

  LinearGradient get accentGradient =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [ice, tealDeep]);
  LinearGradient get sidebarGradient =>
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [side1, side0]);
  List<BoxShadow> get glowIce => [
        BoxShadow(color: ice.withValues(alpha: .35), spreadRadius: 1),
        BoxShadow(color: ice.withValues(alpha: .30), blurRadius: 28, offset: const Offset(0, 8)),
      ];

  static const light = DentColors(
    canvas: AppPalette.lCanvas, canvasAlt: AppPalette.lCanvasAlt,
    surface: AppPalette.lSurface, surface2: AppPalette.lSurface2, surface3: AppPalette.lSurface3,
    text1: AppPalette.lText1, text2: AppPalette.lText2, text3: AppPalette.lText3, text4: AppPalette.lText4,
    line: AppPalette.lLine, line2: AppPalette.lLine2,
    ice: AppPalette.lIce, iceSoft: AppPalette.lIceSoft, teal: AppPalette.lTeal, tealDeep: AppPalette.lTealDeep,
    ok: AppPalette.ok, warn: AppPalette.warn, alert: AppPalette.alert,
    side0: AppPalette.lSide0, side1: AppPalette.lSide1, sideLine: AppPalette.lSideLine,
    shadowSoft: [BoxShadow(color: Color(0x0A0D1626), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x0F0D1626), blurRadius: 24, offset: Offset(0, 8))],
    shadowCard: [BoxShadow(color: Color(0x0D0D1626), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x120D1626), blurRadius: 32, offset: Offset(0, 12))],
    shadowPop: [BoxShadow(color: Color(0x2E0D1626), blurRadius: 60, offset: Offset(0, 24))],
  );

  static const dark = DentColors(
    canvas: AppPalette.dCanvas, canvasAlt: AppPalette.dCanvasAlt,
    surface: AppPalette.dSurface, surface2: AppPalette.dSurface2, surface3: AppPalette.dSurface3,
    text1: AppPalette.dText1, text2: AppPalette.dText2, text3: AppPalette.dText3, text4: AppPalette.dText4,
    line: AppPalette.dLine, line2: AppPalette.dLine2,
    ice: AppPalette.dIce, iceSoft: AppPalette.dIceSoft, teal: AppPalette.dTeal, tealDeep: AppPalette.dTealDeep,
    ok: AppPalette.okDark, warn: AppPalette.warn, alert: AppPalette.alert,
    side0: AppPalette.dSide0, side1: AppPalette.dSide1, sideLine: AppPalette.dSideLine,
    shadowSoft: [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14))],
    shadowCard: [BoxShadow(color: Color(0x73000000), blurRadius: 34, offset: Offset(0, 14))],
    shadowPop: [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24))],
  );

  @override
  DentColors copyWith({Color? canvas, canvasAlt, surface, surface2, surface3, text1, text2, text3, text4, line, line2, ice, iceSoft, teal, tealDeep, ok, warn, alert, side0, side1, sideLine, List<BoxShadow>? shadowSoft, shadowCard, shadowPop}) => DentColors(
        canvas: canvas ?? this.canvas, canvasAlt: canvasAlt ?? this.canvasAlt, surface: surface ?? this.surface, surface2: surface2 ?? this.surface2, surface3: surface3 ?? this.surface3,
        text1: text1 ?? this.text1, text2: text2 ?? this.text2, text3: text3 ?? this.text3, text4: text4 ?? this.text4, line: line ?? this.line, line2: line2 ?? this.line2,
        ice: ice ?? this.ice, iceSoft: iceSoft ?? this.iceSoft, teal: teal ?? this.teal, tealDeep: tealDeep ?? this.tealDeep, ok: ok ?? this.ok, warn: warn ?? this.warn, alert: alert ?? this.alert,
        side0: side0 ?? this.side0, side1: side1 ?? this.side1, sideLine: sideLine ?? this.sideLine,
        shadowSoft: shadowSoft ?? this.shadowSoft, shadowCard: shadowCard ?? this.shadowCard, shadowPop: shadowPop ?? this.shadowPop);

  @override
  DentColors lerp(ThemeExtension<DentColors>? o, double t) {
    if (o is! DentColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<BoxShadow> s(List<BoxShadow> a, List<BoxShadow> b) => t < .5 ? a : b;
    return DentColors(
      canvas: c(canvas, o.canvas), canvasAlt: c(canvasAlt, o.canvasAlt), surface: c(surface, o.surface), surface2: c(surface2, o.surface2), surface3: c(surface3, o.surface3),
      text1: c(text1, o.text1), text2: c(text2, o.text2), text3: c(text3, o.text3), text4: c(text4, o.text4), line: c(line, o.line), line2: c(line2, o.line2),
      ice: c(ice, o.ice), iceSoft: c(iceSoft, o.iceSoft), teal: c(teal, o.teal), tealDeep: c(tealDeep, o.tealDeep), ok: c(ok, o.ok), warn: c(warn, o.warn), alert: c(alert, o.alert),
      side0: c(side0, o.side0), side1: c(side1, o.side1), sideLine: c(sideLine, o.sideLine),
      shadowSoft: s(shadowSoft, o.shadowSoft), shadowCard: s(shadowCard, o.shadowCard), shadowPop: s(shadowPop, o.shadowPop));
  }
}

extension DentColorsX on BuildContext {
  DentColors get dent => Theme.of(this).extension<DentColors>()!;
}
