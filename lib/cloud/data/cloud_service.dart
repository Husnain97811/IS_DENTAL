import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';

class CloudService {
  final SupabaseClient _sb = Supabase.instance.client;

  Future<bool> ensureSignedIn() async {
    if (_sb.auth.currentSession != null) return true;
    try {
      await _sb.auth.signInWithPassword(
        email: Env.supabaseEmail,
        password: Env.supabasePassword,
      );
      return _sb.auth.currentSession != null;
    } catch (_) {
      return false; // offline or bad creds
    }
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

final cloudServiceProvider = Provider((ref) => CloudService());
