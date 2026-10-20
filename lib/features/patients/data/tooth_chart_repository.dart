import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/tooth_finding.dart';

class ToothChartRepository {
  ToothChartRepository(this._db);
  final AppDatabase _db;

  // ── read ─────────────────────────────────────────────────────────────────

  /// Every finding for a patient, deleted ones included — the history needs
  /// them. Callers filter `!isDeleted` for what is currently true.
  Stream<List<ToothFinding>> watch(int patientId) =>
      (_db.select(_db.toothFindings)
            ..where((t) => t.patientId.equals(patientId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_fromRow).whereType<ToothFinding>().toList());

  Future<List<ToothFinding>> liveFor(int patientId, int fdi) async {
    final rows =
        await (_db.select(_db.toothFindings)..where(
              (t) =>
                  t.patientId.equals(patientId) &
                  t.fdi.equals(fdi) &
                  t.isDeleted.equals(false),
            ))
            .get();
    return rows.map(_fromRow).whereType<ToothFinding>().toList();
  }

  // ── write ────────────────────────────────────────────────────────────────

  /// Click on one surface with a surface tool (caries, filling, sealant).
  ///
  /// Adds the surface to this tooth's matching finding, or creates one.
  /// Clicking a surface that is already marked clears it; clearing the last
  /// surface removes the finding.
  Future<void> toggleSurface({
    required int patientId,
    required String patientUuid,
    required int fdi,
    required String surface,
    required ToothKind kind,
    required FindingStatus status,
    required String by,
  }) async {
    final existing =
        await (_db.select(_db.toothFindings)
              ..where(
                (t) =>
                    t.patientId.equals(patientId) &
                    t.fdi.equals(fdi) &
                    t.kind.equals(kind.name) &
                    t.status.equals(status.name) &
                    t.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();

    if (existing == null) {
      await _insert(
        patientId: patientId,
        patientUuid: patientUuid,
        fdi: fdi,
        kind: kind,
        status: status,
        surfaces: surface,
        by: by,
      );
      return;
    }

    final set = existing.surfaces.split('').toSet();
    set.contains(surface) ? set.remove(surface) : set.add(surface);

    if (set.isEmpty) {
      await softDelete(existing.id, by: by);
      return;
    }
    await (_db.update(
      _db.toothFindings,
    )..where((t) => t.id.equals(existing.id))).write(
      ToothFindingsCompanion(
        surfaces: Value(surfaceNotation(set)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// A whole-tooth tool on one or more teeth.
  ///
  /// If every tooth already has it, it is removed from all of them (so the
  /// same click undoes it); otherwise it is added where missing.
  /// Returns how many teeth changed.
  Future<int> toggleWhole({
    required int patientId,
    required String patientUuid,
    required List<int> fdis,
    required ToothKind kind,
    required FindingStatus status,
    required String by,
  }) async {
    final found = <int, ToothFindingRow>{};
    for (final fdi in fdis) {
      final r =
          await (_db.select(_db.toothFindings)
                ..where(
                  (t) =>
                      t.patientId.equals(patientId) &
                      t.fdi.equals(fdi) &
                      t.kind.equals(kind.name) &
                      t.status.equals(status.name) &
                      t.isDeleted.equals(false),
                )
                ..limit(1))
              .getSingleOrNull();
      if (r != null) found[fdi] = r;
    }

    var changed = 0;
    await _db.transaction(() async {
      if (found.length == fdis.length) {
        for (final r in found.values) {
          await softDelete(r.id, by: by);
          changed++;
        }
        return;
      }
      for (final fdi in fdis) {
        if (found.containsKey(fdi)) continue;
        await _insert(
          patientId: patientId,
          patientUuid: patientUuid,
          fdi: fdi,
          kind: kind,
          status: status,
          surfaces: '',
          by: by,
        );
        changed++;
      }
    });
    return changed;
  }

  /// Adds a finding from the tooth dialog.
  ///
  /// Surface findings merge into an existing one of the same kind and status
  /// (Filling MO, then Filling D → Filling MOD). Returns false when the tooth
  /// already has exactly this, so nothing changed.
  Future<bool> add({
    required int patientId,
    required String patientUuid,
    required int fdi,
    required ToothKind kind,
    required FindingStatus status,
    Set<String> surfaces = const {},
    String? note,
    required String by,
  }) async {
    final cleanNote = (note ?? '').trim().isEmpty ? null : note!.trim();
    final existing =
        await (_db.select(_db.toothFindings)
              ..where(
                (t) =>
                    t.patientId.equals(patientId) &
                    t.fdi.equals(fdi) &
                    t.kind.equals(kind.name) &
                    t.status.equals(status.name) &
                    t.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();

    if (existing == null) {
      await _insert(
        patientId: patientId,
        patientUuid: patientUuid,
        fdi: fdi,
        kind: kind,
        status: status,
        surfaces: kind.bySurface ? surfaceNotation(surfaces) : '',
        note: cleanNote,
        by: by,
      );
      return true;
    }
    if (!kind.bySurface) return false;

    final merged = surfaceNotation({
      ...existing.surfaces.split('').where((s) => s.isNotEmpty),
      ...surfaces,
    });
    if (merged == existing.surfaces && cleanNote == null) return false;
    await (_db.update(
      _db.toothFindings,
    )..where((t) => t.id.equals(existing.id))).write(
      ToothFindingsCompanion(
        surfaces: Value(merged),
        note: cleanNote == null ? const Value.absent() : Value(cleanNote),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return true;
  }

  /// Planned → done. Records who did it and when.
  Future<void> markDone(int id, {required String by}) {
    final now = DateTime.now();
    return (_db.update(_db.toothFindings)..where((t) => t.id.equals(id))).write(
      ToothFindingsCompanion(
        status: const Value('done'),
        completedByName: Value(by),
        completedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> setNote(int id, String? note) =>
      (_db.update(_db.toothFindings)..where((t) => t.id.equals(id))).write(
        ToothFindingsCompanion(
          note: Value((note ?? '').trim().isEmpty ? null : note!.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Never a hard delete — the row stays, so the removal syncs and the
  /// history keeps it.
  Future<void> softDelete(int id, {required String by}) {
    final now = DateTime.now();
    return (_db.update(_db.toothFindings)..where((t) => t.id.equals(id))).write(
      ToothFindingsCompanion(
        isDeleted: const Value(true),
        deletedByName: Value(by),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  // ── one-time import from the old chart ──────────────────────────────────

  /// Copies old single-state tooth records into findings marked "existing"
  /// (or "found" for caries), for patients that have no findings at all yet.
  ///
  /// Safe to run any number of times:
  ///  • a patient who already has any finding is skipped, so nothing charted
  ///    on the new chart is ever duplicated;
  ///  • the uuid is built from the patient and tooth, not random, so two
  ///    computers importing the same patient produce the SAME row.
  ///
  /// Run it only AFTER this computer has pulled findings from the cloud,
  /// otherwise a patient charted on another computer looks "empty" here.
  ///
  /// Returns how many findings were created.
  Future<int> importLegacy() async {
    final rows = await _db
        .customSelect(
          '''
SELECT t.patient_id AS pid, t.fdi AS fdi, t.state AS state, t.note AS note,
       t.updated_at AS at, p.uuid AS puuid, p.clinic_id AS cid
FROM tooth_records t
JOIN patients p ON p.id = t.patient_id
WHERE t.state IN ('caries','treated','crown','rootCanal','bridge','implant','missing')
  AND p.is_deleted = 0
  AND NOT EXISTS (SELECT 1 FROM tooth_findings f WHERE f.patient_id = t.patient_id)
''',
          readsFrom: {_db.toothRecords, _db.patients, _db.toothFindings},
        )
        .get();
    if (rows.isEmpty) return 0;

    const kindOf = {
      'caries': ToothKind.caries,
      'treated': ToothKind.filling,
      'crown': ToothKind.crown,
      'rootCanal': ToothKind.rct,
      'bridge': ToothKind.bridge,
      'implant': ToothKind.implant,
      'missing': ToothKind.missing,
    };

    // updatedAt is NOW (not the old record's date) so the push picks the
    // rows up even when the old record is older than the push cursor.
    final now = DateTime.now();
    var n = 0;
    await _db.transaction(() async {
      for (final r in rows) {
        final kind = kindOf[r.read<String>('state')];
        if (kind == null) continue;
        final puuid = r.read<String>('puuid');
        final fdi = r.read<int>('fdi');
        final at = r.readNullable<DateTime>('at') ?? now;
        final id = await _db
            .into(_db.toothFindings)
            .insert(
              ToothFindingsCompanion.insert(
                uuid: 'mig-$puuid-$fdi',
                clinicId: r.readNullable<String>('cid') ?? '',
                patientId: r.read<int>('pid'),
                patientUuid: puuid,
                fdi: fdi,
                kind: kind.name,
                status: kind == ToothKind.caries ? 'found' : 'existing',
                surfaces: const Value(''),
                note: Value(r.readNullable<String>('note')),
                createdByName: const Value('Imported from previous chart'),
                createdAt: Value(at),
                updatedAt: Value(now),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (id > 0) n++;
      }
    });
    return n;
  }

  // ── sync helpers ─────────────────────────────────────────────────────────

  Future<List<ToothFindingRow>> changedSince(DateTime since) => (_db.select(
    _db.toothFindings,
  )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();

  /// Applies one row from the cloud. Last write wins by updatedAt unless
  /// [force] (a full restore).
  Future<void> applyRemote(
    Map<String, dynamic> r,
    int patientId, {
    required bool force,
  }) async {
    DateTime? dt(String k) =>
        r[k] == null ? null : DateTime.parse(r[k] as String).toLocal();
    final u = dt('updated_at') ?? DateTime.now();
    final existing = await (_db.select(
      _db.toothFindings,
    )..where((t) => t.uuid.equals(r['uuid'] as String))).getSingleOrNull();
    if (!force && existing != null && !u.isAfter(existing.updatedAt)) return;
    final c = ToothFindingsCompanion(
      uuid: Value(r['uuid'] as String),
      clinicId: Value(r['clinic_id'] as String? ?? ''),
      patientId: Value(patientId),
      patientUuid: Value(r['patient_uuid'] as String),
      fdi: Value((r['fdi'] as num).toInt()),
      kind: Value(r['kind'] as String),
      status: Value(r['status'] as String),
      surfaces: Value(r['surfaces'] as String? ?? ''),
      note: Value(r['note'] as String?),
      createdByName: Value(r['created_by_name'] as String? ?? ''),
      createdAt: Value(dt('created_at') ?? u),
      completedByName: Value(r['completed_by_name'] as String?),
      completedAt: Value(dt('completed_at')),
      isDeleted: Value(r['is_deleted'] as bool? ?? false),
      deletedByName: Value(r['deleted_by_name'] as String?),
      deletedAt: Value(dt('deleted_at')),
      updatedAt: Value(u),
    );
    if (existing == null) {
      await _db.into(_db.toothFindings).insert(c);
    } else {
      await (_db.update(
        _db.toothFindings,
      )..where((t) => t.id.equals(existing.id))).write(c);
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<void> _insert({
    required int patientId,
    required String patientUuid,
    required int fdi,
    required ToothKind kind,
    required FindingStatus status,
    required String surfaces,
    required String by,
    String? note,
  }) async {
    final now = DateTime.now();
    final done = status == FindingStatus.done;
    await _db
        .into(_db.toothFindings)
        .insert(
          ToothFindingsCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: await _db.currentClinicId() ?? '',
            patientId: patientId,
            patientUuid: patientUuid,
            fdi: fdi,
            kind: kind.name,
            status: status.name,
            surfaces: Value(surfaces),
            note: Value(note),
            createdByName: Value(by),
            createdAt: Value(now),
            completedByName: done ? Value(by) : const Value.absent(),
            completedAt: done ? Value(now) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
  }

  static ToothFinding? _fromRow(ToothFindingRow r) {
    final kind = ToothKind.values.asNameMap()[r.kind];
    final status = FindingStatus.values.asNameMap()[r.status];
    // A value written by a newer version of DentOS — skip rather than crash.
    if (kind == null || status == null) return null;
    return ToothFinding(
      id: r.id,
      uuid: r.uuid,
      fdi: r.fdi,
      kind: kind,
      status: status,
      surfaces: r.surfaces.split('').where((s) => s.isNotEmpty).toSet(),
      note: r.note,
      createdBy: r.createdByName,
      createdAt: r.createdAt,
      completedBy: r.completedByName,
      completedAt: r.completedAt,
      isDeleted: r.isDeleted,
      deletedBy: r.deletedByName,
      deletedAt: r.deletedAt,
    );
  }
}

final toothChartRepositoryProvider = Provider(
  (ref) => ToothChartRepository(ref.watch(appDatabaseProvider)),
);

final toothFindingsProvider = StreamProvider.autoDispose
    .family<List<ToothFinding>, int>(
      (ref, patientId) =>
          ref.watch(toothChartRepositoryProvider).watch(patientId),
    );
