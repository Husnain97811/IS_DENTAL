import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../prescription_controller.dart';
import 'prescription_editor.dart';
import 'prescription_preview.dart';

class PrescriptionCard extends ConsumerWidget {
  const PrescriptionCard({
    super.key,
    required this.patientId,
    required this.patientUuid,
    required this.patientName,
    this.allergies,
  });
  final int patientId;
  final String patientUuid, patientName;
  final String? allergies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final list =
        ref.watch(patientPrescriptionsProvider(patientId)).value ??
        const <Prescription>[];

    return Container(
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d.teal.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    size: 17,
                    color: d.tealDeep,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Prescriptions',
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${list.length}',
                  style: TextStyle(color: d.text2, fontSize: 10.5.sp),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: d.ice,
                    foregroundColor: AppPalette.onAccent,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                  ),
                  onPressed: () => showPrescriptionEditor(
                    context,
                    patientId: patientId,
                    patientUuid: patientUuid,
                    patientName: patientName,
                    allergies: allergies,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text('New', style: TextStyle(fontSize: 10.sp)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No prescriptions yet.',
                style: TextStyle(color: d.text4, fontSize: 10.5.sp),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 38.h),
              child: SingleChildScrollView(
                child: Column(
                  children: [for (final p in list) _row(context, ref, d, p)],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    Prescription p,
  ) => InkWell(
    onTap: () => showPrescriptionPreview(
      context,
      rx: p,
      patientName: patientName,
      patientUuid: patientUuid,
      allergies: allergies,
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      p.rxNo,
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        color: d.text1,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _fmt(p.issuedAt),
                      style: TextStyle(color: d.text3, fontSize: 10.sp),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  p.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: d.text2, fontSize: 10.sp),
                ),
                if (p.doctorName.isNotEmpty)
                  Text(
                    p.doctorName,
                    style: TextStyle(color: d.text2, fontSize: 10.sp),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline_rounded, size: 17, color: d.text4),
            onPressed: () async {
              final ok = await showDentDialog(
                context,
                kind: DentDialogKind.warning,
                title: 'Delete prescription?',
                message: 'Remove ${p.rxNo} from this patient\'s record.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
              );
              if (ok == true) {
                await ref
                    .read(prescriptionRepositoryProvider)
                    .deletePrescription(p.id, patientId);
              }
            },
          ),
        ],
      ),
    ),
  );

  String _fmt(DateTime dt) =>
      '${dt.day} '
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]} '
      '${dt.year}';
}
