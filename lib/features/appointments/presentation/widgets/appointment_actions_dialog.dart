import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../../../../cloud/data/quick_sync.dart';

/// Step 1 — choose Reschedule or Cancel.
Future<void> showAppointmentActions(BuildContext context, Appointment a) =>
    showDialog(
      context: context,
      builder: (dialogCtx) => _ChooseDialog(appt: a, dialogCtx: dialogCtx),
    );

class _ChooseDialog extends ConsumerWidget {
  const _ChooseDialog({required this.appt, required this.dialogCtx});
  final Appointment appt;
  final BuildContext dialogCtx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Manage appointment',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${appt.patientName} · ${appt.procedure}',
                style: TextStyle(color: d.text3, fontSize: 10.5.sp),
              ),
              const SizedBox(height: 2),
              Text(
                _fmtFull(appt.startsAt),
                style: TextStyle(color: d.text4, fontSize: 10.sp),
              ),
              SizedBox(height: 2.4.h),

              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  showRescheduleDialog(context, appt);
                },
                icon: const Icon(Icons.event_repeat_rounded, size: 18),
                label: Text(
                  'Reschedule',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.alert,
                  side: BorderSide(color: d.alert.withValues(alpha: .5)),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  showCancelDialog(context, appt);
                },
                icon: const Icon(Icons.event_busy_rounded, size: 18),
                label: Text(
                  'Cancel appointment',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Close', style: TextStyle(fontSize: 10.5.sp)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────── CANCEL ───────────
Future<void> showCancelDialog(BuildContext context, Appointment a) =>
    showDialog(
      context: context,
      builder: (_) => _CancelDialog(appt: a),
    );

class _CancelDialog extends ConsumerStatefulWidget {
  const _CancelDialog({required this.appt});
  final Appointment appt;
  @override
  ConsumerState<_CancelDialog> createState() => _CancelState();
}

class _CancelState extends ConsumerState<_CancelDialog> {
  final _reason = TextEditingController();
  bool _notify = true;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final a = widget.appt;
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cancel appointment?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${a.patientName} · ${a.procedure}\n${_fmtFull(a.startsAt)}',
                style: TextStyle(
                  color: d.text2,
                  fontSize: 10.5.sp,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 2.h),

              Text(
                'REASON (OPTIONAL)',
                style: TextStyle(
                  color: d.text4,
                  fontSize: 8.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                height: 44,
                child: TextField(
                  controller: _reason,
                  style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: d.surface2,
                    hintText: 'Patient called to cancel…',
                    hintStyle: TextStyle(color: d.text4, fontSize: 10.5.sp),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(color: d.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(color: d.line),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              _NotifyRow(
                value: _notify,
                onChanged: (v) => setState(() => _notify = v),
                label: 'Let the patient know',
              ),

              SizedBox(height: 2.4.h),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text('Keep it', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.alert,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    onPressed: _busy ? null : _cancel,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Cancel appointment',
                            style: TextStyle(fontSize: 10.5.sp),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    final a = widget.appt;
    try {
      await ref
          .read(appointmentRepositoryProvider)
          .cancel(a.id, reason: _reason.text.trim());
      syncInBackground(ref);
      if (_notify) {
        notifyAppointmentChange(
          ref,
          appointmentUuid: a.uuid,
          type: 'cancelled',
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appointment cancelled for ${a.patientName}.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
    }
  }
}

// ─────────── RESCHEDULE ───────────
Future<void> showRescheduleDialog(BuildContext context, Appointment a) =>
    showDialog(
      context: context,
      builder: (_) => _RescheduleDialog(appt: a),
    );

class _RescheduleDialog extends ConsumerStatefulWidget {
  const _RescheduleDialog({required this.appt});
  final Appointment appt;
  @override
  ConsumerState<_RescheduleDialog> createState() => _ReState();
}

class _ReState extends ConsumerState<_RescheduleDialog> {
  late DateTime _day;
  DateTime? _slot;
  bool _notify = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.appt.startsAt;
    _day = DateTime(s.year, s.month, s.day);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final a = widget.appt;
    final slots = ref.watch(daySlotsProvider(_day));
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: 86.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Reschedule appointment',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${a.patientName} · ${a.procedure}',
                    style: TextStyle(color: d.text2, fontSize: 10.5.sp),
                  ),
                  Text(
                    'Currently ${_fmtFull(a.startsAt)}',
                    style: TextStyle(color: d.text4, fontSize: 10.sp),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'NEW DATE',
                      style: TextStyle(
                        color: d.text4,
                        fontSize: 8.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _day.isBefore(todayMidnight)
                              ? todayMidnight
                              : _day,
                          firstDate: todayMidnight, // ← past dates blocked
                          lastDate: todayMidnight.add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            _day = picked;
                            _slot = null;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: d.surface2,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: d.line),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_rounded, size: 16, color: d.text3),
                            const SizedBox(width: 10),
                            Text(
                              _fmtDay(_day),
                              style: TextStyle(
                                fontSize: 10.5.sp,
                                color: d.text1,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                              color: d.text3,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text(
                      'AVAILABLE SLOTS',
                      style: TextStyle(
                        color: d.text4,
                        fontSize: 8.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (slots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'The clinic is closed on this day.',
                          style: TextStyle(color: d.text4, fontSize: 10.5.sp),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in slots) _slotChip(d, s.time, s.busy),
                        ],
                      ),

                    const SizedBox(height: 16),
                    _NotifyRow(
                      value: _notify,
                      onChanged: (v) => setState(() => _notify = v),
                      label: 'Let the patient know',
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _slot == null ? d.line : d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    onPressed: (_busy || _slot == null) ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Move appointment',
                            style: TextStyle(fontSize: 10.5.sp),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotChip(DentColors d, DateTime t, bool busy) {
    // the appointment's own current slot shouldn't read as busy
    final isOwn = t.isAtSameMomentAs(widget.appt.startsAt);
    final blocked = busy && !isOwn;
    final selected = _slot != null && _slot!.isAtSameMomentAs(t);
    return GestureDetector(
      onTap: blocked ? null : () => setState(() => _slot = t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? d.ice
              : blocked
              ? d.surface2
              : d.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? d.ice : d.line),
        ),
        child: Text(
          _fmtTime(t),
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 10.sp,
            color: selected
                ? AppPalette.onAccent
                : blocked
                ? d.text4
                : d.text1,
            decoration: blocked ? TextDecoration.lineThrough : null,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final a = widget.appt;
    try {
      await ref
          .read(appointmentRepositoryProvider)
          .reschedule(id: a.id, startsAt: _slot!);
      syncInBackground(ref);
      if (_notify) {
        notifyAppointmentChange(
          ref,
          appointmentUuid: a.uuid,
          type: 'rescheduled',
        );
      }
      if (!mounted) return;
      Navigator.pop(context);

      // follow the appointment to its new date
      final newDay = DateTime(_slot!.year, _slot!.month, _slot!.day);
      ref.read(selectedDateProvider.notifier).state = newDay;
      ref.read(viewedMonthProvider.notifier).state = (
        year: newDay.year,
        month: newDay.month,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${_fmtFull(_slot!)} — showing that day.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reschedule: $e')));
    }
  }
}

// ─────────── shared bits ───────────
class _NotifyRow extends StatelessWidget {
  const _NotifyRow({
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: d.line),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded, size: 16, color: d.text3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    color: d.text1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Sends an app notification, and WhatsApp if enabled',
                  style: TextStyle(fontSize: 9.sp, color: d.text4),
                ),
              ],
            ),
          ),
          Switch(value: value, activeColor: d.ice, onChanged: onChanged),
        ],
      ),
    );
  }
}

String _fmtTime(DateTime t) {
  final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}

String _fmtDay(DateTime d) =>
    '${d.day} '
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} '
    '${d.year}';
String _fmtFull(DateTime d) => '${_fmtDay(d)} · ${_fmtTime(d)}';
