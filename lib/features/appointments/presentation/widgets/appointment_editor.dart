import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../patients/domain/patient.dart';
import '../../../patients/presentation/patients_controller.dart';
import '../../application/book_with_new_patient.dart';
import '../appointments_controller.dart';
import 'patient_picker_field.dart';

Future<void> showAppointmentEditor(BuildContext context, {int? patientId}) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: _AppointmentEditor(patientId: patientId),
    ),
  );
}

class _AppointmentEditor extends ConsumerStatefulWidget {
  const _AppointmentEditor({this.patientId});
  final int? patientId;
  @override
  ConsumerState<_AppointmentEditor> createState() => _AppointmentEditorState();
}

class _AppointmentEditorState extends ConsumerState<_AppointmentEditor> {
  PatientChoice? _patient;
  String _procedure = kProcedures.first;
  String _dentist = kDentists.first;
  late DateTime _date;
  DateTime? _slot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = ref.read(selectedDateProvider);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
        _slot = null;
      });
    }
  }

  Future<void> _confirm() async {
    final choice = _patient;
    final slot = _slot;
    if (choice == null || slot == null) return;

    setState(() => _busy = true);
    final dentist = _dentist
        .replaceFirst('Dr. Ayesha', 'Dr.')
        .replaceFirst('Dr. Bilal Ahmed', 'Dr. Bilal')
        .replaceFirst('Dr. Sara Malik', 'Dr. Sara');
    final chair = 1 + kDentists.indexOf(_dentist);

    try {
      switch (choice) {
        case ExistingPatientChoice(:final patient):
          await ref
              .read(appointmentRepositoryProvider)
              .book(
                patientId: patient.id,
                dentist: dentist,
                chair: chair,
                procedure: _procedure,
                startsAt: slot,
                durationMin: 45,
              );
        case NewPatientChoice(:final name):
          await ref.read(bookWithNewPatientProvider)(
            fullName: name,
            dentist: dentist,
            chair: chair,
            procedure: _procedure,
            startsAt: slot,
            durationMin: 45,
          );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not book: $e')));
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice is NewPatientChoice
              ? 'Patient created & appointment booked.'
              : 'Appointment booked.',
        ),
      ),
    );
  }

  Patient? _initialPatient(List<Patient> patients) {
    if (widget.patientId == null) return null;
    for (final p in patients) {
      if (p.id == widget.patientId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final patients =
        ref.watch(patientsStreamProvider).value ?? const <Patient>[];
    final slots = ref.watch(slotsProvider(_date)).value ?? const [];
    String two(int v) => v.toString().padLeft(2, '0');
    final initialPatient = _initialPatient(patients);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'New Appointment',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 12.sp,
                      color: d.text3,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PatientPickerField(
                      key: ValueKey(initialPatient?.id),
                      initial: initialPatient,
                      patients: patients,
                      onChanged: (c) => setState(() => _patient = c),
                    ),
                    _label(d, 'Procedure'),
                    _box(
                      d,
                      DropdownButton<String>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: _procedure,
                        items: [
                          for (final p in kProcedures)
                            DropdownMenuItem(
                              value: p,
                              child: Text(
                                p,
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  color: d.text1,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _procedure = v!),
                      ),
                    ),
                    _label(d, 'Dentist'),
                    _box(
                      d,
                      DropdownButton<String>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: _dentist,
                        items: [
                          for (final p in kDentists)
                            DropdownMenuItem(
                              value: p,
                              child: Text(
                                p,
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  color: d.text1,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _dentist = v!),
                      ),
                    ),
                    _label(d, 'Date'),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: d.surface2,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: d.line),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 10.sp,
                              color: d.text3,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_date.day}/${_date.month}/${_date.year}',
                              style: TextStyle(fontSize: 9.sp, color: d.text1),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 11.sp,
                              color: d.text4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _label(d, 'Available slots'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in slots)
                          _slotChip(
                            d,
                            '${two(s.time.hour)}:${two(s.time.minute)}',
                            busy: s.busy,
                            selected: _slot == s.time,
                            onTap: s.busy
                                ? null
                                : () => setState(() => _slot = s.time),
                          ),
                        if (slots.isEmpty)
                          Text(
                            'No slots for this day.',
                            style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: (_busy || _patient == null || _slot == null)
                    ? null
                    : _confirm,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 17),
                label: const Text('Confirm Booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 7),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        color: d.text4,
        fontSize: 7.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  Widget _box(DentColors d, Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: d.line),
    ),
    child: child,
  );

  Widget _slotChip(
    DentColors d,
    String label, {
    required bool busy,
    required bool selected,
    VoidCallback? onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 84,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? null : d.surface2,
        gradient: selected ? d.accentGradient : null,
        borderRadius: BorderRadius.circular(9),
        border: selected ? null : Border.all(color: d.line),
      ),
      child: Text(
        label,
        style: AppTypography.mono(
          size: 8.sp,
          color: selected ? AppPalette.onAccent : (busy ? d.text4 : d.text2),
          weight: selected ? FontWeight.w600 : FontWeight.w500,
        ).copyWith(decoration: busy ? TextDecoration.lineThrough : null),
      ),
    ),
  );
}
