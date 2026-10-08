import 'package:drift/drift.dart';
import '../../../core/constants/views.dart';

class PermissionRepository {
  PermissionRepository(this._db);
  final AppDatabase _db;

  /// Every stored override, keyed "role|key".
  Stream<Map<String, bool>> watchAll() => _db
      .select(_db.rolePermissions)
      .watch()
      .map((rows) => {for (final r in rows) '${r.role}|${r.key}': r.allowed});

  Future<void> set({
    required AppRole role,
    required String key,
    required bool allowed,
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    final existing =
        await (_db.select(_db.rolePermissions)
              ..where((t) => t.role.equals(role.name) & t.key.equals(key)))
            .getSingleOrNull();

    if (existing == null) {
      await _db
          .into(_db.rolePermissions)
          .insert(
            RolePermissionsCompanion.insert(
              clinicId: clinicId,
              role: role.name,
              key: key,
              allowed: Value(allowed),
            ),
          );
    } else {
      await (_db.update(
        _db.rolePermissions,
      )..where((t) => t.id.equals(existing.id))).write(
        RolePermissionsCompanion(
          allowed: Value(allowed),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Write the defaults once, so the settings screen reflects reality.
  Future<void> seedIfEmpty() async {
    // A joined or restored install must never write defaults: its tables are
    // empty because the data has not arrived, and defaults would push up with
    // today's timestamp and beat the owner's real matrix everywhere.
    if (!await _db.seedAllowed()) return;
    if ((await _db.select(_db.rolePermissions).get()).isNotEmpty) return;
    for (final role in const [
      AppRole.admin,
      AppRole.clinician,
      AppRole.receptionist,
    ]) {
      for (final key in Perm.all) {
        await set(role: role, key: key, allowed: defaultFor(role, key));
      }
    }
  }
}
