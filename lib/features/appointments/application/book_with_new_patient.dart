import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/core/utils/uuids.dart';
import 'package:is_dental/features/appointments/presentation/appointments_controller.dart';
import 'package:is_dental/features/patients/domain/patient.dart';
import 'package:is_dental/features/patients/presentation/patients_controller.dart';

final bookWithNewPatientProvider = Provider<BookWithNewPatient>(
  (ref) => BookWithNewPatient(ref),
);

/// Creates a brand-new patient AND books their appointment in a single
/// transaction. The local DB (source of truth) is never left with an
/// appointment pointing at a patient that doesn't exist; because the patient
/// is committed with its uuid first, the sync engine pushes patients-before-
/// appointments and resolves the FK with no Supabase conflict.
class BookWithNewPatient {
  BookWithNewPatient(this._ref);
  final Ref _ref;

  Future<void> call({
    required String fullName,
    required String dentist,
    required int chair,
    required String procedure,
    required DateTime startsAt,
    int durationMin = 45,
  }) async {
    final db = _ref.read(appDatabaseProvider);
    final patients = _ref.read(patientRepositoryProvider);
    final appts = _ref.read(appointmentRepositoryProvider);

    await db.transaction(() async {
      final uuid = Uuids.v4();

      // Reuses the normal create path (clinic stamp + audit + uuid handling),
      // so a quick-created patient is identical to one added via the editor.
      await patients.upsertPatient(
        Patient(
          id: 0,
          uuid: uuid,
          code: await _nextPatientCode(db),
          fullName: fullName.trim(),
          gender: Gender.other,
          status: PatientStatus.newPatient,
          treatmentSummary: 'New patient',
        ),
      );

      final created = await (db.select(
        db.patients,
      )..where((t) => t.uuid.equals(uuid))).getSingle();

      await appts.book(
        patientId: created.id,
        dentist: dentist,
        chair: chair,
        procedure: procedure,
        startsAt: startsAt,
        durationMin: durationMin,
      );
    });
  }

  /// Next free `PT-#####` based on the highest existing numeric suffix.
  Future<String> _nextPatientCode(AppDatabase db) async {
    final rows = await db.select(db.patients).get();
    var max = 10000;
    for (final r in rows) {
      final m = RegExp(r'PT-(\d+)').firstMatch(r.code);
      final n = m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
      if (n > max) max = n;
    }
    return 'PT-${max + 1}';
  }
}
