import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../domain/treatment_plan.dart';

class TreatmentPlanTimeline extends StatelessWidget {
  const TreatmentPlanTimeline({super.key, required this.steps});
  final List<TreatmentStep> steps;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < steps.length; i++)
        _step(context, steps[i], i, i == steps.length - 1),
    ],
  );

  Widget _step(BuildContext context, TreatmentStep s, int i, bool last) {
    final d = context.dent;
    final (Color nodeBg, Color nodeFg, Widget mark) = switch (s.status) {
      StepStatus.done => (
        d.teal,
        AppPalette.onAccent,
        const Icon(Icons.check_rounded, size: 13, color: AppPalette.onAccent),
      ),
      StepStatus.current => (
        d.surface,
        d.ice,
        Icon(Icons.circle, size: 9, color: d.ice),
      ),
      StepStatus.todo => (
        d.surface2,
        d.text4,
        Text(
          '${i + 1}',
          style: TextStyle(
            color: d.text4,
            fontSize: 7.5.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nodeBg,
                  shape: BoxShape.circle,
                  border: s.status == StepStatus.current
                      ? Border.all(color: d.ice, width: 2)
                      : (s.status == StepStatus.todo
                            ? Border.all(color: d.line2)
                            : null),
                  boxShadow: s.status == StepStatus.current
                      ? [
                          BoxShadow(
                            color: d.ice.withValues(alpha: .16),
                            blurRadius: 0,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: mark,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: s.status == StepStatus.done
                        ? d.teal.withValues(alpha: .5)
                        : d.line2,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 1.6.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w600,
                      color: s.status == StepStatus.current ? d.ice : d.text1,
                    ),
                  ),
                  Text(
                    s.detail,
                    style: TextStyle(fontSize: 7.5.sp, color: d.text4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
