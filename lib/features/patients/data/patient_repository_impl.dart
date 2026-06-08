import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/patient.dart';
import '../domain/patient_repository.dart';
import '../domain/tooth_record.dart';
import '../domain/treatment_plan.dart';

class PatientRepositoryImpl implements PatientRepository {
  PatientRepositoryImpl(this._db);
  final AppDatabase _db;

  @override
  Stream<List<Patient>> watchPatients() =>
      (_db.select(_db.patients)
            ..where((t) => t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
          .watch()
          .map((rows) => rows.map(_toPatient).toList());

  @override
  Future<void> upsertPatient(Patient p) async {
    final clinicId = await _db.currentClinicId() ?? '';
    await _db
        .into(_db.patients)
        .insertOnConflictUpdate(
          PatientsCompanion(
            id: p.id == 0 ? const Value.absent() : Value(p.id),
            uuid: Value(p.uuid.isEmpty ? Uuids.v4() : p.uuid),
            clinicId: Value(clinicId),
            code: Value(p.code),
            fullName: Value(p.fullName),
            gender: Value(p.gender.name),
            age: Value(p.age),
            phone: Value(p.phone),
            allergies: Value(p.allergies),
            insurance: Value(p.insurance),
            lastVisit: Value(p.lastVisit),
            visitCount: Value(p.visitCount),
            balance: Value(p.balance),
            status: Value(p.status.name),
            treatmentSummary: Value(p.treatmentSummary),
            updatedAt: Value(DateTime.now()),
          ),
        );
    await _audit(clinicId, p.id == 0 ? 'create' : 'update', 'patient', p.code);
  }

  @override
  Future<void> softDeletePatient(int id) async {
    await (_db.update(_db.patients)..where((t) => t.id.equals(id))).write(
      PatientsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _audit(
      await _db.currentClinicId() ?? '',
      'soft_delete',
      'patient',
      '$id',
    );
  }

  @override
  Stream<Map<int, ToothRecord>> watchToothRecords(int patientId) =>
      (_db.select(
        _db.toothRecords,
      )..where((t) => t.patientId.equals(patientId))).watch().map(
        (rows) => {
          for (final r in rows)
            r.fdi: ToothRecord(
              fdi: r.fdi,
              state: ToothState.values.byName(r.state),
              note: r.note,
            ),
        },
      );

  @override
  Future<void> setToothState(int patientId, int fdi, ToothState state) async {
    final existing =
        await (_db.select(_db.toothRecords)
              ..where((t) => t.patientId.equals(patientId) & t.fdi.equals(fdi)))
            .getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.toothRecords)
          .insert(
            ToothRecordsCompanion.insert(
              patientId: patientId,
              fdi: fdi,
              state: Value(state.name),
            ),
          );
    } else {
      await (_db.update(
        _db.toothRecords,
      )..where((t) => t.id.equals(existing.id))).write(
        ToothRecordsCompanion(
          state: Value(state.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  @override
  Stream<TreatmentPlan?> watchActivePlan(int patientId) {
    final q =
        _db.select(_db.treatmentSteps).join([
            innerJoin(
              _db.treatmentPlans,
              _db.treatmentPlans.id.equalsExp(_db.treatmentSteps.planId),
            ),
          ])
          ..where(
            _db.treatmentPlans.patientId.equals(patientId) &
                _db.treatmentPlans.isDeleted.equals(false),
          )
          ..orderBy([OrderingTerm.asc(_db.treatmentSteps.position)]);
    return q.watch().map((rows) {
      if (rows.isEmpty) return null;
      final plan = rows.first.readTable(_db.treatmentPlans);
      final steps = rows.map((r) {
        final s = r.readTable(_db.treatmentSteps);
        return TreatmentStep(
          id: s.id,
          order: s.position,
          label: s.label,
          detail: s.detail,
          status: StepStatus.values.byName(s.status),
        );
      }).toList();
      return TreatmentPlan(id: plan.id, title: plan.title, steps: steps);
    });
  }

  Future<void> _audit(
    String clinicId,
    String action,
    String entity,
    String? ref,
  ) => _db
      .into(_db.auditLog)
      .insert(
        AuditLogCompanion.insert(
          clinicId: clinicId,
          action: action,
          entity: entity,
          entityRef: Value(ref),
        ),
      );

  Patient _toPatient(PatientRow r) => Patient(
    id: r.id,
    uuid: r.uuid,
    code: r.code,
    fullName: r.fullName,
    gender: Gender.values.byName(r.gender),
    age: r.age,
    phone: r.phone,
    allergies: r.allergies,
    insurance: r.insurance,
    lastVisit: r.lastVisit,
    visitCount: r.visitCount,
    balance: r.balance,
    status: PatientStatus.values.byName(r.status),
    treatmentSummary: r.treatmentSummary,
  );

  // --- dev convenience: mirrors the prototype so screens render with data ---
  @override
  Future<void> seedDemoDataIfEmpty() async {
    final clinicId = await _db.currentClinicId();
    if (clinicId == null) return;
    if ((await _db.select(_db.patients).get()).isNotEmpty) return;

    final demo =
        <
          (
            String,
            String,
            String,
            int,
            String,
            DateTime?,
            int,
            int,
            String,
            String,
            String?,
            String?,
          )
        >[
          (
            'PT-10472',
            'Fatima Aslam',
            'female',
            32,
            '+92 300 1234567',
            DateTime(2026, 5, 14),
            9,
            8500,
            'inTreatment',
            'Root Canal (ongoing)',
            'Penicillin allergy',
            'State Life',
          ),
          (
            'PT-10468',
            'Usman Raza',
            'male',
            41,
            '+92 333 9988776',
            DateTime(2026, 6, 3),
            6,
            0,
            'active',
            'Scaling & Polishing',
            null,
            null,
          ),
          (
            'PT-10455',
            'Hira Nadeem',
            'female',
            28,
            '+92 301 4455667',
            DateTime(2026, 6, 3),
            3,
            0,
            'active',
            'Composite Filling',
            null,
            null,
          ),
          (
            'PT-10440',
            'Tariq Mehmood',
            'male',
            55,
            '+92 345 2233445',
            DateTime(2026, 4, 21),
            12,
            12000,
            'pendingPayment',
            'Crown Fitting',
            null,
            'EFU Health',
          ),
          (
            'PT-10399',
            'Ayesha Zubair',
            'female',
            19,
            '+92 312 6677889',
            DateTime(2026, 6, 3),
            7,
            3000,
            'inTreatment',
            'Orthodontics',
            null,
            null,
          ),
          (
            'PT-10501',
            'Sana Kamal',
            'female',
            34,
            '+92 321 1122334',
            null,
            0,
            0,
            'newPatient',
            'New patient',
            null,
            null,
          ),
          (
            'PT-10377',
            'Bilal Akhtar',
            'male',
            47,
            '+92 308 5566778',
            DateTime(2026, 5, 18),
            5,
            0,
            'active',
            'Whitening',
            null,
            null,
          ),
          (
            'PT-10302',
            'Nida Yousuf',
            'female',
            38,
            '+92 333 4433221',
            DateTime(2026, 4, 29),
            8,
            1500,
            'recallDue',
            'Extraction',
            null,
            null,
          ),
        ];

    int? firstId;
    for (final d in demo) {
      final id = await _db
          .into(_db.patients)
          .insert(
            PatientsCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              code: d.$1,
              fullName: d.$2,
              gender: Value(d.$3),
              age: Value(d.$4),
              phone: Value(d.$5),
              lastVisit: Value(d.$6),
              visitCount: Value(d.$7),
              balance: Value(d.$8),
              status: Value(d.$9),
              treatmentSummary: Value(d.$10),
              allergies: Value(d.$11),
              insurance: Value(d.$12),
            ),
          );
      firstId ??= id;
    }

    const states = {
      16: 'caries',
      36: 'treated',
      46: 'crown',
      18: 'missing',
      28: 'missing',
      14: 'caries',
      24: 'treated',
    };
    for (final e in states.entries) {
      await _db
          .into(_db.toothRecords)
          .insert(
            ToothRecordsCompanion.insert(
              patientId: firstId!,
              fdi: e.key,
              state: Value(e.value),
            ),
          );
    }
    final planId = await _db
        .into(_db.treatmentPlans)
        .insert(
          TreatmentPlansCompanion.insert(
            patientId: firstId!,
            title: 'Active Treatment Plan',
          ),
        );
    final steps = <(int, String, String, String)>[
      (0, 'Diagnosis & X-Ray', 'Completed · 02 May', 'done'),
      (1, 'RCT — Session 1', 'Completed · 14 May', 'done'),
      (2, 'RCT — Session 2', 'In progress · today', 'current'),
      (3, 'Crown Placement', 'Scheduled · 28 May', 'todo'),
    ];
    for (final s in steps) {
      await _db
          .into(_db.treatmentSteps)
          .insert(
            TreatmentStepsCompanion.insert(
              planId: planId,
              position: s.$1,
              label: s.$2,
              detail: Value(s.$3),
              status: Value(s.$4),
            ),
          );
    }
  }
}
