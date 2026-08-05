import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/booking_request.dart';

class BookingRequestRepository {
  BookingRequestRepository(this._db);
  final AppDatabase _db;

  /// PKT = UTC + 5. Stored slot is UTC; this is the real booked Pakistan time.
  static DateTime _toPkt(DateTime utc) =>
      utc.toUtc().add(const Duration(hours: 5));

  SupabaseClient get _sb => Supabase.instance.client;

  /// Lightweight reachability check — pings Supabase.
  Future<bool> _online() async {
    try {
      await _sb
          .from('clinics')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pushes a single request row to Supabase immediately (no full sync).
  Future<void> _pushOne(int id) async {
    final r = await (_db.select(
      _db.bookingRequests,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return;
    await _sb.from('booking_requests').upsert({
      'id': r.uuid,
      'clinic_id': r.clinicId,
      'branch_id': r.branchId,
      'patient_uuid': r.patientUuid,
      'patient_account_id': r.patientAccountId,
      'dentist': r.dentist,
      'procedure': r.procedure,
      'requested_slot': r.requestedSlot.toUtc().toIso8601String(),
      'duration_min': r.durationMin,
      'status': r.status,
      'modified_by': r.modifiedBy,
      'accepted_by': r.acceptedBy,
      'decided_at': r.decidedAt?.toUtc().toIso8601String(),
      'updated_at': r.updatedAt.toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Resolve a local patient id → their uuid (appointments push by patient_uuid).
  Future<String?> _patientUuidOf(int patientId) async => (await (_db.select(
    _db.patients,
  )..where((t) => t.id.equals(patientId))).getSingleOrNull())?.uuid;

  /// Push a single appointment to Supabase immediately (no full sync), so the
  /// mobile app's available-slots sees it as busy right away.
  Future<void> _pushOneAppointment(String appointmentUuid) async {
    final a = await (_db.select(
      _db.appointments,
    )..where((t) => t.uuid.equals(appointmentUuid))).getSingleOrNull();
    if (a == null) return;
    final pu = await _patientUuidOf(a.patientId);
    if (pu == null) return; // patient not resolvable; full sync will catch it
    await _sb.from('appointments').upsert({
      'uuid': a.uuid,
      'clinic_id': a.clinicId,
      'branch_id': a.branchId,
      'patient_uuid': pu,
      'dentist': a.dentist,
      'chair': a.chair,
      'procedure': a.procedure,
      'starts_at': a.startsAt.toUtc().toIso8601String(),
      'duration_min': a.durationMin,
      'status': a.status,
      'notes': a.notes,
      'is_deleted': a.isDeleted,
      'updated_at': a.updatedAt.toUtc().toIso8601String(),
    }, onConflict: 'uuid');
  }

  /// Live stream of requests for a status, branch-filtered, with patient names
  /// resolved via a join to patients (by uuid).
  Stream<List<BookingRequestView>> watch({
    required String status,
    String? branchId,
  }) {
    final q =
        _db.select(_db.bookingRequests).join([
            leftOuterJoin(
              _db.patients,
              _db.patients.uuid.equalsExp(_db.bookingRequests.patientUuid),
            ),
          ])
          ..where(
            _db.bookingRequests.isDeleted.equals(false) &
                _db.bookingRequests.status.equals(status) &
                (branchId == null
                    ? const Constant(true)
                    : _db.bookingRequests.branchId.equals(branchId)),
          )
          ..orderBy([OrderingTerm.desc(_db.bookingRequests.createdAt)]);
    return q.watch().map(
      (rows) => rows.map((r) {
        final b = r.readTable(_db.bookingRequests);
        final p = r.readTableOrNull(_db.patients);
        return BookingRequestView(
          id: b.id,
          uuid: b.uuid,
          branchId: b.branchId,
          patientUuid: b.patientUuid,
          patientName: p?.fullName ?? 'Unknown patient',
          dentist: b.dentist,
          procedure: b.procedure,
          slotPkt: _toPkt(b.requestedSlot),
          durationMin: b.durationMin,
          status: b.status,
          modifiedBy: b.modifiedBy,
          acceptedBy: b.acceptedBy,
          decidedAt: b.decidedAt,
          createdAt: b.createdAt,
        );
      }).toList(),
    );
  }

  Stream<int> watchPendingCount({String? branchId}) {
    final c = _db.bookingRequests.id.count();
    final q = _db.selectOnly(_db.bookingRequests)
      ..addColumns([c])
      ..where(
        _db.bookingRequests.isDeleted.equals(false) &
            _db.bookingRequests.status.equals('pending') &
            (branchId == null
                ? const Constant(true)
                : _db.bookingRequests.branchId.equals(branchId)),
      );
    return q.map((row) => row.read(c) ?? 0).watchSingle();
  }

  /// Approve: books a REAL appointment at [finalSlotUtc] (staff may have changed
  /// time/duration), then flips the request to approved. Guarded — only acts if
  /// the request is still pending. Stamps audit fields.
  /// [finalSlotUtc] must be UTC (the dialog converts the picked PKT time back).
  /// Returns true on success, false if offline (nothing changed).
  Future<bool> approve({
    required int requestId,
    required int patientId,
    required String dentist,
    required int chair,
    required String procedure,
    required DateTime finalSlotUtc,
    required int durationMin,
    required String staffUsername,
    required bool wasModified,
  }) async {
    if (!await _online()) return false;

    final apptUuid = Uuids.v4(); // ← known uuid so we can push it after

    await _db.transaction(() async {
      final req = await (_db.select(
        _db.bookingRequests,
      )..where((t) => t.id.equals(requestId))).getSingleOrNull();
      if (req == null || req.status != 'pending') return; // stale guard

      final clinicId = await _db.currentClinicId() ?? '';
      await _db
          .into(_db.appointments)
          .insert(
            AppointmentsCompanion.insert(
              uuid: apptUuid,
              clinicId: clinicId,
              branchId: Value(req.branchId),
              patientId: patientId,
              dentist: dentist,
              chair: Value(chair),
              procedure: procedure,
              startsAt: finalSlotUtc,
              durationMin: Value(durationMin),
              status: const Value('upcoming'),
            ),
          );

      await (_db.update(
        _db.bookingRequests,
      )..where((t) => t.id.equals(requestId))).write(
        BookingRequestsCompanion(
          status: const Value('approved'),
          acceptedBy: Value(staffUsername),
          modifiedBy: wasModified ? Value(staffUsername) : const Value.absent(),
          decidedAt: Value(DateTime.now().toUtc()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });

    await _pushOne(requestId); // pushes the approved request
    await _pushOneAppointment(apptUuid); // pushes the new appointment NOW
    return true;
  }

  /// Reject: frees the slot (status != pending) and timestamps for 30-day purge.
  /// Guarded to pending only.
  /// Returns true on success, false if offline.
  Future<bool> reject({
    required int requestId,
    required String staffUsername,
  }) async {
    if (!await _online()) return false;

    final req = await (_db.select(
      _db.bookingRequests,
    )..where((t) => t.id.equals(requestId))).getSingleOrNull();
    if (req == null || req.status != 'pending') return false;

    await (_db.update(
      _db.bookingRequests,
    )..where((t) => t.id.equals(requestId))).write(
      BookingRequestsCompanion(
        status: const Value('rejected'),
        modifiedBy: Value(staffUsername),
        decidedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _pushOne(requestId);
    return true;
  }

  /// Resolve a request's patientUuid to a local patient id (for the approve dialog).
  Future<int?> localPatientId(String patientUuid) async => (await (_db.select(
    _db.patients,
  )..where((t) => t.uuid.equals(patientUuid))).getSingleOrNull())?.id;
}
