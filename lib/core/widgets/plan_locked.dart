import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

/// Shown in place of a feature the clinic's plan doesn't include.
///
/// Full size for a whole screen or tab (what the feature does, what's in
/// it, the clinic's current plan); [PlanLocked.compact] for a card that sits
/// among other cards.
class PlanLocked extends ConsumerWidget {
  const PlanLocked({
    super.key,
    required this.feature,
    required this.pitch,
    this.icon = Icons.workspace_premium_rounded,
    this.points = const [],
  }) : compact = false;

  const PlanLocked.compact({
    super.key,
    required this.feature,
    required this.pitch,
    this.icon = Icons.workspace_premium_rounded,
  }) : points = const [],
       compact = true;

  final String feature, pitch;
  final IconData icon;
  final List<String> points;
  final bool compact;

  static const plans = 'Standard & Premium';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final current = ref.watch(entitlementsProvider).tierLabel;
    return compact ? _compact(d) : _full(d, current);
  }

  Widget _badge(DentColors d) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: d.warn.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_rounded, size: 12, color: d.warn),
        const SizedBox(width: 5),
        Text(
          plans,
          style: TextStyle(
            color: d.warn,
            fontSize: 8.6.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _icon(DentColors d, double size) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [d.ice.withValues(alpha: .18), d.teal.withValues(alpha: .10)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(icon, size: size * .46, color: d.ice),
  );

  Widget _compact(DentColors d) => Container(
    padding: EdgeInsets.all((1.3.w).clamp(16.0, 22.0)),
    decoration: BoxDecoration(
      color: d.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: d.line),
    ),
    child: Row(
      children: [
        _icon(d, 46),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    feature,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      color: d.text1,
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _badge(d),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                pitch,
                style: TextStyle(color: d.text3, fontSize: 9.8.sp, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _full(DentColors d, String current) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: (46.w).clamp(420.0, 620.0)),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4.h, horizontal: 16),
        padding: EdgeInsets.all((2.2.w).clamp(24.0, 40.0)),
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _icon(d, 64),
            const SizedBox(height: 18),
            _badge(d),
            const SizedBox(height: 14),
            Text(
              feature,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: d.text1,
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pitch,
              textAlign: TextAlign.center,
              style: TextStyle(color: d.text3, fontSize: 10.5.sp, height: 1.5),
            ),
            if (points.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: d.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in points)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 17,
                              color: d.tealDeep,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p,
                                style: TextStyle(
                                  color: d.text2,
                                  fontSize: 10.sp,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Your plan: $current  ·  Contact DentOS support to upgrade',
              textAlign: TextAlign.center,
              style: TextStyle(color: d.text4, fontSize: 9.4.sp),
            ),
          ],
        ),
      ),
    ),
  );
}
