import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../domain/patient.dart';
import '../../domain/tooth_record.dart';
import '../patients_controller.dart';
import 'odontogram.dart';
import 'treatment_plan_timeline.dart';

class PatientSnapshotDrawer extends ConsumerWidget {
  const PatientSnapshotDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final p = ref.watch(selectedPatientProvider);
    if (p == null) {
      return _wrap(
        context,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(6.w),
            child: Text(
              'Select a patient to preview.',
              textAlign: TextAlign.center,
              style: TextStyle(color: d.text4, fontSize: 9.sp),
            ),
          ),
        ),
      );
    }
    final toothAsync = ref.watch(toothRecordsProvider(p.id));
    final planAsync = ref.watch(activePlanProvider(p.id));

    void cycle(int fdi) {
      final map =
          ref.read(toothRecordsProvider(p.id)).value ??
          const <int, ToothRecord>{};
      final cur = map[fdi]?.state ?? ToothState.healthy;
      const order = ToothState.values;
      final next = order[(cur.index + 1) % order.length];
      ref.read(patientRepositoryProvider).setToothState(p.id, fdi, next);
    }

    return _wrap(
      context,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _patientCard(context, p),
          _quickStats(context, p),
          _section(
            context,
            'Dental Chart',
            'FDI · tap a tooth to update',
            toothAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
              data: (states) => Odontogram(
                states: {for (final e in states.entries) e.key: e.value.state},
                onToothTap: cycle,
              ),
            ),
          ),
          planAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (plan) => plan == null
                ? const SizedBox.shrink()
                : _section(
                    context,
                    plan.title,
                    null,
                    TreatmentPlanTimeline(steps: plan.steps),
                  ),
          ),
          _actions(context),
        ],
      ),
    );
  }

  Widget _wrap(BuildContext context, {required Widget child}) {
    final d = context.dent;
    return Container(
      width: 332,
      decoration: BoxDecoration(
        color: d.surface,
        border: Border(left: BorderSide(color: d.line)),
      ),
      child: child,
    );
  }

  Widget _patientCard(BuildContext context, Patient p) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 74,
                height: 74,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0EA5E9), Color(0xFF0D2640)],
                  ),
                ),
                child: Text(
                  p.initials,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: Colors.white,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                bottom: 3,
                right: 3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: d.ok,
                    shape: BoxShape.circle,
                    border: Border.all(color: d.surface, width: 3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(p.fullName, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 3),
          Text(
            '${_cap(p.gender.name)} · ${p.age} yrs · ID #${p.code}',
            style: TextStyle(color: d.text3, fontSize: 8.5.sp),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              if (p.allergies != null)
                _tag(context, '⚠ ${p.allergies}', d.alert),
              if (p.insurance != null)
                _tag(context, 'Insured · ${p.insurance}', d.ice),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickStats(BuildContext context, Patient p) {
    final d = context.dent;
    Widget cell(String label, String value, {Color? color}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        color: d.surface,
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: d.text4,
                fontSize: 7.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
                color: color ?? d.text1,
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          cell('Last Visit', p.lastVisit == null ? '—' : _fmt(p.lastVisit!)),
          Container(width: 1, height: 44, color: d.line),
          cell('Visits', '${p.visitCount}'),
          Container(width: 1, height: 44, color: d.line),
          cell(
            'Balance',
            p.balance == 0 ? 'Rs 0' : 'Rs ${_grp(p.balance)}',
            color: p.balance > 0 ? d.alert : null,
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    String? sub,
    Widget body,
  ) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 9.5.sp,
                    fontWeight: FontWeight.w600,
                    color: d.text1,
                  ),
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: TextStyle(color: d.text4, fontSize: 7.sp),
                ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
      child: Column(
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
              minimumSize: const Size.fromHeight(42),
            ),
            onPressed: () {},
            icon: const Icon(Icons.folder_open_rounded, size: 17),
            label: const Text('Open Full Record'),
          ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: d.text2,
              side: BorderSide(color: d.line),
              minimumSize: const Size.fromHeight(42),
            ),
            onPressed: () {},
            icon: const Icon(Icons.event_rounded, size: 17),
            label: const Text('Schedule Follow-up'),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 7.5.sp,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  String _grp(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  String _fmt(DateTime dt) =>
      '${dt.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]}';
}
