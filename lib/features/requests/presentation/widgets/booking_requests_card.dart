import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../../../../core/router/app_routes.dart';
import '../../domain/booking_request.dart';
import '../requests_controller.dart';

class BookingRequestsCard extends ConsumerWidget {
  const BookingRequestsCard({super.key});

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

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
    return '${months[pkt.month - 1]} ${pkt.day} · $h:$m $ap';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final async = ref.watch(pendingRequestsProvider);
    final all = async.value ?? const <BookingRequestView>[];
    final shown = all.take(3).toList();
    final extra = all.length - shown.length;

    return DentPanel(
      title: 'Booking Requests',
      subtitle: all.isEmpty
          ? 'From the patient app'
          : '${all.length} pending · from the patient app',
      trailing: PanelLink(
        'View all',
        icon: Icons.chevron_right_rounded,
        onTap: () => context.go(AppRoutes.requests),
      ),
      child: async.isLoading
          ? const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : all.isEmpty
          ? _empty(d)
          : Column(
              children: [
                for (final r in shown) _row(context, ref, d, r),
                if (extra > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '+ $extra more request${extra == 1 ? '' : 's'}',
                        style: TextStyle(color: d.text4, fontSize: 8.sp),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _empty(DentColors d) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 26, color: d.text4),
          const SizedBox(height: 8),
          Text(
            'No pending requests',
            style: TextStyle(
              color: d.text3,
              fontSize: 9.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "You're all caught up.",
            style: TextStyle(color: d.text4, fontSize: 8.sp),
          ),
        ],
      ),
    ),
  );

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    BookingRequestView r,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          // avatar
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: d.ice.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.event_available_rounded, size: 17, color: d.ice),
          ),
          const SizedBox(width: 12),
          // details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.patientName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: d.text1,
                          fontWeight: FontWeight.w600,
                          fontSize: 9.sp,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _ago(r.createdAt),
                      style: TextStyle(color: d.text4, fontSize: 7.sp),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  '${r.procedure} · ${r.dentist}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: d.text3, fontSize: 8.sp),
                ),
                Text(
                  _slotLabel(r.slotPkt),
                  style: AppTypography.mono(size: 7.5.sp, color: d.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // actions
          _miniBtn(
            d,
            Icons.check_rounded,
            d.ok,
            () => showApproveRequestDialog(context, r),
          ),
          const SizedBox(width: 6),
          _miniBtn(
            d,
            Icons.close_rounded,
            d.alert,
            () => _reject(context, ref, r),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(
    DentColors d,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    BookingRequestView r,
  ) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Reject request?',
      message:
          'Reject ${r.patientName}\'s booking for ${r.procedure}. This frees the '
          'slot. The request stays in history for 30 days.',
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
