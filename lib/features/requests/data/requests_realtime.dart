import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/app_database.dart';

/// Subscribes to Supabase Realtime on `booking_requests` for this clinic and
/// mirrors inserts/updates into the local Drift table. The dashboard card and
/// requests screen watch the local table, so they update live — no manual sync.
class RequestsRealtime {
  RequestsRealtime(this._db);
  final AppDatabase _db;
  RealtimeChannel? _channel;

  SupabaseClient get _sb => Supabase.instance.client;

  Future<void> start(String clinicId) async {
    if (_channel != null) return; // already subscribed
    _channel = _sb
        .channel('booking_requests:$clinicId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'clinic_id',
            value: clinicId,
          ),
          callback: (payload) => _apply(payload.newRecord, clinicId),
        )
        .subscribe();
    debugPrint('REALTIME: subscribed booking_requests for $clinicId');
  }

  Future<void> stop() async {
    if (_channel != null) {
      await _sb.removeChannel(_channel!);
      _channel = null;
      debugPrint('REALTIME: unsubscribed booking_requests');
    }
  }

  Future<void> _apply(Map<String, dynamic> r, String clinicId) async {
    final rid = r['id']; // Supabase PK is `id` (uuid type), not `uuid`
    if (r.isEmpty || rid == null) return;
    try {
      final u = r['updated_at'] != null
          ? DateTime.parse(r['updated_at'])
          : DateTime.now();
      final existing = await (_db.select(
        _db.bookingRequests,
      )..where((t) => t.uuid.equals(rid))).getSingleOrNull();
      // don't clobber a newer local change (e.g. we just approved it)
      if (existing != null && !u.isAfter(existing.updatedAt)) return;

      await _db
          .into(_db.bookingRequests)
          .insertOnConflictUpdate(
            BookingRequestsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(rid),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              patientUuid: Value(r['patient_uuid'] ?? ''),
              patientAccountId: Value(r['patient_account_id']),
              dentist: Value(r['dentist'] ?? ''),
              procedure: Value(r['procedure'] ?? ''),
              requestedSlot: Value(DateTime.parse(r['requested_slot'])),
              durationMin: Value(r['duration_min'] ?? 30),
              status: Value(r['status'] ?? 'pending'),
              modifiedBy: Value(r['modified_by']),
              acceptedBy: Value(r['accepted_by']),
              decidedAt: Value(
                r['decided_at'] == null
                    ? null
                    : DateTime.parse(r['decided_at']),
              ),
              updatedAt: Value(u),
            ),
          );
      debugPrint('REALTIME: applied request ${r['uuid']} (${r['status']})');
    } catch (e) {
      debugPrint('REALTIME apply failed: $e');
    }
  }
}

final requestsRealtimeProvider = Provider<RequestsRealtime>(
  (ref) => RequestsRealtime(ref.watch(appDatabaseProvider)),
);
