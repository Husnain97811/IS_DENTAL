import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient, FileOptions;
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/prescriptions/data/prescription_pdf.dart';
import 'package:is_dental/features/prescriptions/presentation/widgets/prescription_preview.dart';

/// WhatsApp queue (Supabase `wa_outbox`). The desktop app only adds rows and
/// reads them back; the `wa-dispatch` edge function does the actual sending
/// with safe gaps, the 8 am–8 pm window, a daily cap and STOP opt-outs.

SupabaseClient get _sb => Supabase.instance.client;

/// Same rule as normalizePhone() in the edge functions, so opt-out keys match.
String waNormalizePhone(String raw) {
  var p = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (p.startsWith('0')) p = '92${p.substring(1)}';
  return p;
}

// ─────────── per-branch settings ───────────
class WaBranchSettings {
  const WaBranchSettings({
    this.rxAuto = true,
    this.summaryPhone = '',
    this.dailyCap = 150,
  });
  final bool rxAuto;
  final String summaryPhone;
  final int dailyCap;

  factory WaBranchSettings.fromRow(Map<String, dynamic>? r) => r == null
      ? const WaBranchSettings()
      : WaBranchSettings(
          rxAuto: r['rx_auto'] as bool? ?? true,
          summaryPhone: (r['summary_phone'] as String?) ?? '',
          dailyCap: (r['daily_cap'] as num?)?.toInt() ?? 150,
        );
}

final waBranchSettingsProvider = FutureProvider.autoDispose
    .family<WaBranchSettings, String>((ref, branchUuid) async {
      final r = await _sb
          .from('wa_branch_settings')
          .select()
          .eq('branch_id', branchUuid)
          .maybeSingle();
      return WaBranchSettings.fromRow(r);
    });

Future<void> saveWaBranchSettings({
  required String clinicId,
  required String branchUuid,
  required bool rxAuto,
  required String summaryPhone,
}) async {
  final phone = summaryPhone.trim().isEmpty
      ? ''
      : waNormalizePhone(summaryPhone);
  await _sb.from('wa_branch_settings').upsert({
    'branch_id': branchUuid,
    'clinic_id': clinicId,
    'rx_auto': rxAuto,
    'summary_phone': phone,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  }, onConflict: 'branch_id');
}

// ─────────── send log ───────────
class WaLogEntry {
  const WaLogEntry({
    required this.id,
    required this.kind,
    required this.status,
    required this.patientName,
    required this.phone,
    required this.lastError,
    required this.attempts,
    required this.createdAt,
    this.notBefore,
    this.sentAt,
  });
  final int id;
  final String kind, status, patientName, phone, lastError;
  final int attempts;
  final DateTime createdAt;
  final DateTime? notBefore, sentAt;

  static DateTime? _t(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  factory WaLogEntry.fromRow(Map<String, dynamic> r) => WaLogEntry(
    id: (r['id'] as num).toInt(),
    kind: (r['kind'] as String?) ?? '',
    status: (r['status'] as String?) ?? '',
    patientName: (r['patient_name'] as String?) ?? '',
    phone: (r['phone'] as String?) ?? '',
    lastError: (r['last_error'] as String?) ?? '',
    attempts: (r['attempts'] as num?)?.toInt() ?? 0,
    createdAt: _t(r['created_at']) ?? DateTime.now(),
    notBefore: _t(r['not_before']),
    sentAt: _t(r['sent_at']),
  );

  bool get isWaiting => status == 'pending' || status == 'sending';

  String get kindLabel => switch (kind) {
    '24h' => 'Reminder · day before',
    '2h' => 'Reminder · 2 hours',
    'post' => 'Follow-up',
    'rx' => 'Prescription',
    'photo' => 'Before & after',
    'summary' => 'Weekly summary',
    _ => kind,
  };

  String get statusLabel => switch (status) {
    'sent' => 'Sent',
    'pending' => 'Waiting',
    'sending' => 'Sending',
    'failed' => 'Failed',
    'skipped' => 'Not sent',
    'cancelled' => 'Cancelled',
    _ => status,
  };
}

const _logCols =
    'id, kind, status, patient_name, phone, not_before, sent_at, created_at, last_error, attempts';

/// autoDispose: fetched fresh every time the log is opened.
final waLogProvider = FutureProvider.autoDispose
    .family<List<WaLogEntry>, String>((ref, branchUuid) async {
      final rows = await _sb
          .from('wa_outbox')
          .select(_logCols)
          .eq('branch_id', branchUuid)
          .order('created_at', ascending: false)
          .limit(80);
      return [for (final r in rows) WaLogEntry.fromRow(r)];
    });

/// Latest WhatsApp row for one prescription (null = never sent).
/// autoDispose: fetched fresh every time a prescription is opened, so the
/// status is never an old one from earlier in the day.
final rxWaStatusProvider = FutureProvider.autoDispose
    .family<WaLogEntry?, String>((ref, rxUuid) async {
      final rows = await _sb
          .from('wa_outbox')
          .select(_logCols)
          .eq('kind', 'rx')
          .like('ref', 'rx:$rxUuid:%')
          .order('created_at', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : WaLogEntry.fromRow(rows.first);
    });

/// Put a failed message back in the queue.
Future<void> retryWaMessage(int id) => _sb
    .from('wa_outbox')
    .update({
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'not_before': DateTime.now().toUtc().toIso8601String(),
    })
    .eq('id', id)
    .eq('status', 'failed');

/// Stop a message that hasn't gone yet.
Future<void> cancelWaMessage(int id) => _sb
    .from('wa_outbox')
    .update({'status': 'cancelled', 'last_error': 'cancelled by staff'})
    .eq('id', id)
    .eq('status', 'pending');

// ─────────── prescription → WhatsApp ───────────
enum RxWaResult { queued, autoOff, notConnected, noPhone, offline, failed }

/// Snackbar text for a result, or null when nothing should be shown
/// (auto-send off / WhatsApp not set up — silent on save).
String? rxWaMessage(RxWaResult r, {bool manual = false}) => switch (r) {
  RxWaResult.queued => 'Prescription will be sent on WhatsApp.',
  RxWaResult.noPhone =>
    'Not sent on WhatsApp — this patient has no phone number.',
  RxWaResult.offline =>
    'No internet — the prescription will go on WhatsApp automatically once the internet is back.',
  RxWaResult.failed => 'Could not send the prescription on WhatsApp.',
  RxWaResult.notConnected =>
    manual
        ? 'WhatsApp (QR) is not connected or turned off for this branch.'
        : null,
  RxWaResult.autoOff => null,
};

/// Builds the same PDF as Print / Save PDF, uploads it and queues it.
/// [manual] = the Send / Resend button (ignores the auto-send switch and
/// creates a new message instead of the once-only automatic one).
///
/// No internet? The prescription is remembered on THIS computer and sent
/// automatically when the internet is back (checked every 2 minutes, for up
/// to 24 hours). Retrying can never send it twice: each send has a fixed
/// de-duplication key, so a retry of one that actually got through is
/// ignored by the server.
Future<RxWaResult> queuePrescriptionOnWhatsApp(
  ProviderContainer c,
  Prescription rx, {
  bool manual = false,
  String byName = '',
}) async {
  // not on this plan — nothing is uploaded or remembered for later
  if (!c.read(entitlementsProvider).rxOnWhatsapp) {
    return RxWaResult.notConnected;
  }
  final db = c.read(appDatabaseProvider);
  List<Map<String, dynamic>> pending = const [];
  try {
    pending = await _readPending(db);
  } catch (_) {}
  Map<String, dynamic>? mine;
  for (final e in pending) {
    if (e['id'] == rx.id) mine = e;
  }
  // same key on every retry of the same send → never a duplicate message
  final key = manual
      ? (mine?['key'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}')
      : 'auto';

  final r = await _queueRx(c, rx, manual: manual, byName: byName, key: key);

  try {
    final list = await _readPending(db);
    final had = list.any((e) => e['id'] == rx.id);
    if (r == RxWaResult.offline) {
      if (!had) {
        list.add({
          'id': rx.id,
          'at': DateTime.now().millisecondsSinceEpoch,
          'by': byName,
          'manual': manual,
          'key': key,
        });
        await _writePending(db, list);
      }
      _startRetryTimer(c);
    } else if (had) {
      list.removeWhere((e) => e['id'] == rx.id);
      await _writePending(db, list);
    }
    // the internet is back — send whatever else was waiting
    if (r == RxWaResult.queued) unawaited(_flushPending(c));
  } catch (_) {}
  return r;
}

Future<RxWaResult> _queueRx(
  ProviderContainer c,
  Prescription rx, {
  required bool manual,
  required String byName,
  required String key,
}) async {
  try {
    final db = c.read(appDatabaseProvider);
    final clinicId = await db.currentClinicId() ?? '';
    final row = await (db.select(
      db.prescriptions,
    )..where((t) => t.id.equals(rx.id))).getSingleOrNull();
    final branchUuid = row?.branchId ?? await db.currentBranchId() ?? '';
    if (clinicId.isEmpty || branchUuid.isEmpty) return RxWaResult.notConnected;

    // listen (not read) so the stream stays alive until it has a value
    final sub = c.listen(branchesStreamProvider.future, (_, __) {});
    final List<Branch> branches;
    try {
      branches = await sub.read().timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
    Branch? b;
    for (final x in branches) {
      if (x.uuid == branchUuid) b = x;
    }
    if (b == null || !b.waEnabled || !b.qrConnected) {
      return RxWaResult.notConnected;
    }

    if (!manual) {
      // asked fresh every time (not a cached provider) so a failed check
      // while offline doesn't stick
      final s = await _sb
          .from('wa_branch_settings')
          .select('rx_auto')
          .eq('branch_id', branchUuid)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (s != null && s['rx_auto'] == false) return RxWaResult.autoOff;
    }

    final p = await (db.select(
      db.patients,
    )..where((t) => t.id.equals(rx.patientId))).getSingleOrNull();
    final phone = waNormalizePhone(p?.phone ?? '');
    if (phone.length < 10) return RxWaResult.noPhone;

    final data = await buildRxDataFrom(db, rx);
    if (data == null) return RxWaResult.failed;
    final bytes = await PrescriptionPdf.build(data);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$clinicId/rx/${rx.uuid}_$stamp.pdf';
    await _sb.storage
        .from('wa-media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        )
        .timeout(const Duration(seconds: 30));

    final fullName = (p?.fullName ?? '').trim();
    final first = fullName.isEmpty ? '' : fullName.split(RegExp(r'\s+')).first;
    final now = DateTime.now().toUtc();
    await _sb
        .from('wa_outbox')
        .upsert(
          {
            'clinic_id': clinicId,
            'branch_id': branchUuid,
            'kind': 'rx',
            'priority': 0,
            'phone': phone,
            'media_path': path,
            'file_name': 'Prescription_${rx.rxNo}.pdf'.replaceAll(' ', '_'),
            'meta': {'rx_no': rx.rxNo, 'rx_uuid': rx.uuid, 'first_name': first},
            // auto-send happens once per prescription; each Resend is its
            // own message — and a retry of the same send reuses its key
            'ref': 'rx:${rx.uuid}:$key',
            'patient_uuid': rx.patientUuid,
            'patient_name': fullName,
            'not_before': now.toIso8601String(),
            'expires_at': now.add(const Duration(days: 2)).toIso8601String(),
            'created_by_name': byName,
          },
          onConflict: 'ref',
          ignoreDuplicates: true,
        )
        .timeout(const Duration(seconds: 15));
    return RxWaResult.queued;
  } on TimeoutException {
    return RxWaResult.offline;
  } catch (e) {
    final s = '$e'.toLowerCase();
    if (s.contains('socket') ||
        s.contains('host lookup') ||
        s.contains('clientexception') ||
        s.contains('connection')) {
      return RxWaResult.offline;
    }
    debugPrint('WA rx queue failed: $e');
    return RxWaResult.failed;
  }
}

// ─────────── waiting for internet ───────────
const _kRxPending = 'wa_rx_pending';
const _retryEvery = Duration(minutes: 2);
const _giveUpAfter = Duration(hours: 24);
Timer? _retryTimer;
bool _flushing = false;
DateTime? _lastKick;

Future<List<Map<String, dynamic>>> _readPending(AppDatabase db) async {
  final raw = await db.getSetting(_kRxPending);
  if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
  try {
    return [
      for (final e in jsonDecode(raw) as List)
        (e as Map).cast<String, dynamic>(),
    ];
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

Future<void> _writePending(AppDatabase db, List<Map<String, dynamic>> l) =>
    db.setSetting(_kRxPending, jsonEncode(l));

void _startRetryTimer(ProviderContainer c) {
  _retryTimer ??= Timer.periodic(_retryEvery, (_) => _flushPending(c));
}

/// Call once at app start (cheap and safe to call again — it checks at most
/// every 2 minutes). If prescriptions were left waiting for internet when
/// DentOS was closed, they are sent now.
void resumePendingWhatsApp(ProviderContainer c) {
  final now = DateTime.now();
  if (_retryTimer != null ||
      (_lastKick != null && now.difference(_lastKick!) < _retryEvery)) {
    return;
  }
  _lastKick = now;
  unawaited(_flushPending(c));
}

/// Is this prescription waiting for internet on this computer?
final rxWaPendingProvider = FutureProvider.autoDispose.family<bool, int>(
  (ref, rxId) async => (await _readPending(
    ref.read(appDatabaseProvider),
  )).any((e) => e['id'] == rxId),
);

Future<void> _flushPending(ProviderContainer c) async {
  if (_flushing) return;
  _flushing = true;
  try {
    final db = c.read(appDatabaseProvider);
    final list = await _readPending(db);
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _giveUpAfter.inMilliseconds;
    final before = list.length;
    list.removeWhere((e) => ((e['at'] as num?) ?? 0) < cutoff);
    if (list.length != before) await _writePending(db, list);
    if (list.isEmpty) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    _startRetryTimer(c);

    for (final e in List.of(list)) {
      final id = (e['id'] as num).toInt();
      final rx = await c.read(prescriptionRepositoryProvider).byId(id);
      if (rx == null) {
        final now = await _readPending(db);
        now.removeWhere((x) => x['id'] == id);
        await _writePending(db, now);
        continue;
      }
      final r = await queuePrescriptionOnWhatsApp(
        c,
        rx,
        manual: e['manual'] == true,
        byName: (e['by'] as String?) ?? '',
      );
      if (r == RxWaResult.offline) break; // still offline — next round
    }
  } catch (e) {
    debugPrint('WA pending retry: $e');
  } finally {
    _flushing = false;
  }
}

// ─────────── before & after picture → WhatsApp ───────────

/// Snackbar text for sending a before/after picture (always a button press).
String photoWaMessage(RxWaResult r) => switch (r) {
  RxWaResult.queued => 'Before & after picture will be sent on WhatsApp.',
  RxWaResult.noPhone => 'Not sent — this patient has no phone number.',
  RxWaResult.offline => 'Not sent — no internet. Try again when online.',
  RxWaResult.notConnected =>
    'WhatsApp (QR) is not connected or turned off for this branch.',
  _ => 'Could not send the picture on WhatsApp.',
};

/// Uploads a before/after picture and queues it for the patient.
/// [caseId] keeps one case's sends together in the log.
Future<RxWaResult> queueImageOnWhatsApp(
  ProviderContainer c, {
  required int patientId,
  required String patientUuid,
  required String? branchUuid,
  required String caseId,
  required Uint8List png,
  required String fileName,
  required String treatment,
  String byName = '',
}) async {
  try {
    final db = c.read(appDatabaseProvider);
    final clinicId = await db.currentClinicId() ?? '';
    final branch = branchUuid ?? await db.currentBranchId() ?? '';
    if (clinicId.isEmpty || branch.isEmpty) return RxWaResult.notConnected;

    final sub = c.listen(branchesStreamProvider.future, (_, __) {});
    final List<Branch> branches;
    try {
      branches = await sub.read().timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
    Branch? b;
    for (final x in branches) {
      if (x.uuid == branch) b = x;
    }
    if (b == null || !b.waEnabled || !b.qrConnected) {
      return RxWaResult.notConnected;
    }

    final p = await (db.select(
      db.patients,
    )..where((t) => t.id.equals(patientId))).getSingleOrNull();
    final phone = waNormalizePhone(p?.phone ?? '');
    if (phone.length < 10) return RxWaResult.noPhone;

    final fullName = (p?.fullName ?? '').trim();
    final first = fullName.isEmpty ? '' : fullName.split(RegExp(r'\s+')).first;
    final clinic = (await db.clinicName()) ?? '';
    final what = treatment.trim().isEmpty ? '' : treatment.trim().toLowerCase();
    final n = first.isEmpty ? '' : ' $first';
    final caption = b.waLanguage == 'ur'
        ? 'Assalam o Alaikum$n,\n'
              '${what.isEmpty ? 'Aap ke ilaaj' : 'Aap ke $what'} ka pehle aur baad ka muqabla saath hai.'
              '\n\nShukriya\n$clinic'
        : 'Hello$n,\n'
              'Here is your before & after${what.isEmpty ? '' : ' for $what'}. '
              'Thank you for choosing $clinic.'
              '\n\nRegards,\n$clinic';

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$clinicId/photo/${caseId}_$stamp.png';
    await _sb.storage
        .from('wa-media')
        .uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        )
        .timeout(const Duration(seconds: 40));

    final now = DateTime.now().toUtc();
    await _sb
        .from('wa_outbox')
        .upsert(
          {
            'clinic_id': clinicId,
            'branch_id': branch,
            'kind': 'photo',
            'priority': 0,
            'phone': phone,
            'body': caption,
            'media_path': path,
            'file_name': fileName,
            'meta': {'mime': 'image/png', 'case': caseId},
            'ref': 'photo:$caseId:$stamp',
            'patient_uuid': patientUuid,
            'patient_name': fullName,
            'not_before': now.toIso8601String(),
            'expires_at': now.add(const Duration(days: 2)).toIso8601String(),
            'created_by_name': byName,
          },
          onConflict: 'ref',
          ignoreDuplicates: true,
        )
        .timeout(const Duration(seconds: 15));
    return RxWaResult.queued;
  } on TimeoutException {
    return RxWaResult.offline;
  } catch (e) {
    final s = '$e'.toLowerCase();
    if (s.contains('socket') ||
        s.contains('host lookup') ||
        s.contains('clientexception') ||
        s.contains('connection')) {
      return RxWaResult.offline;
    }
    debugPrint('WA photo queue failed: $e');
    return RxWaResult.failed;
  }
}
