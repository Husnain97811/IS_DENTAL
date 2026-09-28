import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/dent_colors.dart';

class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.peakIndex,
    this.height,
  });

  final List<double> values; // 0..1
  final List<String> labels;
  final int? peakIndex;

  /// Defaults to 16% of screen height, clamped to a sane desktop range.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;

    final chartHeight = height ?? (16.h).clamp(120.0, 190.0);
    final labelBlock = 3.2.h.clamp(24.0, 34.0);
    final trackHeight = chartHeight - labelBlock;

    return SizedBox(
      height: chartHeight,
      child: LayoutBuilder(
        builder: (context, c) {
          // bar width from the PANEL's width, not the screen's
          final slot = c.maxWidth / values.length;
          final barWidth = (slot * .42).clamp(12.0, 34.0);
          final radius = (barWidth * .28).clamp(4.0, 9.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: trackHeight,
                        child: Center(
                          child: SizedBox(
                            width: barWidth,
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                Container(
                                  height: trackHeight,
                                  decoration: BoxDecoration(
                                    color: d.line.withValues(alpha: .45),
                                    borderRadius: BorderRadius.circular(radius),
                                  ),
                                ),
                                TweenAnimationBuilder<double>(
                                  duration: Duration(
                                    milliseconds: 460 + i * 55,
                                  ),
                                  curve: Curves.easeOutCubic,
                                  tween: Tween(begin: 0, end: values[i]),
                                  builder: (_, t, __) => Container(
                                    height: 3 + (trackHeight - 3) * t,
                                    decoration: BoxDecoration(
                                      color: i == peakIndex
                                          ? d.teal
                                          : d.ice.withValues(alpha: .28),
                                      borderRadius: BorderRadius.circular(
                                        radius,
                                      ),
                                      boxShadow: i == peakIndex
                                          ? [
                                              BoxShadow(
                                                color: d.teal.withValues(
                                                  alpha: .28,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: .9.h),
                      Text(
                        labels[i],
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 9.5.sp,
                          letterSpacing: .3,
                          color: i == peakIndex ? d.teal : d.text3,
                          fontWeight: i == peakIndex
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
