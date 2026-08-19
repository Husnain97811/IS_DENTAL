import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/patients/presentation/widgets/tooth_chart_screen.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/app_flags.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/dent_colors.dart';
import '../domain/treatment.dart';
import 'treatments_controller.dart';
import 'widgets/treatment_editor.dart';

class TreatmentsScreen extends ConsumerStatefulWidget {
  const TreatmentsScreen({super.key});
  @override
  ConsumerState<TreatmentsScreen> createState() => _S();
}

class _S extends ConsumerState<TreatmentsScreen> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode && kSeedDemoData) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(treatmentRepositoryProvider).seedDemoIfEmpty(),
      );
    }
  }

  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (x) => '${x[1]},',
  );

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final async = ref.watch(treatmentsStreamProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 2.2.h),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        'No procedures yet. Use "New Procedure" in the top bar.',
                        style: TextStyle(color: d.text4),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth < 640
                          ? 1
                          : (c.maxWidth < 1000 ? 2 : 3);
                      const gap = 16.0;
                      final w = (c.maxWidth - gap * (cols - 1)) / cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final t in list)
                            SizedBox(width: w, child: _card(d, t)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(DentColors d, Treatment t) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => showTreatmentEditor(context, existing: t),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
        boxShadow: d.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                colors: [
                  d.ice.withValues(alpha: .16),
                  d.teal.withValues(alpha: .10),
                ],
              ),
            ),
            child: Icon(
              Icons.medical_services_rounded,
              color: d.tealDeep,
              size: 12.sp,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            t.name,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              color: d.text1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            t.category.toUpperCase(),
            style: TextStyle(
              color: d.text4,
              fontSize: 7.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: d.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs ${_m(t.price)}',
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: d.text1,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 13, color: d.text3),
                    const SizedBox(width: 5),
                    Text(
                      t.duration,
                      style: TextStyle(color: d.text3, fontSize: 8.sp),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
