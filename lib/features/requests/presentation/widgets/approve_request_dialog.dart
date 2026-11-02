import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../requests_controller.dart';

Future<void> showApproveRequestDialog(
  BuildContext context,
  BookingRequestView request,
) => showDialog(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: _ApproveRequestDialog(request: request),
  ),
);

class _ApproveRequestDialog extends ConsumerStatefulWidget {
  const _ApproveRequestDialog({required this.request});
  final BookingRequestView request;
  @override
  ConsumerState<_ApproveRequestDialog> createState() => _S();
}

class _S extends ConsumerState<_ApproveRequestDialog> {
  late DateTime _date; // PKT date
  late TimeOfDay _time; // PKT time
  late int _durationMin;
  bool _busy = false;
  String? _error;
  int? _patientId; // local id, for the "same patient" check

  BookingRequestView get req => widget.request;

  @override
  void initState() {
    super.initState();
    // seed from the request (already PKT in the view model)
    _date = DateTime(req.slotPkt.year, req.slotPkt.month, req.slotPkt.day);
    _time = TimeOfDay(hour: req.slotPkt.hour, minute: req.slotPkt.minute);
    _durationMin = req.durationMin;
    ref
        .read(bookingRequestRepositoryProvider)
        .localPatientId(req.patientUuid)
        .then((id) {
          if (mounted) setState(() => _patientId = id);
        });
  }

  DateTime get _slot =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  bool get _modified => _slot != req.slotPkt || _durationMin != req.durationMin;

  /// Only the SAME doctor, or the SAME patient, at an overlapping time —
  /// other doctors' patients at that time are fine.
  ({Appointment appt, bool sameDoctor})? _clash(List<Appointment> day) =>
      findBookingClash(
        day,
        start: _slot,
        durationMin: _durationMin,
        dentist: req.dentist,
        patientId: _patientId,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _approve() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(bookingRequestRepositoryProvider);
    final patientId = await repo.localPatientId(req.patientUuid);
    if (patientId == null) {
      setState(() {
        _busy = false;
        _error = 'This patient is not synced to this device yet. Sync first.';
      });
      return;
    }

    // Last check right before booking — another computer may have just
    // booked this doctor at the same time.
    final day =
        ref.read(allAppointmentsForDayProvider(_date)).value ?? const [];
    final clash = findBookingClash(
      day,
      start: _slot,
      durationMin: _durationMin,
      dentist: req.dentist,
      patientId: patientId,
    );
    if (clash != null) {
      setState(() {
        _busy = false;
        _error = clashMessage(clash);
      });
      return;
    }

    final staff = ref.read(authControllerProvider)?.username ?? 'unknown';

    try {
      final ok = await repo.approve(
        requestId: req.id,
        patientId: patientId,
        dentist: req.dentist,
        chair: 1,
        procedure: req.procedure,
        finalSlotUtc: _slot,
        durationMin: _durationMin,
        staffUsername: staff,
        wasModified: _modified,
      );
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'No internet connection. Connect and try again.';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not approve: $e';
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    await showDentDialog(
      context,
      kind: DentDialogKind.success,
      title: 'Appointment Confirmed',
      message:
          '${req.patientName}\'s appointment is booked'
          '${_modified ? ' (time adjusted)' : ''}. '
          'They\'ll see it in the app on next refresh.',
      confirmLabel: 'Done',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    String two(int v) => v.toString().padLeft(2, '0');

    // live: tells staff about a clash as soon as they pick a time
    final dayAppts =
        ref.watch(allAppointmentsForDayProvider(_date)).value ?? const [];
    final clash = _clash(dayAppts);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 52.w),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Approve Request',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'BlackOpsOne',
                        fontSize: 13.sp,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 12.sp,
                      color: d.text3,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // patient (locked)
                  _locked(d, 'Patient', req.patientName),
                  const SizedBox(height: 12),
                  _locked(d, 'Procedure', req.procedure),
                  const SizedBox(height: 12),
                  _locked(d, 'Dentist', req.dentist),
                  const SizedBox(height: 16),

                  // date + time (editable)
                  Row(
                    children: [
                      Expanded(
                        child: _editable(
                          d,
                          'Date',
                          Icons.calendar_today_rounded,
                          '${_date.day}/${_date.month}/${_date.year}',
                          _pickDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _editable(
                          d,
                          'Time (PKT)',
                          Icons.schedule_rounded,
                          '${two(_time.hour)}:${two(_time.minute)}',
                          _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // duration
                  Text(
                    'DURATION (MIN)',
                    style: TextStyle(
                      color: d.text4,
                      fontSize: 9.sp,
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
                    child: DropdownButton<int>(
                      isExpanded: true,
                      underline: const SizedBox(),
                      value: _durationMin,
                      items: [
                        for (final m in const [15, 20, 25, 30, 45, 50, 60, 90])
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              '$m min',
                              style: TextStyle(fontSize: 11.sp, color: d.text1),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _durationMin = v!),
                    ),
                  ),

                  if (clash != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.event_busy_rounded,
                            size: 16,
                            color: d.alert,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${clashMessage(clash)} Change the date or time '
                              'to approve.',
                              style: TextStyle(
                                color: d.alert,
                                fontSize: 9.5.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_modified)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: d.ice,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Time changed from the patient\'s request — '
                              'they\'ll see the confirmed time in the app.',
                              style: TextStyle(color: d.text3, fontSize: 9.sp),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: d.alert, fontSize: 9.5.sp),
                      ),
                    ),
                ],
              ),
            ),

            // confirm
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: _busy || clash != null ? null : _approve,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _modified ? 'Confirm (modified)' : 'Confirm & Book',
                  style: TextStyle(fontSize: 10.5.sp),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locked(DentColors d, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: d.text4,
          fontSize: 9.5.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        height: 42,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: d.line),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: d.text4),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.sp, color: d.text1),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _editable(
    DentColors d,
    String label,
    IconData icon,
    String value,
    VoidCallback onTap,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: d.text4,
          fontSize: 9.5.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
      const SizedBox(height: 6),
      InkWell(
        onTap: onTap,
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
              Icon(icon, size: 13, color: d.text3),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(fontSize: 11.sp, color: d.text1),
              ),
              const Spacer(),
              Icon(Icons.edit_rounded, size: 12, color: d.text4),
            ],
          ),
        ),
      ),
    ],
  );
}
