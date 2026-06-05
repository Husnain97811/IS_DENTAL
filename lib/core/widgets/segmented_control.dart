import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/app_palette.dart';
import '../theme/dent_colors.dart';

class SegmentedControl extends StatelessWidget {
  const SegmentedControl({super.key, required this.items, required this.selected, required this.onChanged});
  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: d.surface, borderRadius: BorderRadius.circular(11), border: Border.all(color: d.line), boxShadow: d.shadowSoft),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: i == selected
                    ? (dark ? d.accentGradient : const LinearGradient(colors: [Color(0xFF0D1626), Color(0xFF1D2C46)]))
                    : null,
              ),
              child: Text(items[i],
                  style: TextStyle(fontSize: 8.5.sp, fontWeight: FontWeight.w600,
                      color: i == selected ? (dark ? AppPalette.onAccent : Colors.white) : d.text3)),
            ),
          ),
      ]),
    );
  }
}
