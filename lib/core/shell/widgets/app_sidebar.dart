import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../router/nav_destinations.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';
import '../../theme/dent_colors.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.collapsed, required this.currentIndex, required this.onSelect});
  final bool collapsed;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const _groupTitles = {NavGroup.clinical: 'Clinical', NavGroup.operations: 'Operations', NavGroup.system: 'System'};

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: collapsed ? 78 : 252,
      decoration: BoxDecoration(gradient: d.sidebarGradient, border: Border(right: BorderSide(color: d.sideLine))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(context),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 1.h),
              children: [
                for (final g in NavGroup.values) ..._group(context, g),
              ],
            ),
          ),
          _docCard(context),
        ],
      ),
    );
  }

  Widget _brand(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(14, 2.2.h, 14, 1.6.h),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(gradient: context.dent.accentGradient, borderRadius: BorderRadius.circular(11)),
            alignment: Alignment.center,
            child: Text('D', style: TextStyle(fontFamily: AppFonts.display, fontSize: 11.sp, fontWeight: FontWeight.w700, color: AppPalette.onAccent)),
          ),
          if (!collapsed) ...[
            SizedBox(width: 3.w),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DentOS', style: TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700)),
                Text('CLINICAL SUITE', style: TextStyle(color: AppPalette.sideLabel, fontSize: 6.5.sp, letterSpacing: 1)),
              ]),
            ),
          ],
        ]),
      );

  List<Widget> _group(BuildContext context, NavGroup group) {
    final items = <Widget>[];
    if (!collapsed) {
      items.add(Padding(
        padding: EdgeInsets.fromLTRB(22, 1.4.h, 12, .6.h),
        child: Text(_groupTitles[group]!.toUpperCase(),
            style: TextStyle(color: AppPalette.sideLabel, fontSize: 6.2.sp, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
      ));
    } else {
      items.add(SizedBox(height: 1.4.h));
    }
    for (var i = 0; i < kNavDestinations.length; i++) {
      if (kNavDestinations[i].group == group) items.add(_navItem(context, i));
    }
    return items;
  }

  Widget _navItem(BuildContext context, int index) {
    final dest = kNavDestinations[index];
    final active = index == currentIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => onSelect(index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: active ? const LinearGradient(colors: [Color(0x3038BDF8), Color(0x0D13E0C4)]) : null,
            ),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (active && !collapsed)
                  Container(width: 3, height: 20, margin: const EdgeInsets.only(right: 9),
                      decoration: BoxDecoration(gradient: context.dent.accentGradient, borderRadius: BorderRadius.circular(4))),
                Icon(dest.icon, size: 11.sp, color: active ? AppPalette.sideTextActive : AppPalette.sideText),
                if (!collapsed) ...[
                  SizedBox(width: 3.w),
                  Expanded(child: Text(dest.label,
                      style: TextStyle(color: active ? AppPalette.sideTextActive : AppPalette.sideText, fontSize: 9.5.sp, fontWeight: FontWeight.w500))),
                  if (dest.badge != null)
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0x2B38BDF8), borderRadius: BorderRadius.circular(20)),
                        child: Text(dest.badge!, style: TextStyle(color: context.dent.iceSoft, fontSize: 7.5.sp, fontWeight: FontWeight.w600))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _docCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.dent.sideLine))),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: const Color(0x0AFFFFFF), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Container(width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(50),
                    gradient: const LinearGradient(colors: [Color(0xFF1F3A5F), Color(0xFF0D2640)]),
                    border: Border.all(color: const Color(0x4D7DD3FC))),
                child: Text('AK', style: TextStyle(color: const Color(0xFFBFE3FF), fontSize: 8.sp, fontWeight: FontWeight.w700))),
            if (!collapsed) ...[
              SizedBox(width: 2.6.w),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Dr. Ayesha Khan', style: TextStyle(color: const Color(0xFFE9F2FF), fontSize: 8.5.sp, fontWeight: FontWeight.w600)),
                Text('Lead Orthodontist', style: TextStyle(color: const Color(0xFF6F7F99), fontSize: 7.sp)),
              ])),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6F7F99), size: 18),
            ],
          ]),
        ),
      );
}
