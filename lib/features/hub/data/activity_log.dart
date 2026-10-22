import 'package:drift/drift.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/core/utils/uuids.dart';

/// Adds one line to the synced activity record (`activity_events`).
///
/// Pass [session] for something a signed-in user did, or [userName] for
/// a name typed at sign-in. Never throws — a failed log line must never
/// stop the work it describes.
Future<void> logActivity(
  AppDatabase db,
  String kind, {
  AuthSession? session,
  String? userName,
  String detail = '',
}) async {
  try {
    final clinicId = await db.currentClinicId() ?? '';
    final dev = await db.localDevice();
    final u = session == null
        ? null
        : await db.findActiveUser(session.username);
    await db
        .into(db.activityEvents)
        .insert(
          ActivityEventsCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId,
            kind: kind,
            branchId: Value(session?.branchId ?? ''),
            userUuid: Value(u?.uuid ?? ''),
            userName: Value(session?.fullName ?? userName ?? ''),
            device: Value(dev.letter),
            detail: Value(detail),
          ),
        );
  } catch (_) {}
}
