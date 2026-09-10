import 'package:drift/drift.dart';
import 'package:is_dental/features/prescriptions/data/domain/prescription.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';

class PrescriptionRepository {
  PrescriptionRepository(this._db);
  final AppDatabase _db;

  // ─────────── MEDICINES CATALOG ───────────
  Stream<List<Medicine>> watchMedicines() =>
      (_db.select(_db.medicines)
            ..where((t) => t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => Medicine(
                    id: r.id,
                    uuid: r.uuid,
                    name: r.name,
                    form: r.form,
                    defaultDosage: r.defaultDosage,
                    defaultFrequency: r.defaultFrequency,
                    category: r.category,
                  ),
                )
                .toList(),
          );

  Future<void> upsertMedicine({
    int? id,
    required String name,
    String form = '',
    String defaultDosage = '',
    String defaultFrequency = '',
    String category = '',
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    if (id == null) {
      await _db
          .into(_db.medicines)
          .insert(
            MedicinesCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              name: name,
              form: Value(form),
              defaultDosage: Value(defaultDosage),
              defaultFrequency: Value(defaultFrequency),
              category: Value(category),
            ),
          );
    } else {
      await (_db.update(_db.medicines)..where((t) => t.id.equals(id))).write(
        MedicinesCompanion(
          name: Value(name),
          form: Value(form),
          defaultDosage: Value(defaultDosage),
          defaultFrequency: Value(defaultFrequency),
          category: Value(category),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<void> deleteMedicine(int id) =>
      (_db.update(_db.medicines)..where((t) => t.id.equals(id))).write(
        MedicinesCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  // ─────────── PRECAUTION SETS ───────────
  Stream<List<PrecautionSet>> watchPrecautionSets() {
    final q = _db.select(_db.precautionSets)
      ..where((t) => t.isDeleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm.asc(t.position),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return q.watch().asyncMap((sets) async {
      final out = <PrecautionSet>[];
      for (final s in sets) {
        final lines =
            await (_db.select(_db.precautionLines)
                  ..where((t) => t.setId.equals(s.id))
                  ..orderBy([(t) => OrderingTerm.asc(t.position)]))
                .get();
        out.add(
          PrecautionSet(
            id: s.id,
            uuid: s.uuid,
            name: s.name,
            lines: lines
                .map((l) => CareLine(urdu: l.urdu, english: l.english))
                .toList(),
          ),
        );
      }
      return out;
    });
  }

  /// Create or replace a set with its lines.
  Future<void> saveSet({
    int? id,
    required String name,
    required List<CareLine> lines,
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    late final int realId;

    if (id == null) {
      realId = await _db
          .into(_db.precautionSets)
          .insert(
            PrecautionSetsCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              name: name,
            ),
          );
    } else {
      realId = id;
      await (_db.update(
        _db.precautionSets,
      )..where((t) => t.id.equals(id))).write(
        PrecautionSetsCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    await (_db.delete(
      _db.precautionLines,
    )..where((t) => t.setId.equals(realId))).go();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].isEmpty) continue;
      await _db
          .into(_db.precautionLines)
          .insert(
            PrecautionLinesCompanion.insert(
              setId: realId,
              position: Value(i),
              urdu: Value(lines[i].urdu),
              english: Value(lines[i].english),
            ),
          );
    }
  }

  Future<void> deleteSet(int id) =>
      (_db.update(_db.precautionSets)..where((t) => t.id.equals(id))).write(
        PrecautionSetsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  // ─────────── PRESCRIPTIONS ───────────
  Stream<List<Prescription>> watchForPatient(int patientId) {
    final q = _db.select(_db.prescriptions)
      ..where((t) => t.patientId.equals(patientId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.issuedAt)]);
    return q.watch().asyncMap((rows) async {
      final out = <Prescription>[];
      for (final r in rows) {
        out.add(await _hydrate(r));
      }
      return out;
    });
  }

  Future<Prescription?> byId(int id) async {
    final r = await (_db.select(
      _db.prescriptions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _hydrate(r);
  }

  Future<Prescription> _hydrate(PrescriptionRow r) async {
    final items =
        await (_db.select(_db.prescriptionItems)
              ..where((t) => t.prescriptionId.equals(r.id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    final care =
        await (_db.select(_db.prescriptionCare)
              ..where((t) => t.prescriptionId.equals(r.id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return Prescription(
      id: r.id,
      uuid: r.uuid,
      rxNo: r.rxNo,
      patientId: r.patientId,
      patientUuid: r.patientUuid,
      appointmentId: r.appointmentId,
      appointmentLabel: r.appointmentLabel,
      doctorName: r.doctorName,
      advice: r.advice,
      issuedAt: r.issuedAt,
      items: items
          .map(
            (i) => MedicineItem(
              medicine: i.medicine,
              dosage: i.dosage,
              frequency: i.frequency,
              duration: i.duration,
              instructions: i.instructions,
            ),
          )
          .toList(),
      care: care
          .map((c) => CareLine(urdu: c.urdu, english: c.english))
          .toList(),
    );
  }

  /// Create or update a prescription with its items + care lines.
  Future<int> save({
    int? id,
    required int patientId,
    required String patientUuid,
    int? appointmentId,
    String appointmentLabel = '',
    required String doctorName,
    String advice = '',
    required List<MedicineItem> items,
    required List<CareLine> care,
    DateTime? issuedAt,
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    late final int realId;

    if (id == null) {
      // ── new ──
      realId = await _db
          .into(_db.prescriptions)
          .insert(
            PrescriptionsCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              branchId: Value(await _db.currentBranchId()),
              patientId: patientId,
              patientUuid: patientUuid,
              rxNo: Value(await _db.nextRxNo()),
              appointmentId: Value(appointmentId),
              appointmentLabel: Value(appointmentLabel),
              doctorName: Value(doctorName),
              advice: Value(advice),
              issuedAt: Value(issuedAt ?? DateTime.now()),
            ),
          );
    } else {
      // ── edit: never touch uuid or rxNo ──
      realId = id;
      await (_db.update(
        _db.prescriptions,
      )..where((t) => t.id.equals(id))).write(
        PrescriptionsCompanion(
          appointmentId: Value(appointmentId),
          appointmentLabel: Value(appointmentLabel),
          doctorName: Value(doctorName),
          advice: Value(advice),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    // replace items
    await (_db.delete(
      _db.prescriptionItems,
    )..where((t) => t.prescriptionId.equals(realId))).go();
    for (var i = 0; i < items.length; i++) {
      final m = items[i];
      if (m.medicine.trim().isEmpty) continue;
      await _db
          .into(_db.prescriptionItems)
          .insert(
            PrescriptionItemsCompanion.insert(
              prescriptionId: realId,
              position: Value(i),
              medicine: m.medicine,
              dosage: Value(m.dosage),
              frequency: Value(m.frequency),
              duration: Value(m.duration),
              instructions: Value(m.instructions),
            ),
          );
    }

    // replace care lines
    await (_db.delete(
      _db.prescriptionCare,
    )..where((t) => t.prescriptionId.equals(realId))).go();
    for (var i = 0; i < care.length; i++) {
      if (care[i].isEmpty) continue;
      await _db
          .into(_db.prescriptionCare)
          .insert(
            PrescriptionCareCompanion.insert(
              prescriptionId: realId,
              position: Value(i),
              urdu: Value(care[i].urdu),
              english: Value(care[i].english),
            ),
          );
    }

    await _touchPatient(patientId);
    return realId;
  }

  Future<void> deletePrescription(int id, int patientId) async {
    await (_db.update(_db.prescriptions)..where((t) => t.id.equals(id))).write(
      PrescriptionsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _touchPatient(patientId);
  }

  Future<void> _touchPatient(int patientId) =>
      (_db.update(_db.patients)..where((t) => t.id.equals(patientId))).write(
        PatientsCompanion(updatedAt: Value(DateTime.now())),
      );

  // ─────────── SEED DEFAULTS ───────────
  /// Seeds a starter catalog + Urdu precaution sets on first use.
  Future<void> seedIfEmpty() async {
    final clinicId = await _db.currentClinicId();
    if (clinicId == null) return;

    if ((await _db.select(_db.medicines).get()).isEmpty) {
      const meds = <(String, String, String, String, String)>[
        ('Augmentin 625mg', 'Tablet', '1 tab', 'TDS (3× daily)', 'Antibiotic'),
        ('Amoxil 500mg', 'Capsule', '1 cap', 'TDS (3× daily)', 'Antibiotic'),
        ('Flagyl 400mg', 'Tablet', '1 tab', 'TDS (3× daily)', 'Antibiotic'),
        ('Brufen 400mg', 'Tablet', '1 tab', 'BD (2× daily)', 'Painkiller'),
        ('Panadol 500mg', 'Tablet', '1–2 tab', 'QID (4× daily)', 'Painkiller'),
        (
          'Ponstan Forte 500mg',
          'Tablet',
          '1 tab',
          'TDS (3× daily)',
          'Painkiller',
        ),
        (
          'Chlorhexidine 0.2%',
          'Mouthwash',
          '10 ml',
          'BD (2× daily)',
          'Antiseptic',
        ),
        (
          'Risek 20mg',
          'Capsule',
          '1 cap',
          'OD (once daily)',
          'Gastro-protective',
        ),
      ];
      for (final m in meds) {
        await upsertMedicine(
          name: m.$1,
          form: m.$2,
          defaultDosage: m.$3,
          defaultFrequency: m.$4,
          category: m.$5,
        );
      }
    }

    if ((await _db.select(_db.precautionSets).get()).isEmpty) {
      await saveSet(
        name: 'After Extraction — دانت نکالنے کے بعد',
        lines: const [
          CareLine(
            urdu: 'آج کے دن کلی نہیں کرنی',
            english: 'Do not rinse your mouth today',
          ),
          CareLine(
            urdu: 'سخت چیز نہیں کھانی، نرم غذا لیں',
            english: 'Avoid hard foods — take soft diet',
          ),
          CareLine(
            urdu: 'ٹھنڈی چیزیں اور آئس کریم لے سکتے ہیں',
            english: 'Cold items and ice cream are allowed',
          ),
          CareLine(
            urdu: 'گرم چائے اور گرم کھانے سے پرہیز کریں',
            english: 'Avoid hot tea and hot food',
          ),
          CareLine(
            urdu: 'تھوکنا نہیں، خون رکنے دیں',
            english: 'Do not spit — let the clot form',
          ),
          CareLine(
            urdu: 'سگریٹ نوشی سے مکمل پرہیز',
            english: 'No smoking at all',
          ),
          CareLine(
            urdu: 'کل سے نیم گرم پانی میں نمک ڈال کر کلی کریں',
            english: 'From tomorrow, rinse with warm salt water',
          ),
        ],
      );
      await saveSet(
        name: 'After Root Canal — آر سی ٹی کے بعد',
        lines: const [
          CareLine(
            urdu: 'علاج والی طرف سے نہ چبائیں',
            english: 'Do not chew from the treated side',
          ),
          CareLine(
            urdu: 'سخت اور چپکنے والی چیزوں سے پرہیز',
            english: 'Avoid hard and sticky food',
          ),
          CareLine(
            urdu: 'ہلکا درد معمول کی بات ہے، دوا لیتے رہیں',
            english: 'Mild pain is normal — continue the medicine',
          ),
          CareLine(
            urdu: 'اگلی وزٹ پر ضرور آئیں، کراؤن لازمی ہے',
            english: 'Attend the next visit — the crown is essential',
          ),
        ],
      );
      await saveSet(
        name: 'After Scaling — اسکیلنگ کے بعد',
        lines: const [
          CareLine(
            urdu: 'ایک ہفتہ بہت ٹھنڈی اور بہت گرم چیزوں سے پرہیز',
            english: 'Avoid very cold and very hot items for one week',
          ),
          CareLine(
            urdu: 'دن میں دو بار نرم برش سے برش کریں',
            english: 'Brush twice daily with a soft brush',
          ),
          CareLine(
            urdu: 'مسوڑھوں سے ہلکا خون آنا معمول ہے',
            english: 'Slight gum bleeding is normal',
          ),
        ],
      );
      await saveSet(
        name: 'General Oral Care — عام ہدایات',
        lines: const [
          CareLine(
            urdu: 'دن میں دو بار برش کریں',
            english: 'Brush twice a day',
          ),
          CareLine(
            urdu: 'میٹھی چیزیں کم کھائیں',
            english: 'Reduce sugary food',
          ),
          CareLine(
            urdu: 'ہر چھ ماہ بعد چیک اپ کروائیں',
            english: 'Get a check-up every six months',
          ),
          CareLine(
            urdu: 'پان، گٹکا اور چھالیہ سے پرہیز کریں',
            english: 'Avoid paan, gutka and betel nut',
          ),
        ],
      );
    }
  }
}
