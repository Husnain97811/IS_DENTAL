import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/theme/app_typography.dart';
import 'package:is_dental/core/theme/dent_colors.dart';
import 'package:is_dental/core/widgets/dent_avatar.dart';
import 'package:is_dental/core/widgets/dent_panel.dart';
import 'package:is_dental/core/widgets/status_chip.dart';
import '../domain/patient.dart';
import '../domain/tooth_record.dart';
import '../domain/treatment_plan.dart';
import 'patients_controller.dart';
import 'widgets/odontogram.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/presentation/appointments_controller.dart';
import '../../billing/domain/invoice.dart';
import '../../billing/presentation/billing_controller.dart';
import 'package:is_dental/core/widgets/segmented_control.dart';
import 'package:is_dental/features/patients/presentation/widgets/tooth_model_3d.dart';

String _money(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
String _fmtDate(DateTime dt) =>
    '${dt.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]} ${dt.year}';

class PatientDetailScreen extends ConsumerWidget {
  const PatientDetailScreen({super.key, required this.patientId});
  final int patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final patient = ref.watch(patientByIdProvider(patientId));

    if (patient == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      );
    }

    final toothRecords =
        ref.watch(toothRecordsProvider(patientId)).value ?? const {};
    final toothStates = {
      for (final e in toothRecords.entries) e.key: e.value.state,
    };
    final plan = ref.watch(activePlanProvider(patientId)).value;
    final appts =
        ref.watch(appointmentsForPatientProvider(patientId)).value ??
        const <Appointment>[];
    final invoices =
        (ref.watch(invoicesStreamProvider).value ?? const <Invoice>[])
            .where((i) => i.patientId == patientId)
            .toList();

    final now = DateTime.now();
    final lastVisit = appts
        .where((a) => a.startsAt.isBefore(now))
        .fold<Appointment?>(null, (best, a) => best); // appts already desc
    final lastPast = appts.where((a) => a.startsAt.isBefore(now)).toList();
    final last = lastPast.isNotEmpty ? lastPast.first : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, d, patient),
          SizedBox(height: 2.h),

          _quickStats(context, d, patient, last),
          _DentalChartCard(
            patientId: patientId,
            states: toothStates,
            records: toothRecords,
          ),
          SizedBox(height: 2.h),
          LayoutBuilder(
            builder: (context, c) {
              final stack = c.maxWidth < 980;
              final leftCol = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _lastVisitCard(context, d, patient, last),
                  const SizedBox(height: 18),
                  _historyCard(context, d, appts),
                  const SizedBox(height: 18),
                  _invoicesCard(context, d, invoices),
                ],
              );
              final rightCol = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // _chartCard(context, ref, d, toothStates, toothRecords),

                  // const SizedBox(height: 18),
                  _planCard(context, d, plan),
                  const SizedBox(height: 18),
                  _detailsCard(context, d, patient),
                ],
              );
              if (stack) {
                return Column(
                  children: [rightCol, const SizedBox(height: 18), leftCol],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 11, child: leftCol),
                  const SizedBox(width: 18),
                  Expanded(flex: 10, child: rightCol),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---- header ----
  Widget _header(BuildContext context, DentColors d, Patient p) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconButton(
        onPressed: () => context.pop(),
        icon: Icon(Icons.arrow_back_rounded, color: d.text2, size: 13.sp),
        tooltip: 'Back',
      ),
      const SizedBox(width: 6),
      DentAvatar(
        p.initials,
        bg: const Color(0x2638BDF8),
        fg: const Color(0xFF38BDF8),
        size: 56,
        radius: 16,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.fullName, style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 3),
            Text(
              '#${p.code} · ${p.gender.name} · ${p.age} yrs',
              style: AppTypography.mono(size: 8.sp, color: d.text3),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if ((p.allergies ?? '').isNotEmpty)
                  _tag(d, '⚠ ${p.allergies}', d.alert),
                if ((p.insurance ?? '').isNotEmpty)
                  _tag(d, 'Insured · ${p.insurance}', d.ice),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _tag(DentColors d, String text, Color color) => Container(
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

  // ---- quick stats ----
  Widget _quickStats(
    BuildContext context,
    DentColors d,
    Patient p,
    Appointment? last,
  ) => Row(
    children: [
      _stat(d, 'Total Visits', '${p.visitCount}'),
      const SizedBox(width: 14),
      _stat(
        d,
        'Balance',
        'Rs ${_money(p.balance)}',
        color: p.balance > 0 ? d.alert : null,
      ),
      const SizedBox(width: 14),
      _stat(
        d,
        'Last Visit',
        last != null
            ? _fmtDate(last.startsAt)
            : (p.lastVisit != null ? _fmtDate(p.lastVisit!) : '—'),
      ),
    ],
  );

  Widget _stat(DentColors d, String label, String value, {Color? color}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: d.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: d.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: d.text3,
                  fontSize: 8.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: color ?? d.text1,
                ),
              ),
            ],
          ),
        ),
      );

  // ---- last visit (separate & clear) ----
  Widget _lastVisitCard(
    BuildContext context,
    DentColors d,
    Patient p,
    Appointment? last,
  ) => DentPanel(
    title: 'Last Visit',
    subtitle: 'Most recent completed appointment',
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: last == null
          ? Text(
              p.lastVisit != null
                  ? 'Last seen on ${_fmtDate(p.lastVisit!)}.'
                  : 'No visits recorded yet.',
              style: TextStyle(color: d.text3, fontSize: 9.sp),
            )
          : Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d.ice.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.event_available_rounded,
                    color: d.ice,
                    size: 14.sp,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmtDate(last.startsAt),
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${last.procedure} · ${last.dentist}',
                        style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    ),
  );

  // ---- visit history ----
  Widget _historyCard(
    BuildContext context,
    DentColors d,
    List<Appointment> appts,
  ) => DentPanel(
    title: 'Visit History',
    subtitle: '${appts.length} total',
    child: appts.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'No appointments recorded.',
              style: TextStyle(color: d.text4, fontSize: 9.sp),
            ),
          )
        : Column(
            children: [
              for (final a in appts)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: d.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.procedure,
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_fmtDate(a.startsAt)} · ${a.dentist}',
                              style: TextStyle(color: d.text3, fontSize: 8.sp),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(
                        _prettify(a.status.name),
                        kind: _apptKind(a.status),
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );

  // ---- invoices ----
  Widget _invoicesCard(
    BuildContext context,
    DentColors d,
    List<Invoice> invoices,
  ) => DentPanel(
    title: 'Invoices',
    subtitle: '${invoices.length} total',
    child: invoices.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'No invoices.',
              style: TextStyle(color: d.text4, fontSize: 9.sp),
            ),
          )
        : Column(
            children: [
              for (final i in invoices)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: d.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${i.invoiceNo} · ${i.summary}',
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fmtDate(i.issuedAt),
                              style: TextStyle(color: d.text3, fontSize: 8.sp),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Rs ${_money(i.total)}',
                        style: AppTypography.mono(size: 8.5.sp, color: d.text1),
                      ),
                      const SizedBox(width: 12),
                      StatusChip(
                        _prettify(i.status.name),
                        kind: _invKind(i.status),
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );

  // ---- dental chart (rotatable + tap to edit) ----
  // Widget _chartCard(
  //   BuildContext context,
  //   WidgetRef ref,
  //   DentColors d,
  //   Map<int, ToothState> states,
  //   Map<int, ToothRecord> records,
  // ) => DentPanel(
  //   title: 'Dental Chart',
  //   subtitle: 'FDI · drag to rotate · tap a tooth to update',
  //   child: Padding(
  //     padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
  //     child: _Rotatable(
  //       child: Odontogram(
  //         states: states,
  //         onToothTap: (fdi) =>
  //             _showToothSheet(context, ref, patientId, fdi, records[fdi]),
  //       ),
  //     ),
  //   ),
  // );

  // ---- treatment plan ----
  Widget _planCard(BuildContext context, DentColors d, TreatmentPlan? plan) =>
      DentPanel(
        title: 'Treatment Plan',
        subtitle: plan?.title ?? 'None active',
        child: plan == null || plan.steps.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'No active treatment plan.',
                  style: TextStyle(color: d.text4, fontSize: 9.sp),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final s in plan.steps) _step(d, s)],
                ),
              ),
      );

  Widget _step(DentColors d, TreatmentStep s) {
    final name = s.status.name;
    final color = name == 'done'
        ? d.teal
        : (name == 'current' ? d.ice : d.text4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (s.detail.isNotEmpty)
                  Text(
                    s.detail,
                    style: TextStyle(color: d.text4, fontSize: 8.sp),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- patient details ----
  Widget _detailsCard(BuildContext context, DentColors d, Patient p) =>
      DentPanel(
        title: 'Patient Details',
        child: Column(
          children: [
            _detailRow(d, 'Phone', p.phone.isEmpty ? '—' : p.phone),
            _detailRow(d, 'Gender', p.gender.name),
            _detailRow(d, 'Age', '${p.age}'),
            _detailRow(
              d,
              'Allergies',
              (p.allergies ?? '').isEmpty ? 'None' : p.allergies!,
            ),
            _detailRow(
              d,
              'Insurance',
              (p.insurance ?? '').isEmpty ? 'None' : p.insurance!,
            ),
          ],
        ),
      );

  Widget _detailRow(DentColors d, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: d.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: d.text3, fontSize: 9.sp),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: d.text1,
            fontSize: 9.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  // ---- helpers ----
  String _prettify(String enumName) {
    final s = enumName.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return s[0].toUpperCase() + s.substring(1);
  }

  ChipKind _apptKind(AppointmentStatus s) {
    switch (s.name) {
      case 'completed':
        return ChipKind.done;
      case 'inChair':
        return ChipKind.inProgress;
      case 'waiting':
        return ChipKind.waiting;
      case 'noShow':
        return ChipKind.overdue;
      default:
        return ChipKind.upcoming;
    }
  }

  ChipKind _invKind(InvoiceStatus s) => switch (s) {
    InvoiceStatus.paid => ChipKind.done,
    InvoiceStatus.pending => ChipKind.waiting,
    InvoiceStatus.overdue => ChipKind.overdue,
  };
}

// Tap-a-tooth clinical options sheet.
void _showToothSheet(
  BuildContext context,
  WidgetRef ref,
  int patientId,
  int fdi,
  ToothRecord? rec,
) {
  const options = <(ToothState, String, String)>[
    (ToothState.healthy, 'Healthy', 'Sound tooth, no findings'),
    (ToothState.caries, 'Caries (decay)', 'Active decay present'),
    (
      ToothState.treated,
      'Filled / Restored',
      'Composite or amalgam restoration',
    ),
    (ToothState.crown, 'Crown', 'Full-coverage crown'),
    (ToothState.rootCanal, 'Root Canal (RCT)', 'Endodontically treated'),
    (ToothState.bridge, 'Bridge', 'Part of a fixed bridge'),
    (ToothState.implant, 'Implant', 'Dental implant'),
    (ToothState.missing, 'Missing / Extracted', 'Tooth absent'),
  ];
  showModalBottomSheet(
    context: context,
    backgroundColor: context.dent.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final d = ctx.dent;
      final current = rec?.state ?? ToothState.healthy;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Tooth $fdi',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 10),
                  StatusChip(
                    current.name[0].toUpperCase() + current.name.substring(1),
                    kind: ChipKind.inProgress,
                  ),
                ],
              ),
              if ((rec?.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  rec!.note!,
                  style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'SET CONDITION',
                style: TextStyle(
                  color: d.text4,
                  fontSize: 7.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 6),
              for (final (state, label, hint) in options)
                InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () {
                    ref
                        .read(patientRepositoryProvider)
                        .setToothState(patientId, fdi, state);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: state == current ? d.surface2 : null,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: state == current ? d.ice : d.line,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 9.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                hint,
                                style: TextStyle(
                                  color: d.text4,
                                  fontSize: 7.5.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (state == current)
                          Icon(
                            Icons.check_circle_rounded,
                            color: d.ice,
                            size: 12.sp,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

// Click-and-hold drag tilts the chart in perspective (the "3D feel").
class _Rotatable extends StatefulWidget {
  const _Rotatable({required this.child});
  final Widget child;
  @override
  State<_Rotatable> createState() => _RotatableState();
}

class _RotatableState extends State<_Rotatable> {
  double _rx = -0.12;
  double _ry = 0.0;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Column(
      children: [
        GestureDetector(
          onPanUpdate: (e) => setState(() {
            _ry = (_ry + e.delta.dx * 0.012).clamp(-0.7, 0.7);
            _rx = (_rx - e.delta.dy * 0.012).clamp(-0.6, 0.25);
          }),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(_rx)
              ..rotateY(_ry),
            child: widget.child,
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => setState(() {
            _rx = -0.12;
            _ry = 0.0;
          }),
          icon: Icon(
            Icons.threed_rotation_rounded,
            size: 11.sp,
            color: d.text3,
          ),
          label: Text(
            'Reset view',
            style: TextStyle(color: d.text3, fontSize: 8.sp),
          ),
        ),
      ],
    );
  }
}

class _DentalChartCard extends ConsumerStatefulWidget {
  const _DentalChartCard({
    required this.patientId,
    required this.states,
    required this.records,
  });
  final int patientId;
  final Map<int, ToothState> states;
  final Map<int, ToothRecord> records;

  @override
  ConsumerState<_DentalChartCard> createState() => _DentalChartCardState();
}

class _DentalChartCardState extends ConsumerState<_DentalChartCard> {
  int _tab = 0; // 0 = 2D chart (editable), 1 = 3D view

  @override
  Widget build(BuildContext context) {
    return DentPanel(
      title: 'Dental Chart',
      subtitle: _tab == 0
          ? 'FDI · tap a tooth to update'
          : 'Drag to rotate · view only',
      trailing: SegmentedControl(
        items: const ['Chart', '3D'],
        selected: _tab,
        onChanged: (i) => setState(() => _tab = i),
      ),
      child: _tab == 0
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Odontogram(
                states: widget.states,
                onToothTap: (fdi) => _showToothSheet(
                  context,
                  ref,
                  widget.patientId,
                  fdi,
                  widget.records[fdi],
                ),
              ),
            )
          : const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(height: 360, child: ToothModel3D()),
            ),
    );
  }
}
