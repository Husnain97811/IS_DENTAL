import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/dent_colors.dart';

class MiniBarChart extends StatelessWidget {
  const MiniBarChart({super.key, required this.values, required this.labels, this.peakIndex, this.height = 170});
  final List<double> values; // 0..1
  final List<String> labels;
  final int? peakIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              TweenAnimationBuilder<double>(
                duration: Duration(milliseconds: 500 + i * 60), curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: values[i]),
                builder: (_, t, __) => Container(
                  height: height * .82 * t,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: i == peakIndex ? [d.teal, d.tealDeep] : [d.ice, d.teal.withValues(alpha: .55)]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(4)),
                    boxShadow: [BoxShadow(color: (i == peakIndex ? d.teal : d.ice).withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(labels[i], style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 7.sp, color: d.text4)),
            ]),
          )),
      ]),
    );
  }
}
