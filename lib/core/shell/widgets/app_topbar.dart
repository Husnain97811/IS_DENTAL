import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../router/nav_destinations.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';
import '../../theme/dent_colors.dart';
import '../../theme/theme_controller.dart';

class AppTopbar extends ConsumerWidget {
  const AppTopbar({super.key, required this.destination, required this.onToggleSidebar});
  final NavDestination destination;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: d.surface.withValues(alpha: .7),
            border: Border(bottom: BorderSide(color: d.line)),
          ),
          child: Row(children: [
            _iconBtn(context, Icons.menu_rounded, onToggleSidebar),
            SizedBox(width: 3.w),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(destination.title, style: Theme.of(context).textTheme.headlineSmall),
              Text(destination.subtitle, style: TextStyle(color: d.text4, fontSize: 8.sp)),
            ]),
            SizedBox(width: 3.w),
            Expanded(child: _searchField(context)),
            SizedBox(width: 2.w),
            _iconBtn(context, isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                () => ref.read(themeModeProvider.notifier).toggle()),
            const SizedBox(width: 10),
            _iconBtn(context, Icons.notifications_none_rounded, () {}, dot: true),
            const SizedBox(width: 10),
            _iconBtn(context, Icons.storage_rounded, () {}),
            const SizedBox(width: 10),
            _primaryButton(context),
          ]),
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final d = context.dent;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: TextField(
        style: TextStyle(fontSize: 9.5.sp, color: d.text1),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search patients, invoices, appointments…',
          hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
          prefixIcon: Icon(Icons.search_rounded, color: d.text4, size: 11.sp),
          filled: true, fillColor: d.surface2,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.ice, width: 1.5)),
        ),
      ),
    );
  }

  Widget _iconBtn(BuildContext context, IconData icon, VoidCallback onTap, {bool dot = false}) {
    final d = context.dent;
    return Material(
      color: d.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: d.line)),
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, size: 11.sp, color: d.text3),
            if (dot) Positioned(top: 9, right: 10,
                child: Container(width: 8, height: 8, decoration: BoxDecoration(color: d.alert, shape: BoxShape.circle, border: Border.all(color: d.surface, width: 2)))),
          ]),
        ),
      ),
    );
  }

  Widget _primaryButton(BuildContext context) {
    final d = context.dent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {},
        child: Container(
          height: 42, padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(gradient: d.accentGradient, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: d.teal.withValues(alpha: .35), blurRadius: 22, offset: const Offset(0, 8))]),
          child: Row(children: [
            const Icon(Icons.add_rounded, color: AppPalette.onAccent, size: 18),
            const SizedBox(width: 8),
            Text(destination.primaryAction, style: TextStyle(fontFamily: AppFonts.body, color: AppPalette.onAccent, fontWeight: FontWeight.w700, fontSize: 9.sp)),
          ]),
        ),
      ),
    );
  }
}
