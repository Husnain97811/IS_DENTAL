import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:is_dental/core/constants/views.dart';

// ═════════════════════════════════════════════════════════════════════
//  Connected phones — the owner's phone, paired with a QR.
//
//  Everything goes through the `owner-pair` Edge Function. This computer
//  never sees the phone's key or the owner number; it only holds the QR
//  secret for the 2 minutes a pairing lasts.
// ═════════════════════════════════════════════════════════════════════

/// One connected phone.
class ConnectedPhone {
  const ConnectedPhone({
    required this.id,
    required this.model,
    required this.platform,
    required this.phoneLast4,
    required this.pairedAt,
    required this.lastSeenAt,
  });

  final String id, model, platform, phoneLast4;
  final DateTime? pairedAt, lastSeenAt;

  bool get isIphone => platform == 'ios';
  String get platformLabel => switch (platform) {
    'ios' => 'iPhone',
    'android' => 'Android',
    'sim' => 'Test simulator',
    _ => 'Phone',
  };

  factory ConnectedPhone.fromJson(Map<String, dynamic> j) => ConnectedPhone(
    id: '${j['id']}',
    model: '${j['model'] ?? ''}'.trim().isEmpty ? 'Phone' : '${j['model']}',
    platform: '${j['platform'] ?? ''}',
    phoneLast4: '${j['phone_last4'] ?? ''}',
    pairedAt: DateTime.tryParse('${j['paired_at'] ?? ''}')?.toLocal(),
    lastSeenAt: DateTime.tryParse('${j['last_seen_at'] ?? ''}')?.toLocal(),
  );
}

/// What the Connected phones panel shows.
class PhonesOverview {
  const PhonesOverview({
    required this.devices,
    required this.max,
    required this.ownerPhoneMasked,
    required this.hasPin,
    required this.onPlan,
    this.planError,
  });

  final List<ConnectedPhone> devices;
  final int max;
  final String ownerPhoneMasked;
  final bool hasPin, onPlan;
  final String? planError;

  bool get full => devices.length >= max;
  bool get hasOwnerPhone => ownerPhoneMasked.isNotEmpty;
}

/// A fresh QR: [s] identifies it, [k] is the one-time secret inside it.
class PairTicket {
  const PairTicket({required this.s, required this.k, required this.expiresAt});
  final String s, k;
  final DateTime expiresAt;

  /// What the QR holds — no clinic name, id or number, only random values.
  String get qrData => 'dentos://pair?v=1&s=$s&k=$k';
}

/// Where a pairing is, as the server sees it.
class PairStatus {
  const PairStatus({
    required this.status,
    required this.expiresIn,
    required this.triesLeft,
    this.model,
    this.platform,
    this.phoneLast4,
    this.pubkey,
  });

  /// waiting · claimed · approved · done · rejected · cancelled · expired · locked
  final String status;
  final int expiresIn, triesLeft;
  final String? model, platform, phoneLast4, pubkey;

  String get platformLabel => switch (platform) {
    'ios' => 'iPhone',
    'android' => 'Android',
    'sim' => 'Test simulator',
    _ => 'Phone',
  };

  factory PairStatus.fromJson(Map<String, dynamic> j) => PairStatus(
    status: '${j['status']}',
    expiresIn: (j['expires_in'] as num?)?.toInt() ?? 0,
    triesLeft: (j['tries_left'] as num?)?.toInt() ?? 3,
    model: j['model'] as String?,
    platform: j['platform'] as String?,
    phoneLast4: j['phone_last4'] as String?,
    pubkey: j['pubkey'] as String?,
  );
}

/// A refusal from the server, in plain words.
class PhoneApiError implements Exception {
  PhoneApiError(this.code, {this.triesLeft, this.until, this.max});

  factory PhoneApiError.from(Map<String, dynamic> m) => PhoneApiError(
    '${m['error'] ?? 'server'}',
    triesLeft: (m['tries_left'] as num?)?.toInt(),
    until: DateTime.tryParse('${m['until'] ?? ''}')?.toLocal(),
    max: (m['max'] as num?)?.toInt(),
  );

  final String code;
  final int? triesLeft, max;
  final DateTime? until;

  String get message => switch (code) {
    'wrong_pin' =>
      triesLeft == null
          ? 'Wrong Hub PIN.'
          : 'Wrong Hub PIN. $triesLeft ${triesLeft == 1 ? 'try' : 'tries'} left.',
    'locked' =>
      until == null
          ? 'Too many wrong PINs. Wait 15 minutes and try again.'
          : 'Too many wrong PINs. Try again after ${_hm(until!)}.',
    'no_pin' =>
      'Set your PIN first (Set PIN, below). It is the same PIN that opens '
          'the Detailed Reporting Hub.',
    'no_phone' => 'Add the owner mobile number first (above).',
    'limit' =>
      '${max ?? 2} phones are already connected. Disconnect one first.',
    'not_on_plan' =>
      "Connecting a phone isn't on this clinic's plan yet (the Owner phone "
          'app or Phone booking add-on). Contact Inover Studio to add it.',
    'expired' => 'The licence has expired. Renew it to connect a phone.',
    'suspended' => "This clinic's subscription is suspended.",
    'bad_number' => 'Enter a Pakistani mobile number, like 0300 1234567.',
    'invalid' => 'This pairing is no longer valid. Please start again.',
    'offline' => 'No internet connection. Connect and try again.',
    'not_signed_in' =>
      "This computer isn't signed in to the clinic cloud. Use Sync now in "
          'Data & Backup, then try again.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => message;
}

String _hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

class OwnerPhonesApi {
  OwnerPhonesApi(this._signIn);

  /// Makes sure this computer is signed in to the clinic's cloud account.
  final Future<void> Function() _signIn;

  static const _fn = 'owner-pair';

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      await _signIn().timeout(const Duration(seconds: 10));
    } catch (_) {
      throw PhoneApiError('not_signed_in');
    }
    try {
      final res = await Supabase.instance.client.functions
          .invoke(_fn, body: body)
          .timeout(const Duration(seconds: 20));
      final data = res.data;
      if (data is! Map) throw PhoneApiError('server');
      final m = Map<String, dynamic>.from(data);
      if (m['ok'] != true) throw PhoneApiError.from(m);
      return m;
    } on PhoneApiError {
      rethrow;
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        throw PhoneApiError.from(Map<String, dynamic>.from(d));
      }
      throw PhoneApiError(e.status == 401 ? 'not_signed_in' : 'server');
    } on TimeoutException {
      throw PhoneApiError('offline');
    } catch (_) {
      throw PhoneApiError('offline');
    }
  }

  Future<PhonesOverview> list() async {
    final m = await _call({'action': 'list'});
    return PhonesOverview(
      devices: [
        for (final d in (m['devices'] as List? ?? const []))
          ConnectedPhone.fromJson(Map<String, dynamic>.from(d as Map)),
      ],
      max: (m['max'] as num?)?.toInt() ?? 2,
      ownerPhoneMasked: '${m['owner_phone_masked'] ?? ''}',
      hasPin: m['has_pin'] == true,
      onPlan: m['on_plan'] == true,
      planError: m['plan_error'] as String?,
    );
  }

  Future<PairTicket> start(String pin, {String by = ''}) async {
    final m = await _call({'action': 'start', 'pin': pin, 'by': by});
    return PairTicket(
      s: '${m['s']}',
      k: '${m['k']}',
      expiresAt:
          DateTime.tryParse('${m['expires_at']}')?.toLocal() ??
          DateTime.now().add(const Duration(minutes: 2)),
    );
  }

  Future<PairStatus> status(PairTicket t) async => PairStatus.fromJson(
    await _call({'action': 'status', 's': t.s, 'k': t.k}),
  );

  Future<void> approve(PairTicket t) =>
      _call({'action': 'approve', 's': t.s, 'k': t.k});

  Future<void> reject(PairTicket t) =>
      _call({'action': 'reject', 's': t.s, 'k': t.k});

  /// Fire and forget — closing the dialog kills the QR on the server too.
  void cancel(PairTicket t) {
    unawaited(
      _call({
        'action': 'cancel',
        's': t.s,
        'k': t.k,
      }).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  Future<void> revoke(String deviceId, String pin) =>
      _call({'action': 'revoke', 'device_id': deviceId, 'pin': pin});

  Future<String> setOwnerPhone(String phone, String pin) async {
    final m = await _call({'action': 'set_phone', 'phone': phone, 'pin': pin});
    return '${m['owner_phone_masked'] ?? ''}';
  }

  /// The PIN was right on THIS computer but the cloud disagreed — usually a
  /// PIN set or changed here that hasn't synced yet. Sends the PIN hash up
  /// (never the digits) and tries [call] once more. Only overwrites an older
  /// cloud PIN, never a newer one set on another computer.
  Future<T> retryAfterPinSync<T>(User owner, Future<T> Function() call) async {
    try {
      return await call();
    } on PhoneApiError catch (e) {
      if (e.code != 'wrong_pin' && e.code != 'no_pin') rethrow;
      if (!await pushPin(owner)) rethrow;
      return await call();
    }
  }

  /// Sends [u]'s PIN hash (never the digits) to the cloud. Only overwrites
  /// an older cloud PIN, never a newer one set on another computer.
  Future<bool> pushPin(User u) async {
    final hash = u.hubPinHash ?? '';
    if (u.uuid.isEmpty || hash.isEmpty) return false;
    try {
      final at = (u.hubPinSetAt ?? DateTime.now()).toUtc().toIso8601String();
      final rows = await Supabase.instance.client
          .from('users')
          .update({'hub_pin_hash': hash, 'hub_pin_set_at': at})
          .eq('uuid', u.uuid)
          .or('hub_pin_set_at.is.null,hub_pin_set_at.lt."$at"')
          .select('uuid');
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// The 6-digit code both screens show. Same rule as the server:
  /// first 4 bytes of HMAC-SHA256(key = QR secret, msg = SHA-256(phone key)),
  /// mod 1,000,000. Worked out HERE from the secret only this computer and
  /// the phone hold — so a matching code proves it is the same phone.
  static String pairCode(String k, String pubkeyB64) {
    final secret = Uint8List.fromList(base64Url.decode(base64Url.normalize(k)));
    final spki = Uint8List.fromList(base64.decode(pubkeyB64));
    final digest = SHA256Digest().process(spki);
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(secret));
    final out = mac.process(digest);
    final n = (out[0] << 24) | (out[1] << 16) | (out[2] << 8) | out[3];
    return (n % 1000000).toString().padLeft(6, '0');
  }
}

final ownerPhonesApiProvider = Provider<OwnerPhonesApi>(
  (ref) => OwnerPhonesApi(ref.watch(cloudServiceProvider).ensureSignedIn),
);

final phonesOverviewProvider = FutureProvider.autoDispose<PhonesOverview>(
  (ref) => ref.watch(ownerPhonesApiProvider).list(),
);
