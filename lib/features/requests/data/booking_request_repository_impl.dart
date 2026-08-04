import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/booking_request.dart';

class BookingRequestRepository {
  BookingRequestRepository(this._db);
  final AppDatabase _db;

  /// PKT = UTC + 5. Stored slot is UTC; this is the real booked Pakistan time.
  static DateTime _toPkt(DateTime utc) =>
      utc.toUtc().add(const Duration(hours: 5));

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
  Future<void> approve({
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
    await _db.transaction(() async {
      final req = await (_db.select(
        _db.bookingRequests,
      )..where((t) => t.id.equals(requestId))).getSingleOrNull();
      if (req == null || req.status != 'pending') return; // stale guard

      // create the real appointment (branch-stamped inside book path)
      final clinicId = await _db.currentClinicId() ?? '';
      await _db
          .into(_db.appointments)
          .insert(
            AppointmentsCompanion.insert(
              uuid: Uuids.v4(),
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
  }

  /// Reject: frees the slot (status != pending) and timestamps for 30-day purge.
  /// Guarded to pending only.
  Future<void> reject({
    required int requestId,
    required String staffUsername,
  }) async {
    final req = await (_db.select(
      _db.bookingRequests,
    )..where((t) => t.id.equals(requestId))).getSingleOrNull();
    if (req == null || req.status != 'pending') return;
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
  }

  /// Resolve a request's patientUuid to a local patient id (for the approve dialog).
  Future<int?> localPatientId(String patientUuid) async => (await (_db.select(
    _db.patients,
  )..where((t) => t.uuid.equals(patientUuid))).getSingleOrNull())?.id;
}
