import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:is_dental/core/constants/app_flags.dart';
import 'package:is_dental/core/router/app_routes.dart';
import 'package:is_dental/features/patients/presentation/widgets/tooth_chart_screen.dart';
import 'package:sizer/sizer.dart';

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

  // Single source of truth for column widths. Header and rows both read from
  // this, so the columns can never drift out of alignment again.
  static const _colFlex = (patient: 4, phone: 3, cnic: 3, status: 2);

  // TEMP: set to false to hide the column boundary lines.
  static const _debugColLines = false;

  // A full-height divider between columns (only when _debugColLines is on).
  // Rows must be wrapped in IntrinsicHeight for it to stretch to full height.
  Widget get _vline => _debugColLines
      ? const VerticalDivider(width: 1, thickness: 1, color: Color(0x66FF3B30))
      : const SizedBox.shrink();

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Patients', style: Theme.of(context).textTheme.displayLarge),
              // Row(
              //   children: [
              //     OutlinedButton.icon(
              //       onPressed: () => context.go(AppRoutes.offers),
              //       icon: Icon(Icons.campaign_rounded, size: 12.sp),
              //       label: const Text('Offers'),
              //     ),
              //     SizedBox(width: 0.5.w),
              //     toothChartButton(d),
              //   ],
              // ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Active records · click arrow to preview.',
            style: TextStyle(color: d.text3, fontSize: 11.sp),
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
                        .where(
                          (p) => '${p.fullName} ${p.phone} ${p.code} ${p.cnic}'
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

  Widget toothChartButton(DentColors d) {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ToothChartScreen()));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF38BDF8), Color(0xFF13E0C4)], // ice → teal
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF38BDF8).withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          '3D Chart',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 9.9.sp,
            letterSpacing: 0.4,
          ),
        ),
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
          style: TextStyle(fontSize: 9.9.sp, color: d.text1),
          decoration: InputDecoration(
            hintText: 'Search by name, phone, or ID…',
            isDense: true,
            hintStyle: TextStyle(color: d.text4, fontSize: 9.9.sp),
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

      // const Spacer(),
      // FilledButton.icon(
      //   style: FilledButton.styleFrom(
      //     backgroundColor: d.ice,
      //     foregroundColor: AppPalette.onAccent,
      //   ),
      //   onPressed: () => showPatientEditor(context),
      //   icon: const Icon(Icons.add_rounded, size: 18),
      //   label: const Text('Add Patient'),
      // ),
    ],
  );

  Widget _headerRow(DentColors d) {
    TextStyle h() => TextStyle(
      color: d.text4,
      fontSize: 9.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .7,
    );
    // Same horizontal padding as _row so labels sit directly above cell content.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              flex: _colFlex.patient,
              child: Text('PATIENT', style: h()),
            ),
            _vline,
            Expanded(
              flex: _colFlex.phone,
              child: Text('PHONE', style: h()),
            ),
            _vline,
            Expanded(
              flex: _colFlex.cnic,
              child: Text('CNIC', style: h()),
            ),
            _vline,
            Expanded(
              flex: _colFlex.status,
              child: Text('STATUS', style: h()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(DentColors d, Patient p, int i) {
    final selected = ref.watch(selectedPatientIdProvider) == p.id;
    final tone = _avatarTones[i % 4];
    final (chip, label) = _status(p.status);
    return InkWell(
      onTap: () =>
          // context.push('${AppRoutes.patients}/${p.id}'),
          ref.read(selectedPatientIdProvider.notifier).state = p.id,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? d.surface2 : null,
          border: Border(bottom: BorderSide(color: d.line)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                flex: _colFlex.patient,
                child: Row(
                  children: [
                    DentAvatar(
                      p.initials,
                      bg: tone.$2,
                      fg: tone.$1,
                      size: 19.sp,
                      radius: 10,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.fullName.split(' ').take(2).join(' '),
                            style: TextStyle(
                              color: d.text1,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.65.sp,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),

                          Text(
                            '#${p.code}',
                            style: AppTypography.mono(
                              size: 10.45.sp,
                              color: d.text4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _vline,
              Expanded(
                flex: _colFlex.phone,
                child: Text(
                  p.phone,
                  style: AppTypography.mono(size: 8.8.sp, color: d.text2),
                ),
              ),

              _vline,
              Expanded(
                flex: _colFlex.cnic,
                child: Text(
                  p.cnic.isEmpty ? '—' : p.cnic,
                  style: AppTypography.mono(size: 8.8.sp, color: d.text2),
                ),
              ),

              _vline,
              Expanded(
                flex: _colFlex.status,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(label, kind: chip),
                ),
              ),
            ],
          ),
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
