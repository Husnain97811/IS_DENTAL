import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/appointments/domain/appointment.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../patients/presentation/patients_controller.dart';
import '../../application/book_with_new_patient.dart';
import '../appointments_controller.dart';
import 'patient_picker_field.dart';

class QuickBookDrawer extends ConsumerStatefulWidget {
  const QuickBookDrawer({super.key});
  @override
  ConsumerState<QuickBookDrawer> createState() => _QuickBookDrawerState();
}

class _QuickBookDrawerState extends ConsumerState<QuickBookDrawer> {
  PatientChoice? _patientChoice;
  String _procedure = kProcedures.first;
  String? _dentist; // null until dentists load
  DateTime? _slot;
  int _durationMin = 20;
  bool _busy = false;
  int _formKey = 0;

  @override
  void initState() {
    super.initState();
    _durationMin = ref.read(clinicScheduleProvider).slotMinutes;
  }

  Future<void> _confirm(List<String> dentists) async {
    final choice = _patientChoice;
    final slot = _slot;
    final dentist = _dentist;
    if (choice == null || slot == null || dentist == null) return;

    // ── Conflict check ──
    final day = ref.read(selectedDateProvider);
    final existing =
        ref.read(appointmentsForDayFamilyProvider(day)).value ?? const [];
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
    final chair = 1 + dentists.indexOf(dentist);

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
                durationMin: _durationMin,
              );
        case NewPatientChoice(:final name):
          await ref.read(bookWithNewPatientProvider)(
            fullName: name,
            dentist: dentist,
            chair: chair,
            procedure: _procedure,
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
    setState(() {
      _busy = false;
      _slot = null;
      _patientChoice = null;
      _formKey++;
    });
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

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final patients = ref.watch(patientsStreamProvider).value ?? [];
    final day = ref.watch(selectedDateProvider);
    final slots = ref.watch(daySlotsProvider(day));
    final dentists = ref.watch(dentistsProvider).value ?? [];
    String two(int v) => v.toString().padLeft(2, '0');

    // Once dentists load, seed the selection if not yet set
    if (_dentist == null && dentists.isNotEmpty) {
      _dentist = dentists.first;
    }

    return Container(
      width: 332,
      decoration: BoxDecoration(
        color: d.surface,
        border: Border(left: BorderSide(color: d.line)),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: d.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Quick Book',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  'NEW',
                  style: TextStyle(
                    color: d.ice,
                    fontSize: 7.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),

          // ── Patient picker ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: PatientPickerField(
              key: ValueKey(_formKey),
              patients: patients,
              onChanged: (c) => setState(() => _patientChoice = c),
            ),
          ),

          // ── Procedure ──
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
                      style: TextStyle(fontSize: 9.sp, color: d.text1),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _procedure = v!),
            ),
          ),

          // ── Dentist (live from DB) ──
          _label(d, 'Dentist'),
          dentists.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'No clinicians found. Add staff in Settings.',
                    style: TextStyle(color: d.text4, fontSize: 8.5.sp),
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
                            style: TextStyle(fontSize: 9.sp, color: d.text1),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _dentist = v),
                  ),
                ),

          // ── Slots ──
          _label(d, 'Available slots — ${day.day}/${day.month}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in slots)
                  _slotChip(
                    d,
                    '${two(s.time.hour)}:${two(s.time.minute)}',
                    busy: s.busy,
                    selected: _slot == s.time,
                    onTap: s.busy ? null : () => setState(() => _slot = s.time),
                  ),
              ],
            ),
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
                for (final m in const [15, 20, 25, 30, 45, 50, 60, 90])
                  DropdownMenuItem(
                    value: m,
                    child: Text(
                      '$m min',
                      style: TextStyle(fontSize: 9.sp, color: d.text1),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _durationMin = v!),
            ),
          ),

          // ── Confirm ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: d.ice,
                foregroundColor: AppPalette.onAccent,
                minimumSize: const Size.fromHeight(42),
              ),
              onPressed:
                  (_busy ||
                      _patientChoice == null ||
                      _slot == null ||
                      _dentist == null)
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
    );
  }

  Widget _label(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 7),
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

  Widget _box(DentColors d, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: d.line),
      ),
      child: child,
    ),
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
