import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/offer.dart';

class OfferRepository {
  OfferRepository(this._db);
  final AppDatabase _db;
  SupabaseClient get _sb => Supabase.instance.client;

  /// All offers for the clinic (branch-filtered if a branch is active).
  Stream<List<Offer>> watchOffers({String? branchId}) {
    final q = _db.select(_db.offers)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            (branchId == null
                ? const Constant(true)
                : (t.branchId.equals(branchId) | t.branchId.isNull())),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch().map((rows) => rows.map(_toOffer).toList());
  }

  Offer _toOffer(OfferRow r) => Offer(
    id: r.id,
    uuid: r.uuid,
    branchId: r.branchId,
    title: r.title,
    body: r.body,
    imageUrl: r.imageUrl,
    startsAt: r.startsAt,
    expiresAt: r.expiresAt,
    sentCount: r.sentCount,
    createdBy: r.createdBy,
    createdAt: r.createdAt,
  );

  bool _online() => _sb.auth.currentSession != null;

  /// Creates the offer locally + on Supabase, then calls the send-offer
  /// Edge Function to push it to all clinic patients with the app.
  /// Returns the number of pushes sent (0 if offline or function not ready).
  Future<({bool ok, int sent, String? error})> createAndSend({
    required String title,
    required String body,
    String? imageUrl,
    DateTime? startsAt,
    DateTime? expiresAt,
    String? branchId, // null = all branches
    required String createdBy,
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    final uuid = Uuids.v4();

    // 1. store locally
    await _db
        .into(_db.offers)
        .insert(
          OffersCompanion.insert(
            uuid: uuid,
            clinicId: clinicId,
            branchId: Value(branchId),
            title: title,
            body: body,
            imageUrl: Value(imageUrl),
            startsAt: Value(startsAt),
            expiresAt: Value(expiresAt),
            createdBy: Value(createdBy),
          ),
        );

    if (!_online()) {
      return (ok: false, sent: 0, error: 'No internet connection.');
    }

    // 2. push the offer row to Supabase (so mobile can list it)
    try {
      await _sb.from('offers').upsert({
        'id': uuid,
        'clinic_id': clinicId,
        'branch_id': branchId,
        'title': title,
        'body': body,
        'image_url': imageUrl,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'expires_at': expiresAt?.toUtc().toIso8601String(),
        'created_by': createdBy,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
    } catch (e) {
      return (ok: false, sent: 0, error: 'Could not save offer: $e');
    }

    // 3. call the send-offer Edge Function (fires the pushes)
    try {
      final res = await _sb.functions.invoke(
        'send-offer',
        body: {'offerId': uuid, 'branchId': branchId},
      );
      final data = res.data as Map<String, dynamic>?;
      final sent = (data?['sent'] as num?)?.toInt() ?? 0;
      // record sent_count locally
      await (_db.update(_db.offers)..where((t) => t.uuid.equals(uuid))).write(
        OffersCompanion(sentCount: Value(sent)),
      );
      return (ok: true, sent: sent, error: null);
    } catch (e) {
      // offer is saved; sending failed (e.g. Firebase not set up yet)
      return (ok: false, sent: 0, error: 'Offer saved, but sending failed: $e');
    }
  }

  /// Re-sends an existing offer to all current clinic patients with the app.
  /// Does NOT create a new offer row — reuses the existing one, refreshing
  /// its sent_count. Returns how many pushes went out.
  Future<({bool ok, int sent, String? error})> resend(int localId) async {
    final row = await (_db.select(
      _db.offers,
    )..where((t) => t.id.equals(localId))).getSingleOrNull();
    if (row == null) return (ok: false, sent: 0, error: 'Offer not found.');
    if (!_online())
      return (ok: false, sent: 0, error: 'No internet connection.');

    try {
      final res = await _sb.functions.invoke(
        'send-offer',
        body: {'offerId': row.uuid, 'branchId': row.branchId},
      );
      final data = res.data as Map<String, dynamic>?;
      final sent = (data?['sent'] as num?)?.toInt() ?? 0;
      // refresh sent_count + bump updatedAt locally
      await (_db.update(_db.offers)..where((t) => t.id.equals(localId))).write(
        OffersCompanion(
          sentCount: Value(sent),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (ok: true, sent: sent, error: null);
    } catch (e) {
      return (ok: false, sent: 0, error: 'Could not resend: $e');
    }
  }

  /// How many patients would receive this (have the app / a token).
  /// Calls a lightweight count via the Edge Function or a direct query.
  Future<int> recipientCount({String? branchId}) async {
    if (!_online()) return 0;
    try {
      final clinicId = await _db.currentClinicId() ?? '';
      var q = _sb
          .from('patient_accounts')
          .select('id')
          .eq('clinic_id', clinicId)
          .not('fcm_token', 'is', null);
      if (branchId != null) {
        q = q.or('branch_scope.eq.$branchId,branch_scope.is.null');
      }
      final rows = (await q) as List;
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> deleteOffer(int id) =>
      (_db.update(_db.offers)..where((t) => t.id.equals(id))).write(
        OffersCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
