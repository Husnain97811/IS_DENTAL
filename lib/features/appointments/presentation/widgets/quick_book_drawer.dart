import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String _dentist = kDentists.first;
  DateTime? _slot;
  bool _busy = false;
  int _formKey = 0; // bump to reset the picker after a successful booking

  Future<void> _confirm() async {
    final choice = _patientChoice;
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
    setState(() {
      _busy = false;
      _slot = null;
      _patientChoice = null;
      _formKey++; // clears the picker's text
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
    final slots = ref.watch(slotsProvider(day)).value ?? [];
    String two(int v) => v.toString().padLeft(2, '0');

    return Container(
      width: 332,
      decoration: BoxDecoration(
        color: d.surface,
        border: Border(left: BorderSide(color: d.line)),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
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

          // live-search patient picker (existing or create-new)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: PatientPickerField(
              key: ValueKey(_formKey),
              patients: patients,
              onChanged: (c) => setState(() => _patientChoice = c),
            ),
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
                      style: TextStyle(fontSize: 9.sp, color: d.text1),
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
                      style: TextStyle(fontSize: 9.sp, color: d.text1),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _dentist = v!),
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: d.ice,
                foregroundColor: AppPalette.onAccent,
                minimumSize: const Size.fromHeight(42),
              ),
              onPressed: (_busy || _patientChoice == null || _slot == null)
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
