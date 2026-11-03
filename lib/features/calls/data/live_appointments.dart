import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:is_dental/core/constants/views.dart';

import 'patient_call.dart';

/// Appointment changes that must reach every computer at once — booked,
/// rescheduled, cancelled, Mark arrived, Complete, Undo arrival — instead
/// of on the next scheduled sync. On every cloud plan.
///
/// [push] sends one row straight away; [apply] takes a row that arrived
/// live from another computer or the owner phone. Both use exactly the
/// fields and the last-write-wins rule of SyncEngine._syncAppointments, so
/// the scheduled sync and the live path can never disagree.
class LiveAppointments {
  LiveAppointments(this._db);
  final AppDatabase _db;
  SupabaseClient get _sb => Supabase.instance.client;

  /// Sends one appointment to the cloud now. False when offline — the
  /// scheduled sync sends it later, nothing is lost.
  Future<bool> push(int appointmentId) async {
    try {
      final a = await (_db.select(
        _db.appointments,
      )..where((t) => t.id.equals(appointmentId))).getSingleOrNull();
      if (a == null) return false;
      final p = await (_db.select(
        _db.patients,
      )..where((t) => t.id.equals(a.patientId))).getSingleOrNull();
      if (p == null) return false;
      await _sb
          .from('appointments')
          .upsert({
            'uuid': a.uuid,
            'clinic_id': a.clinicId,
            'branch_id': a.branchId,
            'patient_uuid': p.uuid,
            'dentist': a.dentist,
            'chair': a.chair,
            'procedure': a.procedure,
            'billed': a.billed,
            'starts_at': a.startsAt.toUtc().toIso8601String(),
            'duration_min': a.durationMin,
            'status': a.status,
            'notes': a.notes,
            'is_deleted': a.isDeleted,
            'updated_at': a.updatedAt.toUtc().toIso8601String(),
          }, onConflict: 'uuid')
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The appointment just booked on this computer: [dentist] at
  /// [startsAt], the newest one if (after an offline clash) there are two.
  Future<int?> justBooked({
    required DateTime startsAt,
    required String dentist,
  }) async =>
      (await (_db.select(_db.appointments)
                ..where(
                  (t) =>
                      t.startsAt.equals(startsAt) &
                      t.dentist.equals(dentist) &
                      t.isDeleted.equals(false),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.id)])
                ..limit(1))
              .getSingleOrNull())
          ?.id;

  /// The local patient id of an appointment.
  Future<int?> patientOf(int appointmentId) async => (await (_db.select(
    _db.appointments,
  )..where((t) => t.id.equals(appointmentId))).getSingleOrNull())?.patientId;

  /// A row another computer (or the owner phone) just saved. Skipped when
  /// this computer's copy is as new or newer. The sync cursor is not moved,
  /// so the scheduled pull still sees the row.
  ///
  /// Returns true when a quick catch-up is worth running
  /// (SyncEngine.syncAppointmentsNow):
  ///  • the patient isn't on this computer yet (registered a moment ago on
  ///    another one) — the catch-up brings the patient, then the row;
  ///  • the appointment is new here — the catch-up brings its activity
  ///    line ("Booked from the owner phone").
  /// This computer's own changes come back as echoes that are already
  /// here, so they never start a catch-up.
  Future<bool> apply(Map<String, dynamic> r, String clinicId) async {
    try {
      if (r['clinic_id'] != clinicId) return false;
      final uuid = r['uuid'] as String?;
      final updated = DateTime.tryParse('${r['updated_at']}');
      final starts = DateTime.tryParse('${r['starts_at']}');
      if (uuid == null || updated == null || starts == null) return false;

      final pid =
          (await (_db.select(_db.patients)
                    ..where((t) => t.uuid.equals('${r['patient_uuid']}')))
                  .getSingleOrNull())
              ?.id;
      if (pid == null) return true;

      final existing = await (_db.select(
        _db.appointments,
      )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
      if (existing != null && !updated.isAfter(existing.updatedAt)) {
        return false;
      }

      await _db
          .into(_db.appointments)
          .insertOnConflictUpdate(
            AppointmentsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(uuid),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id'] as String?),
              patientId: Value(pid),
              dentist: Value('${r['dentist'] ?? ''}'),
              chair: Value((r['chair'] as num?)?.toInt() ?? 1),
              procedure: Value('${r['procedure'] ?? ''}'),
              billed: Value(r['billed'] == true),
              startsAt: Value(starts),
              durationMin: Value((r['duration_min'] as num?)?.toInt() ?? 30),
              status: Value('${r['status'] ?? 'upcoming'}'),
              notes: Value(r['notes'] as String?),
              isDeleted: Value(r['is_deleted'] == true),
              updatedAt: Value(updated),
            ),
          );
      return existing == null;
    } catch (_) {
      // a bad row must never break the live channel
      return false;
    }
  }

  /// Today's arrived patients (Mark arrived pressed, not completed),
  /// with full names — the people a doctor can call.
  Stream<List<WaitingPatient>> watchArrivals(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final a = _db.appointments;
    final q =
        _db.select(a).join([
            innerJoin(_db.patients, _db.patients.id.equalsExp(a.patientId)),
          ])
          ..where(
            a.isDeleted.equals(false) &
                a.status.isIn(const ['waiting', 'inChair']) &
                a.startsAt.isBiggerOrEqualValue(start) &
                a.startsAt.isSmallerThanValue(end),
          )
          ..orderBy([OrderingTerm.asc(a.startsAt)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          () {
            final x = r.readTable(a);
            return WaitingPatient(
              appointmentId: x.id,
              appointmentUuid: x.uuid,
              branchId: x.branchId,
              dentist: x.dentist,
              name: r.readTable(_db.patients).fullName.trim(),
              procedure: x.procedure,
              startsAt: x.startsAt.toLocal(),
            );
          }(),
      ],
    );
  }
}

final liveAppointmentsProvider = Provider(
  (ref) => LiveAppointments(ref.watch(appDatabaseProvider)),
);

/// Returns a function that sends an appointment to the cloud now, so the
/// waiting list on every computer and the reception screen changes at once.
///
/// Take it BEFORE any await (it reads providers), call it right after
/// Mark arrived / Complete / Undo arrival. Fire-and-forget: offline is
/// fine, the scheduled sync sends it later.
void Function(int appointmentId) appointmentPusher(WidgetRef ref) {
  final on = ref.read(entitlementsProvider).sync;
  final live = ref.read(liveAppointmentsProvider);
  final cloud = ref.read(cloudServiceProvider);
  return (id) {
    if (!on) return;
    Future(() async {
      try {
        await cloud.ensureSignedIn();
        await live.push(id);
      } catch (_) {}
    });
  };
}
