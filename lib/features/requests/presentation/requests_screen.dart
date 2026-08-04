import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import '../domain/booking_request.dart';
import 'requests_controller.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});
  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  int _tab = 0; // 0 pending, 1 approved, 2 rejected
  static const _statuses = ['pending', 'approved', 'rejected'];

  static String _slotLabel(DateTime pkt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = pkt.hour == 0 ? 12 : (pkt.hour > 12 ? pkt.hour - 12 : pkt.hour);
    final ap = pkt.hour >= 12 ? 'PM' : 'AM';
    final m = pkt.minute.toString().padLeft(2, '0');
    return '${months[pkt.month - 1]} ${pkt.day}, ${pkt.year} · $h:$m $ap';
  }

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  int _daysLeft(DateTime? decidedAt) {
    if (decidedAt == null) return 30;
    final elapsed = DateTime.now().toUtc().difference(decidedAt).inDays;
    return (30 - elapsed).clamp(0, 30);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final async = ref.watch(requestsByStatusProvider(_statuses[_tab]));
    final rows = async.value ?? const <BookingRequestView>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Booking Requests',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Patient-app bookings · approve, modify, or reject.',
            style: TextStyle(color: d.text3, fontSize: 9.sp),
          ),
          SizedBox(height: 2.2.h),

          // tabs
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _tabChip(
                    d,
                    ['Pending', 'Approved', 'Rejected'][i],
                    i == _tab,
                    () => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
          SizedBox(height: 1.8.h),

          if (async.isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            _empty(d)
          else
            Column(children: [for (final r in rows) _card(context, d, r)]),
        ],
      ),
    );
  }

  Widget _tabChip(DentColors d, String label, bool active, VoidCallback onTap) {
    return Material(
      color: active ? d.ice : d.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? d.ice : d.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : d.text2,
              fontSize: 8.5.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(DentColors d) => Padding(
    padding: const EdgeInsets.all(48),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 34, color: d.text4),
          const SizedBox(height: 10),
          Text(
            'Nothing here',
            style: TextStyle(
              color: d.text3,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _card(BuildContext context, DentColors d, BookingRequestView r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: d.ice.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  size: 19,
                  color: d.ice,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.patientName,
                      style: TextStyle(
                        color: d.text1,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.sp,
                      ),
                    ),
                    Text(
                      'Requested ${_ago(r.createdAt)}',
                      style: TextStyle(color: d.text4, fontSize: 7.5.sp),
                    ),
                  ],
                ),
              ),
              _statusChip(r.status),
            ],
          ),
          const SizedBox(height: 14),
          _detail(d, Icons.medical_services_rounded, 'Procedure', r.procedure),
          _detail(d, Icons.person_rounded, 'Dentist', r.dentist),
          _detail(
            d,
            Icons.schedule_rounded,
            'Requested time',
            '${_slotLabel(r.slotPkt)}  ·  ${r.durationMin} min',
          ),

          // audit trail
          if (r.acceptedBy != null)
            _detail(d, Icons.verified_rounded, 'Approved by', r.acceptedBy!),
          if (r.status == 'rejected' && r.modifiedBy != null)
            _detail(d, Icons.block_rounded, 'Rejected by', r.modifiedBy!),
          if (r.status != 'pending')
            _detail(
              d,
              Icons.auto_delete_rounded,
              'Auto-removes',
              'in ${_daysLeft(r.decidedAt)} days',
            ),

          // actions (pending only)
          if (r.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reject(context, r),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: d.alert,
                      side: BorderSide(color: d.alert.withValues(alpha: .4)),
                      minimumSize: const Size.fromHeight(42),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => showApproveRequestDialog(context, r),
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(42),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(DentColors d, IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: d.text4),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: TextStyle(color: d.text4, fontSize: 8.sp),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 8.5.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _statusChip(String status) {
    final (label, kind) = switch (status) {
      'approved' => ('Approved', ChipKind.done),
      'rejected' => ('Rejected', ChipKind.overdue),
      _ => ('Pending', ChipKind.waiting),
    };
    return StatusChip(label, kind: kind);
  }

  Future<void> _reject(BuildContext context, BookingRequestView r) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Reject request?',
      message:
          'Reject ${r.patientName}\'s booking. This frees the slot. Stays in '
          'history for 30 days.',
      confirmLabel: 'Reject',
      cancelLabel: 'Cancel',
    );
    if (ok != true) return;
    final staff = ref.read(authControllerProvider)?.username ?? 'unknown';
    await ref
        .read(bookingRequestRepositoryProvider)
        .reject(requestId: r.id, staffUsername: staff);
  }
}
