import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';

const _shortDentist = {
  'Dr. Ayesha Khan': 'Dr. Khan',
  'Dr. Bilal Ahmed': 'Dr. Bilal',
  'Dr. Sara Malik': 'Dr. Sara',
};

Future<void> showAppointmentEditor(BuildContext context, {int? patientId}) =>
    showDialog(
      context: context,
      builder: (_) => AppointmentEditorDialog(patientId: patientId),
    );

class AppointmentEditorDialog extends ConsumerStatefulWidget {
  const AppointmentEditorDialog({super.key, this.patientId});
  final int? patientId;
  @override
  ConsumerState<AppointmentEditorDialog> createState() => _S();
}

class _S extends ConsumerState<AppointmentEditorDialog> {
  int? _patientId;
  String _procedure = kProcedures.first;
  String _dentist = kDentists.first;
  late DateTime _day;
  DateTime? _slot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _patientId = widget.patientId;
    final s = ref.read(selectedDateProvider);
    _day = DateTime(s.year, s.month, s.day);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_day.year - 1),
      lastDate: DateTime(_day.year + 2),
    );
    if (picked != null)
      setState(() {
        _day = DateTime(picked.year, picked.month, picked.day);
        _slot = null;
      });
  }

  Future<void> _confirm() async {
    if (_patientId == null || _slot == null) return;
    setState(() => _busy = true);
    await ref
        .read(appointmentRepositoryProvider)
        .book(
          patientId: _patientId!,
          dentist: _shortDentist[_dentist] ?? _dentist,
          chair: 1 + kDentists.indexOf(_dentist),
          procedure: _procedure,
          startsAt: _slot!,
          durationMin: 45,
        );
    ref.read(selectedDateProvider.notifier).state =
        _day; // jump the agenda to the booked day
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final patients = ref.watch(patientsStreamProvider).value ?? [];
    final slots = ref.watch(slotsProvider(_day)).value ?? [];
    String two(int v) => v.toString().padLeft(2, '0');
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New Appointment',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: 2.h),
                _dd<int>(
                  d,
                  'Patient',
                  patients
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.fullName,
                            style: TextStyle(fontSize: 9.sp, color: d.text1),
                          ),
                        ),
                      )
                      .toList(),
                  _patientId,
                  (v) => setState(() => _patientId = v),
                  hint: 'Select patient…',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dd<String>(
                        d,
                        'Procedure',
                        kProcedures
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: d.text1,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        _procedure,
                        (v) => setState(() => _procedure = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dd<String>(
                        d,
                        'Dentist',
                        kDentists
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: d.text1,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        _dentist,
                        (v) => setState(() => _dentist = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'DATE',
                      style: TextStyle(
                        color: d.text4,
                        fontSize: 7.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_rounded, size: 16),
                      label: Text('${_day.day}/${_day.month}/${_day.year}'),
                    ),
                  ],
                ),
                SizedBox(height: 1.4.h),
                Text(
                  'AVAILABLE SLOTS',
                  style: TextStyle(
                    color: d.text4,
                    fontSize: 7.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in slots)
                      GestureDetector(
                        onTap: s.busy
                            ? null
                            : () => setState(() => _slot = s.time),
                        child: Container(
                          width: 84,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _slot == s.time ? null : d.surface2,
                            gradient: _slot == s.time ? d.accentGradient : null,
                            borderRadius: BorderRadius.circular(9),
                            border: _slot == s.time
                                ? null
                                : Border.all(color: d.line),
                          ),
                          child: Text(
                            '${two(s.time.hour)}:${two(s.time.minute)}',
                            style:
                                AppTypography.mono(
                                  size: 8.sp,
                                  color: _slot == s.time
                                      ? AppPalette.onAccent
                                      : (s.busy ? d.text4 : d.text2),
                                ).copyWith(
                                  decoration: s.busy
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (slots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No open slots for this day.',
                      style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                    ),
                  ),
                SizedBox(height: 2.4.h),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                      ),
                      onPressed: (_busy || _patientId == null || _slot == null)
                          ? null
                          : _confirm,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppPalette.onAccent,
                              ),
                            )
                          : const Text('Confirm Booking'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dd<T>(
    DentColors d,
    String label,
    List<DropdownMenuItem<T>> items,
    T? value,
    ValueChanged<T?> onChanged, {
    String? hint,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: d.text4,
          fontSize: 7.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: d.line),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          underline: const SizedBox(),
          hint: hint == null
              ? null
              : Text(
                  hint,
                  style: TextStyle(color: d.text4, fontSize: 9.sp),
                ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}
