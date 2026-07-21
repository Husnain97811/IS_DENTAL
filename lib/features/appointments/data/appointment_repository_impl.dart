import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/appointment.dart';
import '../domain/appointment_repository.dart';

class AppointmentRepositoryImpl implements AppointmentRepository {
  AppointmentRepositoryImpl(this._db);
  final AppDatabase _db;

  @override
  Stream<List<Appointment>> watchAppointmentsForDay(
    DateTime day, {
    String? branchId,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final q =
        _db.select(_db.appointments).join([
            innerJoin(
              _db.patients,
              _db.patients.id.equalsExp(_db.appointments.patientId),
            ),
          ])
          ..where(
            _db.appointments.isDeleted.equals(false) &
                _db.appointments.startsAt.isBiggerOrEqualValue(start) &
                _db.appointments.startsAt.isSmallerThanValue(end) &
                (branchId == null
                    ? const Constant(true)
                    : _db.appointments.branchId.equals(branchId)),
          )
          ..orderBy([OrderingTerm.asc(_db.appointments.startsAt)]);
    return q.watch().map(
      (rows) => rows.map((r) {
        final a = r.readTable(_db.appointments);
        final p = r.readTable(_db.patients);
        return Appointment(
          id: a.id,
          uuid: a.uuid,
          patientId: a.patientId,
          patientName: p.fullName,
          dentist: a.dentist,
          chair: a.chair,
          procedure: a.procedure,
          startsAt: a.startsAt,
          durationMin: a.durationMin,
          status: AppointmentStatus.values.byName(a.status),
        );
      }).toList(),
    );
  }

  @override
  Stream<List<Appointment>> watchAppointmentsForMonth(
    int year,
    int month, {
    String? branchId,
  }) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final q =
        _db.select(_db.appointments).join([
            innerJoin(
              _db.patients,
              _db.patients.id.equalsExp(_db.appointments.patientId),
            ),
          ])
          ..where(
            _db.appointments.isDeleted.equals(false) &
                _db.appointments.startsAt.isBiggerOrEqualValue(start) &
                _db.appointments.startsAt.isSmallerThanValue(end) &
                (branchId == null
                    ? const Constant(true)
                    : _db.appointments.branchId.equals(branchId)),
          )
          ..orderBy([OrderingTerm.asc(_db.appointments.startsAt)]);
    return q.watch().map(
      (rows) => rows.map((r) {
        final a = r.readTable(_db.appointments);
        final p = r.readTable(_db.patients);
        return Appointment(
          id: a.id,
          uuid: a.uuid,
          patientId: a.patientId,
          patientName: p.fullName,
          dentist: a.dentist,
          chair: a.chair,
          procedure: a.procedure,
          startsAt: a.startsAt,
          durationMin: a.durationMin,
          status: AppointmentStatus.values.byName(a.status),
        );
      }).toList(),
    );
  }

  @override
  Stream<List<Appointment>> watchAppointmentsForPatient(int patientId) {
    final q =
        _db.select(_db.appointments).join([
            innerJoin(
              _db.patients,
              _db.patients.id.equalsExp(_db.appointments.patientId),
            ),
          ])
          ..where(
            _db.appointments.isDeleted.equals(false) &
                _db.appointments.patientId.equals(patientId),
          )
          ..orderBy([OrderingTerm.desc(_db.appointments.startsAt)]);
    return q.watch().map(
      (rows) => rows.map((r) {
        final a = r.readTable(_db.appointments);
        final p = r.readTable(_db.patients);
        return Appointment(
          id: a.id,
          uuid: a.uuid,
          patientId: a.patientId,
          patientName: p.fullName,
          dentist: a.dentist,
          chair: a.chair,
          procedure: a.procedure,
          startsAt: a.startsAt,
          durationMin: a.durationMin,
          status: AppointmentStatus.values.byName(a.status),
        );
      }).toList(),
    );
  }

  @override
  Future<void> setStatus(int id, AppointmentStatus status) =>
      (_db.update(_db.appointments)..where((t) => t.id.equals(id))).write(
        AppointmentsCompanion(
          status: Value(status.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Stream<Set<int>> watchMarkedDays(int year, int month, {String? branchId}) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return (_db.select(_db.appointments)..where(
          (t) =>
              t.isDeleted.equals(false) &
              t.startsAt.isBiggerOrEqualValue(start) &
              t.startsAt.isSmallerThanValue(end) &
              (branchId == null
                  ? const Constant(true)
                  : t.branchId.equals(branchId)),
        ))
        .watch()
        .map((rows) => rows.map((r) => r.startsAt.day).toSet());
  }

  @override
  Future<List<({DateTime time, bool busy})>> slotsFor(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final booked =
        await (_db.select(_db.appointments)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.startsAt.isBiggerOrEqualValue(start) &
                  t.startsAt.isSmallerThanValue(end),
            ))
            .get();
    final busy = booked
        .map((b) => b.startsAt.hour * 60 + b.startsAt.minute)
        .toSet();
    final slots = <({DateTime time, bool busy})>[];
    var t = DateTime(day.year, day.month, day.day, 9, 0);
    final close = DateTime(day.year, day.month, day.day, 18, 0);
    while (t.isBefore(close)) {
      slots.add((time: t, busy: busy.contains(t.hour * 60 + t.minute)));
      t = t.add(const Duration(minutes: 45));
    }
    return slots;
  }

  @override
  Future<void> book({
    required int patientId,
    required String dentist,
    required int chair,
    required String procedure,
    required DateTime startsAt,
    int durationMin = 45,
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    await _db
        .into(_db.appointments)
        .insert(
          AppointmentsCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId,
            branchId: Value(await _db.currentBranchId()),
            patientId: patientId,
            dentist: dentist,
            chair: Value(chair),
            procedure: procedure,
            startsAt: startsAt,
            durationMin: Value(durationMin),
            status: const Value('upcoming'),
          ),
        );
  }

  @override
  Future<void> seedDemoAppointmentsIfEmpty() async {
    final clinicId = await _db.currentClinicId();
    if (clinicId == null) return;
    if ((await _db.select(_db.appointments).get()).isNotEmpty) return;
    final patients = await _db.select(_db.patients).get();
    if (patients.isEmpty) return;
    int idFor(String code) => patients
        .firstWhere((p) => p.code == code, orElse: () => patients.first)
        .id;

    final n = DateTime.now();
    DateTime at(int h, int m) => DateTime(n.year, n.month, n.day, h, m);
    final demo = <(String, String, int, String, DateTime, int, String)>[
      (
        'PT-10472',
        'Dr. Khan',
        1,
        'Root Canal · Molar #36',
        at(9, 0),
        45,
        'inChair',
      ),
      (
        'PT-10468',
        'Dr. Bilal',
        2,
        'Scaling & Polishing',
        at(9, 45),
        30,
        'waiting',
      ),
      (
        'PT-10455',
        'Dr. Sara',
        3,
        'Composite Filling · #14',
        at(10, 30),
        40,
        'completed',
      ),
      (
        'PT-10440',
        'Dr. Khan',
        1,
        'Crown Fitting · Zirconia · #46',
        at(11, 15),
        60,
        'upcoming',
      ),
      (
        'PT-10399',
        'Dr. Sara',
        3,
        'Braces Adjustment',
        at(12, 0),
        30,
        'upcoming',
      ),
      (
        'PT-10501',
        'Dr. Bilal',
        2,
        'Implant Consultation',
        at(14, 0),
        45,
        'upcoming',
      ),
      ('PT-10377', 'Dr. Khan', 1, 'Teeth Whitening', at(15, 0), 60, 'upcoming'),
    ];
    for (final d in demo) {
      await _db
          .into(_db.appointments)
          .insert(
            AppointmentsCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              patientId: idFor(d.$1),
              dentist: d.$2,
              chair: Value(d.$3),
              procedure: d.$4,
              startsAt: d.$5,
              durationMin: Value(d.$6),
              status: Value(d.$7),
            ),
          );
    }
  }
}
