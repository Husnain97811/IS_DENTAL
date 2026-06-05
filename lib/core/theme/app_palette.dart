import 'package:flutter/material.dart';

/// Raw tokens — never used directly in widgets. Go through [DentColors].
class AppPalette {
  AppPalette._();
  // LIGHT
  static const lCanvas = Color(0xFFEEF3F9), lCanvasAlt = Color(0xFFF6F9FC);
  static const lSurface = Color(0xFFFFFFFF), lSurface2 = Color(0xFFF9FBFE), lSurface3 = Color(0xFFF1F6FC);
  static const lText1 = Color(0xFF0D1626), lText2 = Color(0xFF33415C), lText3 = Color(0xFF64748B), lText4 = Color(0xFF94A3B8);
  static const lLine = Color(0xFFE6EDF5), lLine2 = Color(0xFFDBE5F0);
  static const lIce = Color(0xFF38BDF8), lIceSoft = Color(0xFF7DD3FC), lTeal = Color(0xFF13E0C4), lTealDeep = Color(0xFF0BB6A0);
  // DARK
  static const dCanvas = Color(0xFF070B14), dCanvasAlt = Color(0xFF0B1120);
  static const dSurface = Color(0xFF101A2C), dSurface2 = Color(0xFF0C1424), dSurface3 = Color(0xFF16223A);
  static const dText1 = Color(0xFFEAF1FB), dText2 = Color(0xFFAEBBD1), dText3 = Color(0xFF7385A3), dText4 = Color(0xFF566681);
  static const dLine = Color(0xFF1D2B45), dLine2 = Color(0xFF243453);
  static const dIce = Color(0xFF46C6FF), dIceSoft = Color(0xFF8BD9FF), dTeal = Color(0xFF1EE9CC), dTealDeep = Color(0xFF13C4AD);
  // SIDEBAR (dark hybrid in both themes)
  static const lSide0 = Color(0xFF0B1422), lSide1 = Color(0xFF0F1C30), lSideLine = Color(0xFF1C2C45);
  static const dSide0 = Color(0xFF05080F), dSide1 = Color(0xFF0A1120), dSideLine = Color(0xFF172238);
  static const sideText = Color(0xFF95A5BF), sideTextHover = Color(0xFFDBE6F5), sideTextActive = Color(0xFFEAF6FF), sideLabel = Color(0xFF4F6080);
  // STATUS
  static const ok = Color(0xFF22C55E), okDark = Color(0xFF34D399), warn = Color(0xFFF59E0B), alert = Color(0xFFFB7185);
  static const onAccent = Color(0xFF04121F);
}
