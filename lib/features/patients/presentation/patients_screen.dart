import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:is_dental/core/constants/app_flags.dart';
import 'package:is_dental/core/router/app_routes.dart';
import 'package:is_dental/features/patients/presentation/widgets/patient_editor.dart';
import 'package:sizer/sizer.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/dent_colors.dart';
import '../../../core/widgets/dent_avatar.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/status_chip.dart';
import '../domain/patient.dart';
import 'patients_controller.dart';

class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});
  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    if (kDebugMode && kSeedDemoData) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(patientRepositoryProvider).seedDemoDataIfEmpty(),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _avatarTones = [
    (Color(0xFF38BDF8), Color(0x2638BDF8)),
    (Color(0xFF13E0C4), Color(0x2613E0C4)),
    (Color(0xFFF59E0B), Color(0x24F59E0B)),
    (Color(0xFF64748B), Color(0x2464748B)),
  ];

  (ChipKind, String) _status(PatientStatus s) => switch (s) {
    PatientStatus.inTreatment => (ChipKind.inProgress, 'In Treatment'),
    PatientStatus.active => (ChipKind.done, 'Active'),
    PatientStatus.pendingPayment => (ChipKind.waiting, 'Pending Payment'),
    PatientStatus.newPatient => (ChipKind.upcoming, 'New'),
    PatientStatus.recallDue => (ChipKind.overdue, 'Recall Due'),
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final patientsAsync = ref.watch(patientsStreamProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Patients', style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 4),
          Text(
            'Active records · click a row to preview.',
            style: TextStyle(color: d.text3, fontSize: 9.sp),
          ),
          SizedBox(height: 2.h),
          _toolbar(d),
          SizedBox(height: 1.6.h),
          patientsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text('Error: $e', style: TextStyle(color: d.alert)),
              ),
            ),
            data: (all) {
              final list = _q.isEmpty
                  ? all
                  : all
                        .where(
                          (p) => '${p.fullName} ${p.phone} ${p.code}'
                              .toLowerCase()
                              .contains(_q.toLowerCase()),
                        )
                        .toList();
              return DentPanel(
                child: Column(
                  children: [
                    _headerRow(d),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'No patients found.',
                          style: TextStyle(color: d.text4),
                        ),
                      )
                    else
                      for (var i = 0; i < list.length; i++) _row(d, list[i], i),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _toolbar(DentColors d) => Row(
    children: [
      SizedBox(
        width: 320,
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _q = v),
          style: TextStyle(fontSize: 9.sp, color: d.text1),
          decoration: InputDecoration(
            hintText: 'Search by name, phone, or ID…',
            isDense: true,
            hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
            prefixIcon: Icon(Icons.search_rounded, color: d.text4, size: 11.sp),
            filled: true,
            fillColor: d.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: d.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: d.ice, width: 1.5),
            ),
          ),
        ),
      ),
      const Spacer(),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: d.ice,
          foregroundColor: AppPalette.onAccent,
        ),
        onPressed: () => showPatientEditor(context),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add Patient'),
      ),
    ],
  );

  Widget _headerRow(DentColors d) {
    TextStyle h() => TextStyle(
      color: d.text4,
      fontSize: 7.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .7,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('PATIENT', style: h())),
          Expanded(flex: 2, child: Text('PHONE', style: h())),
          Expanded(flex: 2, child: Text('LAST VISIT', style: h())),
          Expanded(flex: 2, child: Text('TREATMENT', style: h())),
          Expanded(flex: 1, child: Text('BALANCE', style: h())),
          Expanded(flex: 2, child: Text('STATUS', style: h())),
        ],
      ),
    );
  }

  Widget _row(DentColors d, Patient p, int i) {
    final selected = ref.watch(selectedPatientIdProvider) == p.id;
    final tone = _avatarTones[i % 4];
    final (chip, label) = _status(p.status);
    return InkWell(
      onTap: () => context.push('${AppRoutes.patients}/${p.id}'),

      // ref.read(selectedPatientIdProvider.notifier).state = p.id,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? d.surface2 : null,
          border: Border(bottom: BorderSide(color: d.line)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  DentAvatar(
                    p.initials,
                    bg: tone.$2,
                    fg: tone.$1,
                    size: 34,
                    radius: 10,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.fullName,
                          style: TextStyle(
                            color: d.text1,
                            fontWeight: FontWeight.w600,
                            fontSize: 9.sp,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '#${p.code}',
                          style: AppTypography.mono(
                            size: 7.5.sp,
                            color: d.text4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                p.phone,
                style: AppTypography.mono(size: 8.sp, color: d.text2),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                p.lastVisit == null ? '—' : _fmt(p.lastVisit!),
                style: TextStyle(color: d.text2, fontSize: 8.5.sp),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                p.treatmentSummary,
                style: TextStyle(color: d.text2, fontSize: 8.5.sp),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                p.balance == 0 ? 'Rs 0' : 'Rs ${_grp(p.balance)}',
                style: AppTypography.mono(
                  size: 8.5.sp,
                  color: p.balance > 0 ? d.alert : d.text1,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(label, kind: chip),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _grp(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  String _fmt(DateTime dt) =>
      '${dt.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]} ${dt.year}';
}
