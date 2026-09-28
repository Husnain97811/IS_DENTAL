import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../domain/permissions.dart';
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
    await _db
        .into(_db.rolePermissions)
        .insertOnConflictUpdate(
          RolePermissionsCompanion.insert(
            clinicId: clinicId,
            role: role.name,
            key: key,
            allowed: Value(allowed),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Write the defaults once, so the settings screen reflects reality.
  Future<void> seedIfEmpty() async {
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
