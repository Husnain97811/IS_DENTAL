import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';
import '../../core/constants/views.dart';

class CloudService {
  CloudService(this._db); // add this
  final AppDatabase _db;
  SupabaseClient get _sb => Supabase.instance.client;

  Future<void> ensureSignedIn() async {
    final sb = Supabase.instance.client;
    if (sb.auth.currentSession != null)
      return; // session persists after registration
    final email = await _db.getSetting('cloud_email') ?? '';
    final password = await _db.getSetting('cloud_password') ?? '';
    if (email.isEmpty || password.isEmpty)
      throw Exception('Cloud account not set up yet.');
    await sb.auth.signInWithPassword(email: email, password: password);
  }

  /// null = unreachable; otherwise the server's view of the subscription.
  /// null = unreachable; otherwise the server's view of the subscription.
  /// [note] carries the diagnostic detail the locked screen shows to support.
  Future<({String status, DateTime? expiresAt, String note})?> subscription(
    String clinicId,
  ) async {
    try {
      final row = await _sb
          .from('clinics')
          .select('status, expires_at')
          .eq('id', clinicId)
          .maybeSingle();

      // A row we cannot READ is not a cancelled subscription. It usually
      // means RLS hid it, or the licence's clinic id matches no row at all.
      // Returning null reports "unreachable", so the grace window applies
      // instead of an instant lock. A clinic you genuinely want to cut off
      // gets status='suspended' in the row, which reads fine and still locks.
      if (row == null) return null;

      return (
        status: row['status'] as String? ?? 'suspended',
        expiresAt: row['expires_at'] == null
            ? null
            : DateTime.parse(row['expires_at'] as String),
        note: 'row read ok',
      );
    } catch (e) {
      return null;
    }
  }

  /// Support-only probe. Says exactly why the heartbeat is failing —
  /// shown on the locked screen so you never have to guess again.
  Future<String> diagnose(String clinicId) async {
    final out = StringBuffer();
    try {
      await ensureSignedIn();
      final uid = _sb.auth.currentUser;
      out.write('signed in as ${uid?.email ?? "?"}; ');
      final meta = uid?.appMetadata['clinic_id'];
      out.write('token clinic=${meta ?? "MISSING"}; ');
      out.write('licence clinic=$clinicId; ');
      if (meta != null && meta != clinicId) {
        out.write('MISMATCH — RLS will hide the row. ');
      }
      final row = await _sb
          .from('clinics')
          .select('status, expires_at')
          .eq('id', clinicId)
          .maybeSingle();
      out.write(
        row == null
            ? 'no clinics row readable for this id.'
            : 'row: status=${row['status']} expires=${row['expires_at']}',
      );
    } catch (e) {
      out.write('ERROR $e');
    }
    return out.toString();
  }
}

final cloudServiceProvider = Provider(
  (ref) => CloudService(ref.watch(appDatabaseProvider)),
);
