import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/views.dart';
import '../../core/widgets/offline_flash.dart';
import '../../features/calls/data/call_board.dart';
import '../../features/calls/data/live_appointments.dart';
import 'sync_engine.dart';

/// Everything a full sync needs, read NOW — while the screen that asked
/// is still open. A dialog usually closes right after saving, and a closed
/// screen's `ref` can't be used any more; reading it after the first
/// `await` would quietly stop the sync half-way.
Future<void> Function() _fullSync(WidgetRef ref) {
  final cloud = ref.read(cloudServiceProvider);
  final db = ref.read(appDatabaseProvider);
  final engine = ref.read(syncEngineProvider);
  return () async {
    debugPrint('SYNC: signing in…');
    await cloud.ensureSignedIn();
    final clinicId = await db.currentClinicId();
    if (clinicId == null) return;
    debugPrint('SYNC: start for $clinicId');
    await engine.syncAll(clinicId);
    await db.recordSyncNow();
    debugPrint('SYNC: done');
  };
}

/// Push a local change to the cloud immediately, without blocking the user.
/// Offline failures are fine — the scheduled sync catches up later.
void syncInBackground(WidgetRef ref) {
  final run = _fullSync(ref);
  Future(() async {
    try {
      await run();
    } catch (e) {
      debugPrint('SYNC: FAILED $e');
    }
  });
}

/// Sends ONE appointment to the cloud right now — after a booking, a
/// reschedule or a cancel on this computer — so the other computers, the
/// owner phone and the patient app see it within seconds instead of after
/// the next sync. A patient registered a moment ago goes up first.
///
/// Every cloud plan: Basic, Standard and Premium, with or without
/// reception. Never blocks — the change is already saved on this computer.
/// With no internet a big red badge shows for 2 seconds, and the change
/// goes up by itself when the internet is back.
///
/// Call it BEFORE closing the dialog, with [appointmentId], or with
/// [bookedAt] + [dentist] for a booking just made. Completes with true once
/// the cloud has it; it never throws.
Future<bool> sendAppointmentNow(
  WidgetRef ref,
  BuildContext context, {
  int? appointmentId,
  DateTime? bookedAt,
  String? dentist,
}) {
  // an offline licence has no cloud at all — nothing to send, no badge
  if (!ref.read(entitlementsProvider).sync) return Future.value(false);

  // read everything now, while the dialog is still open
  final db = ref.read(appDatabaseProvider);
  final cloud = ref.read(cloudServiceProvider);
  final engine = ref.read(syncEngineProvider);
  final live = ref.read(liveAppointmentsProvider);
  final looksOffline = !ref.read(callBoardProvider).reachable;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);

  var shown = false;
  void flash() {
    if (shown || overlay == null) return;
    shown = true;
    showOfflineFlash(overlay);
  }

  // The last internet check already failed: show the badge straight away
  // instead of waiting for a timeout — unless the send gets through first.
  final early = looksOffline
      ? Timer(const Duration(milliseconds: 1200), flash)
      : null;

  return () async {
    var sent = false;
    var tried = false;
    try {
      await cloud.ensureSignedIn().timeout(const Duration(seconds: 8));
      final clinicId = await db.currentClinicId();
      final id =
          appointmentId ??
          (bookedAt == null || dentist == null
              ? null
              : await live.justBooked(startsAt: bookedAt, dentist: dentist));
      if (clinicId != null && id != null) {
        tried = true;
        // a walk-in registered a moment ago: the patient goes first
        final patientId = await live.patientOf(id);
        if (patientId != null) {
          await engine.ensurePatientInCloud(patientId, clinicId);
        }
        sent = await live.push(id);
      }
    } catch (e) {
      tried = true;
      debugPrint('SYNC: appointment not sent now ($e)');
    }
    early?.cancel();
    if (sent) {
      debugPrint('SYNC: appointment sent now');
    } else if (tried) {
      flash();
    }
    return sent;
  }();
}

/// Tell the patient their appointment changed. Fire-and-forget —
/// never block the staff member on it.
///
/// [after] = the [sendAppointmentNow] of this change: once it's in the
/// cloud the message goes out at once. Without it (or when that send
/// failed) a full sync runs first, as before.
void notifyAppointmentChange(
  WidgetRef ref, {
  required String appointmentUuid,
  required String type, // 'cancelled' | 'rescheduled'
  Future<bool>? after,
}) {
  final sync = _fullSync(ref);
  Future(() async {
    try {
      // the cloud row must show the change before the patient is told
      final sent = after != null && await after;
      if (!sent) {
        try {
          await sync();
        } catch (_) {}
      }
      await Supabase.instance.client.functions.invoke(
        'notify-appointment-change',
        body: {'appointmentUuid': appointmentUuid, 'type': type},
      );
    } catch (_) {}
  });
}
