import 'package:supabase_flutter/supabase_flutter.dart';

class WaConnectService {
  SupabaseClient get _sb => Supabase.instance.client;

  /// Start a connect session; returns the QR (data URL) + status.
  Future<({String? qr, String status, String? error})> connect(
    String branchId,
  ) async {
    try {
      final res = await _sb.functions.invoke(
        'wa-connect',
        body: {'branchId': branchId},
      );
      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['ok'] != true) {
        return (
          qr: null,
          status: 'error',
          error: data?['error']?.toString() ?? 'Failed',
        );
      }
      return (
        qr: data['qr'] as String?,
        status: (data['status'] ?? 'connecting').toString(),
        error: null,
      );
    } catch (e) {
      return (qr: null, status: 'error', error: e.toString());
    }
  }

  /// Poll status; returns current status + fresh QR if still connecting.
  Future<({String? qr, String status})> status(String branchId) async {
    try {
      final res = await _sb.functions.invoke(
        'wa-status',
        body: {'branchId': branchId},
      );
      final data = res.data as Map<String, dynamic>?;
      return (
        qr: data?['qr'] as String?,
        status: (data?['status'] ?? 'disconnected').toString(),
      );
    } catch (_) {
      return (qr: null, status: 'disconnected');
    }
  }

  Future<void> disconnect(String branchId) async {
    try {
      await _sb.functions.invoke('wa-disconnect', body: {'branchId': branchId});
    } catch (_) {}
  }
}
