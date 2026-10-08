import 'package:flutter/material.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';

const _mon = [
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

String _stamp(DateTime dt) {
  final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  return '${dt.day} ${_mon[dt.month - 1]} ${dt.year} · '
      '$h:${dt.minute.toString().padLeft(2, '0')} $ap';
}

String _money(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// Owner-only record of who touched this expense.
/// Names are snapshots taken at write time, so they survive a staff member
/// being removed and they transfer between machines.
Future<void> showExpenseAudit(
  BuildContext context,
  ExpenseRow e,
  String categoryName,
) => showDialog(
  context: context,
  builder: (dialogCtx) {
    final d = dialogCtx.dent;

    Widget entry(
      IconData icon,
      Color tone,
      String label,
      String who,
      DateTime? when, {
      String? extra,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tone, size: 17),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: d.text4,
                    fontSize: 7.5.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  who.isEmpty ? 'Unknown user' : who,
                  style: TextStyle(
                    color: who.isEmpty ? d.text4 : d.text1,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    fontStyle: who.isEmpty ? FontStyle.italic : null,
                  ),
                ),
                if (when != null)
                  Text(
                    _stamp(when),
                    style: AppTypography.mono(size: 8.sp, color: d.text3),
                  ),
                if (extra != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      extra,
                      style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.ice.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.history_rounded, color: d.ice, size: 19),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Record History',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: d.text1,
                          ),
                        ),
                        Text(
                          'Rs ${_money(e.amount)} · $categoryName',
                          style: TextStyle(color: d.text3, fontSize: 9.sp),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Column(
                children: [
                  entry(
                    Icons.add_circle_outline_rounded,
                    d.teal,
                    'ADDED BY',
                    e.recordedByName,
                    e.createdAt,
                  ),
                  if (e.updatedByName != null)
                    entry(
                      Icons.edit_outlined,
                      d.ice,
                      'LAST EDITED BY',
                      e.updatedByName!,
                      e.updatedAt,
                    )
                  else
                    entry(
                      Icons.edit_off_outlined,
                      d.text4,
                      'LAST EDITED BY',
                      '',
                      null,
                      extra: 'Never edited since it was added.',
                    ),
                  if (e.isDeleted)
                    entry(
                      Icons.delete_outline_rounded,
                      d.alert,
                      'DELETED BY',
                      e.deletedByName ?? '',
                      e.deletedAt,
                      extra: (e.deleteReason ?? '').isEmpty
                          ? null
                          : 'Reason: ${e.deleteReason}',
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: d.surface2,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      'Names are recorded at the time of each action and are '
                      'kept even if that staff member is later removed.',
                      style: TextStyle(
                        color: d.text4,
                        fontSize: 8.sp,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: d.text2,
                      side: BorderSide(color: d.line),
                      minimumSize: const Size.fromHeight(42),
                    ),
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  },
);
