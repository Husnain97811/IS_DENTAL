import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/utils/qr_payload.dart';
import '../../domain/patient.dart';

Future<void> showPatientQrDialog(BuildContext context, Patient patient) =>
    showDialog(
      context: context,
      builder: (_) => PatientQrDialog(patient: patient),
    );

class PatientQrDialog extends ConsumerStatefulWidget {
  const PatientQrDialog({super.key, required this.patient});
  final Patient patient;
  @override
  ConsumerState<PatientQrDialog> createState() => _S();
}

class _S extends ConsumerState<PatientQrDialog> {
  // Memoized so FutureBuilder doesn't re-fire on rebuild.
  late final Future<String?> _clinicId = ref
      .read(appDatabaseProvider)
      .currentClinicId();

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final p = widget.patient;
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: FutureBuilder<String?>(
          future: _clinicId,
          builder: (context, snap) {
            final clinicId = snap.data;
            final loading = snap.connectionState == ConnectionState.waiting;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Patient QR',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: d.text3,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.fullName,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '#${p.code}',
                    style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                  ),
                  const SizedBox(height: 18),
                  if (loading)
                    const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (clinicId == null || clinicId.isEmpty)
                    SizedBox(
                      height: 240,
                      child: Center(
                        child: Text(
                          'Clinic not set up.',
                          style: TextStyle(color: d.alert),
                        ),
                      ),
                    )
                  else ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: QrImageView(
                          data: buildPatientQrPayload(
                            clinicId: clinicId,
                            patientUuid: p.uuid,
                          ),
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scan in the DentOS patient app to link this patient.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
