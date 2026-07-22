import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/appointments/domain/appointment.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../patients/domain/patient.dart';
import '../../../patients/presentation/patients_controller.dart';
import '../../../treatments/presentation/treatments_controller.dart';
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
  String? _procedure; // null until catalog loads
  String? _dentist; // null until dentists load from DB
  late DateTime _date;
  DateTime? _slot;
  int _durationMin = 20;
  bool _customTime = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = ref.read(selectedDateProvider);
    _durationMin = ref.read(clinicScheduleProvider).slotMinutes;
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

  Future<void> _pickCustomTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _slot != null
          ? TimeOfDay.fromDateTime(_slot!)
          : ref.read(clinicScheduleProvider).start,
    );
    if (t == null) return;
    setState(() {
      _slot = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
      _customTime = true;
    });
  }

  Future<void> _confirm(List<String> dentists) async {
    final choice = _patient;
    final slot = _slot;
    final dentist = _dentist;
    final procedure = _procedure;
    if (choice == null ||
        slot == null ||
        dentist == null ||
        procedure == null) {
      return;
    }

    // Conflict check
    final existing =
        ref.read(appointmentsForDayFamilyProvider(_date)).value ?? const [];
    final newEnd = slot.add(Duration(minutes: _durationMin));
    Appointment? conflict;
    for (final a in existing) {
      final aEnd = a.startsAt.add(Duration(minutes: a.durationMin));
      if (rangesOverlap(slot, newEnd, a.startsAt, aEnd)) {
        conflict = a;
        break;
      }
    }
    if (conflict != null) {
      final cEnd = conflict.startsAt.add(
        Duration(minutes: conflict.durationMin),
      );
      String hm(DateTime t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This time is already booked '
            '(${hm(conflict.startsAt)}–${hm(cEnd)}). Choose another time.',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);

    // chair = 1-based index in live dentists list; clamp to 1 if not found
    final idx = dentists.indexOf(dentist);
    final int chair = idx < 0 ? 1 : idx + 1;

    try {
      switch (choice) {
        case ExistingPatientChoice(:final patient):
          await ref
              .read(appointmentRepositoryProvider)
              .book(
                patientId: patient.id,
                dentist: dentist,
                chair: chair,
                procedure: procedure,
                startsAt: slot,
                durationMin: _durationMin,
              );
        case NewPatientChoice(:final name):
          await ref.read(bookWithNewPatientProvider)(
            fullName: name,
            dentist: dentist,
            chair: chair,
            procedure: procedure,
            startsAt: slot,
            durationMin: _durationMin,
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
    final slots = ref.watch(daySlotsProvider(_date));
    final dentists = ref.watch(dentistsProvider).value ?? [];
    final procedures = ref.watch(proceduresProvider);
    String two(int v) => v.toString().padLeft(2, '0');
    final initialPatient = _initialPatient(patients);

    // seed/reset procedure from catalog
    if (procedures.isEmpty) {
      _procedure = null;
    } else if (_procedure == null || !procedures.contains(_procedure)) {
      _procedure = procedures.first;
    }

    // seed/reset dentist (handles branch switch)
    if (dentists.isEmpty) {
      _dentist = null;
    } else if (_dentist == null || !dentists.contains(_dentist)) {
      _dentist = dentists.first;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 60.w, maxHeight: 80.h),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
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
                    // ── Patient ──
                    PatientPickerField(
                      key: ValueKey(initialPatient?.id),
                      initial: initialPatient,
                      patients: patients,
                      onChanged: (c) => setState(() => _patient = c),
                    ),

                    // ── Procedure (live from catalog) ──
                    _label(d, 'Procedure'),
                    procedures.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No procedures yet. Add them in Treatments.',
                              style: TextStyle(
                                color: d.text4,
                                fontSize: 8.5.sp,
                              ),
                            ),
                          )
                        : _box(
                            d,
                            DropdownButton<String>(
                              isExpanded: true,
                              underline: const SizedBox(),
                              value: _procedure,
                              items: [
                                for (final p in procedures)
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
                              onChanged: (v) => setState(() => _procedure = v),
                            ),
                          ),

                    // ── Dentist (live from DB) ──
                    _label(d, 'Dentist'),
                    dentists.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No clinicians found. Add staff in Settings.',
                              style: TextStyle(
                                color: d.text4,
                                fontSize: 8.5.sp,
                              ),
                            ),
                          )
                        : _box(
                            d,
                            DropdownButton<String>(
                              isExpanded: true,
                              underline: const SizedBox(),
                              value: _dentist,
                              items: [
                                for (final name in dentists)
                                  DropdownMenuItem(
                                    value: name,
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 9.sp,
                                        color: d.text1,
                                      ),
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _dentist = v),
                            ),
                          ),

                    // ── Date ──
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

                    // ── Slots ──
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
                                : () => setState(() {
                                    _slot = s.time;
                                    _customTime = false;
                                  }),
                          ),
                        if (slots.isEmpty)
                          Text(
                            'No slots for this day.',
                            style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                          ),
                      ],
                    ),

                    // ── Duration ──
                    _label(d, 'Duration (min)'),
                    _box(
                      d,
                      DropdownButton<int>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: _durationMin,
                        items: [
                          for (final m in const [
                            15,
                            20,
                            25,
                            30,
                            45,
                            50,
                            60,
                            90,
                          ])
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                '$m min',
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  color: d.text1,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _durationMin = v!),
                      ),
                    ),

                    // ── Custom time ──
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickCustomTime,
                      icon: Icon(Icons.more_time_rounded, size: 11.sp),
                      label: Text(
                        _customTime && _slot != null
                            ? 'Custom: ${_slot!.hour.toString().padLeft(2, '0')}:${_slot!.minute.toString().padLeft(2, '0')}'
                            : 'Set custom time',
                        style: TextStyle(fontSize: 8.5.sp),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Confirm ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed:
                    (_busy ||
                        _patient == null ||
                        _slot == null ||
                        _dentist == null ||
                        _procedure == null)
                    ? null
                    : () => _confirm(dentists),
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
