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
  Future<({String status, DateTime? expiresAt})?> subscription(
    String clinicId,
  ) async {
    try {
      final row = await _sb
          .from('clinics')
          .select('status, expires_at')
          .eq('id', clinicId)
          .maybeSingle();
      if (row == null) return (status: 'suspended', expiresAt: null);
      return (
        status: row['status'] as String? ?? 'suspended',
        expiresAt: row['expires_at'] == null
            ? null
            : DateTime.parse(row['expires_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

final cloudServiceProvider = Provider(
  (ref) => CloudService(ref.watch(appDatabaseProvider)),
);
