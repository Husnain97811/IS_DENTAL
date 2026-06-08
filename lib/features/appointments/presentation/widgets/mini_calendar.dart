import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../appointments_controller.dart';

class MiniCalendar extends ConsumerStatefulWidget {
  const MiniCalendar({super.key});
  @override
  ConsumerState<MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends ConsumerState<MiniCalendar> {
  late DateTime _month;
  @override
  void initState() {
    super.initState();
    final s = ref.read(selectedDateProvider);
    _month = DateTime(s.year, s.month);
  }

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
  Widget build(BuildContext context) {
    final d = context.dent;
    final now = DateTime.now();
    final selected = ref.watch(selectedDateProvider);
    final marked =
        ref
            .watch(markedDaysProvider((year: _month.year, month: _month.month)))
            .value ??
        {};
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead =
        DateTime(_month.year, _month.month, 1).weekday % 7; // Sunday-start

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_months[_month.month - 1]} ${_month.year}',
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
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                iconSize: 18,
                color: d.text3,
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
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
                _cell(d, day, now, selected, marked.contains(day)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(
    DentColors d,
    int day,
    DateTime now,
    DateTime selected,
    bool marked,
  ) {
    final date = DateTime(_month.year, _month.month, day);
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
