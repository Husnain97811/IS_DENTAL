import 'dart:convert';

import '../../core/db/app_database.dart';
import '../domain/license.dart';

/// "Payment overdue — view only", ticked by Inover Studio in the licence
/// tool. Everything can still be opened and printed; only NEW appointments,
/// patients and invoices are refused — right where they are saved, so no
/// screen (editor, quick add, patient-app approval…) can slip past it.
/// Changes to existing records, payments, cancellations and sync carry on.
class ViewOnlyException implements Exception {
  const ViewOnlyException();

  @override
  String toString() =>
      'Payment overdue — this clinic is view only. New appointments, '
      'patients and invoices are paused until the subscription is renewed. '
      'Please contact Inover Studio.';
}

/// True when the licence on this computer has the "view only" tick.
/// Reads the stored licence (already signature-checked when it was saved).
Future<bool> isViewOnly(AppDatabase db) async {
  final s = await db.getSetting('license_blob');
  if (s == null || s.isEmpty) return false;
  try {
    final j = jsonDecode(s);
    final f = j is Map ? j['features'] : null;
    return f is List && f.contains(LicenseFeature.viewOnly);
  } catch (_) {
    return false;
  }
}

/// Throws [ViewOnlyException] while the clinic is view only.
Future<void> ensureNotViewOnly(AppDatabase db) async {
  if (await isViewOnly(db)) throw const ViewOnlyException();
}
