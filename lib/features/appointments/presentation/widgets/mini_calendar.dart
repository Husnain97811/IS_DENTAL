import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../appointments_controller.dart';

class MiniCalendar extends ConsumerWidget {
  const MiniCalendar({super.key});

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final now = DateTime.now();
    final selected = ref.watch(selectedDateProvider);
    final vm = ref.watch(viewedMonthProvider);
    final month = DateTime(vm.year, vm.month);
    final marked =
        ref.watch(markedDaysProvider((year: vm.year, month: vm.month))).value ??
        const <int>{};
    final daysInMonth = DateTime(vm.year, vm.month + 1, 0).day;
    final lead = DateTime(vm.year, vm.month, 1).weekday % 7; // Sunday-start

    void go(int delta) {
      final m = DateTime(vm.year, vm.month + delta);
      ref.read(viewedMonthProvider.notifier).state = (
        year: m.year,
        month: m.month,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_months[vm.month - 1]} ${vm.year}',
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    color: d.text1,
                  ),
                ),
              ),
              IconButton(
                iconSize: 18,
                color: d.text3,
                onPressed: () => go(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                iconSize: 18,
                color: d.text3,
                onPressed: () => go(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final w in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      color: d.text4,
                      fontSize: 7.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              for (var i = 0; i < lead; i++) const SizedBox(),
              for (var day = 1; day <= daysInMonth; day++)
                _cell(ref, d, month, day, now, selected, marked.contains(day)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(
    WidgetRef ref,
    DentColors d,
    DateTime month,
    int day,
    DateTime now,
    DateTime selected,
    bool marked,
  ) {
    final date = DateTime(month.year, month.month, day);
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final isSel =
        date.year == selected.year &&
        date.month == selected.month &&
        date.day == selected.day;
    return GestureDetector(
      onTap: () => ref.read(selectedDateProvider.notifier).state = date,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: isSel ? d.accentGradient : null,
          border: isToday && !isSel ? Border.all(color: d.ice) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$day',
              style: AppTypography.mono(
                size: 7.5.sp,
                color: isSel ? AppPalette.onAccent : d.text2,
              ),
            ),
            if (marked && !isSel)
              Positioned(
                bottom: 3,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: d.teal,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
