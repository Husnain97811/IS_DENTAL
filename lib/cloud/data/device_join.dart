import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Redeeming a join code gives this computer its OWN cloud account and its
/// device letter. The owner's password never travels to another machine.
class DeviceJoin {
  Future<
    ({
      bool ok,
      String? error,
      String? email,
      String? password,
      String? letter,
      String? clinicName,
    })
  >
  redeem({
    required Map<String, dynamic> license,
    required String code,
    required String deviceName,
  }) async {
    final sb = Supabase.instance.client;
    try {
      final res = await sb.functions.invoke(
        'redeem-join-code',
        body: {'license': license, 'code': code, 'deviceName': deviceName},
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return (
          ok: true,
          error: null,
          email: data['email']?.toString(),
          password: data['password']?.toString(),
          letter: data['letter']?.toString(),
          clinicName: data['clinicName']?.toString(),
        );
      }
      return (
        ok: false,
        error:
            (data is Map ? data['error']?.toString() : null) ??
            'That code could not be used.',
        email: null,
        password: null,
        letter: null,
        clinicName: null,
      );
    } on FunctionException catch (e) {
      final d = e.details;
      return (
        ok: false,
        error:
            (d is Map ? d['error']?.toString() : null) ??
            'Join failed (${e.status}).',
        email: null,
        password: null,
        letter: null,
        clinicName: null,
      );
    } catch (e) {
      return (
        ok: false,
        error: '$e',
        email: null,
        password: null,
        letter: null,
        clinicName: null,
      );
    }
  }

  /// Exchanges a vendor-issued recovery code for a NEW cloud password on the
  /// clinic's account. Returns the account email so the caller can sign in.
  Future<({bool ok, String? error, String? email})> redeemRecovery({
    required Map<String, dynamic> license,
    required String token,
    required String newPassword,
  }) async {
    final sb = Supabase.instance.client;
    try {
      final res = await sb.functions.invoke(
        'redeem-recovery-code',
        body: {'license': license, 'token': token, 'newPassword': newPassword},
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return (ok: true, error: null, email: data['email']?.toString());
      }
      return (
        ok: false,
        error:
            (data is Map ? data['error']?.toString() : null) ??
            'That recovery code could not be used.',
        email: null,
      );
    } on FunctionException catch (e) {
      final d = e.details;
      return (
        ok: false,
        error:
            (d is Map ? d['error']?.toString() : null) ??
            'Recovery failed (${e.status}).',
        email: null,
      );
    } catch (e) {
      return (ok: false, error: '$e', email: null);
    }
  }

  /// Signs in with the owner's cloud credentials for the RECOVER path,
  /// then checks the account really belongs to this licence's clinic.
  Future<({bool ok, String? error})> signInAsOwner({
    required String email,
    required String password,
    required String clinicId,
  }) async {
    final sb = Supabase.instance.client;
    try {
      final res = await sb.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final meta = res.user?.appMetadata['clinic_id'];
      if (meta != null && meta != clinicId) {
        await sb.auth.signOut();
        return (
          ok: false,
          error: 'That account belongs to a different clinic.',
        );
      }
      return (ok: true, error: null);
    } on AuthException catch (e) {
      return (ok: false, error: e.message);
    } catch (e) {
      return (ok: false, error: '$e');
    }
  }
}

final deviceJoinProvider = Provider((ref) => DeviceJoin());
