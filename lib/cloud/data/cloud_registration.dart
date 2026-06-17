import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudRegistration {
  Future<({bool ok, String? error})> register({
    required Map<String, dynamic> license,
    required String email,
    required String password,
  }) async {
    final sb = Supabase.instance.client;
    try {
      final res = await sb.functions.invoke(
        'register-clinic',
        body: {'license': license, 'email': email, 'password': password},
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        await sb.auth.signInWithPassword(
          email: email,
          password: password,
        ); // session persists
        return (ok: true, error: null);
      }
      return (
        ok: false,
        error:
            (data is Map ? data['error']?.toString() : null) ??
            'Registration failed.',
      );
    } on FunctionException catch (e) {
      final d = e.details;
      return (
        ok: false,
        error:
            (d is Map ? d['error']?.toString() : null) ??
            'Registration failed (${e.status}).',
      );
    } catch (e) {
      return (ok: false, error: '$e');
    }
  }
}

final cloudRegistrationProvider = Provider((ref) => CloudRegistration());
