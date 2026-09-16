import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/settings/presentation/settings_screen.dart' show syncNow;

/// Push a local change to the cloud immediately, without blocking the user.
/// Offline failures are fine — the scheduled sync catches up later.
void syncInBackground(WidgetRef ref) {
  Future(() async {
    try {
      await syncNow(ref);
    } catch (_) {}
  });
}

/// Tell the patient their appointment changed. Fire-and-forget —
/// never block the staff member on it.
void notifyAppointmentChange(
  WidgetRef ref, {
  required String appointmentUuid,
  required String type, // 'cancelled' | 'rescheduled'
}) {
  Future(() async {
    try {
      // sync first so the cloud row reflects the change before we notify
      await syncNow(ref);
      await Supabase.instance.client.functions.invoke(
        'notify-appointment-change',
        body: {'appointmentUuid': appointmentUuid, 'type': type},
      );
    } catch (_) {}
  });
}
