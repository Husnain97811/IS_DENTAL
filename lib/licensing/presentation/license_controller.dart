import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/views.dart' show cloudServiceProvider;
import '../data/connectivity_service.dart';
import '../data/license_service.dart';
import '../domain/license.dart';

/// What the "Check subscription" button found (locked / reconnect screens).
enum CloudCheckResult {
  /// A renewal was found (or the server confirmed the subscription) and the
  /// computer is unlocked.
  renewed,

  /// The cloud answered, but there is no renewal yet.
  notRenewed,

  /// The server could not be reached.
  offline,

  /// An offline licence — it only unlocks with a pasted key.
  notCloud,

  /// No licence on this computer, or something unexpected.
  failed,
}

class CloudCheck {
  const CloudCheck(this.result, {this.until});
  final CloudCheckResult result;

  /// The licence's expiry after the check (null when unknown).
  final DateTime? until;
}

class LicenseController extends AsyncNotifier<LicenseState> {
  Timer? _timer;
  LicenseService get _lic => ref.read(licenseServiceProvider);
  ConnectivityService get _conn => ref.read(connectivityServiceProvider);

  @override
  Future<LicenseState> build() async {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) async {
      await reload();
      unawaited(_checkCloudLicence());
      unawaited(_listenLive()); // reconnects if it dropped
    });
    ref.onDispose(() => _timer?.cancel());
    ref.onDispose(_stopLive);
    // A renewal saved on the cloud by the licence tool reaches this
    // computer by itself — a few seconds after start-up, then every 15
    // minutes. Never blocks start-up.
    _startupCheck?.cancel();
    _startupCheck = Timer(const Duration(seconds: 4), () {
      unawaited(_checkCloudLicence());
      unawaited(_listenLive());
    });
    ref.onDispose(() => _startupCheck?.cancel());
    return _resolve();
  }

  Timer? _startupCheck;
  bool _checking = false;
  bool _checkAgain = false;

  // ── live: the licence tool saved a renewal / switch / "view only" ──
  RealtimeChannel? _live;
  String? _liveFor;

  /// Listens to THIS clinic's cloud record. The moment the licence tool
  /// saves a new licence there (new date, feature switches, payment
  /// overdue), this computer applies it — within a couple of seconds
  /// instead of at the next 15-minute check. The new licence goes through
  /// exactly the same signature check; the live message only says "look
  /// now". Offline licences never listen.
  Future<void> _listenLive() async {
    try {
      final cur = (await _lic.resolveLicense()).license;
      if (cur == null || cur.cloudPackage != CloudPackage.cloud) {
        _stopLive();
        return;
      }
      if (_live != null && _liveFor == cur.clinicId) return;
      _stopLive();
      await ref.read(cloudServiceProvider).ensureSignedIn();
      final id = cur.clinicId;
      _liveFor = id;
      _live = Supabase.instance.client
          .channel('dentos-licence-$id')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'clinics',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: id,
            ),
            callback: (_) => unawaited(_checkCloudLicence()),
          )
          .subscribe((status, _) {
            // (re)connected → catch up on anything saved meanwhile
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(_checkCloudLicence());
            }
          });
    } catch (_) {
      // offline or signed out — the 15-minute check tries again
      _stopLive();
    }
  }

  void _stopLive() {
    final ch = _live;
    _live = null;
    _liveFor = null;
    if (ch != null) {
      unawaited(
        Supabase.instance.client
            .removeChannel(ch)
            .then((_) {}, onError: (_) {}),
      );
    }
  }

  /// Applies a newer licence from the clinic's cloud record, if there is
  /// one. Works on the locked screen too, so a renewal unlocks an expired
  /// install without anyone typing a key. Offline licences never call out.
  Future<void> _checkCloudLicence() async {
    if (_checking) {
      // a save arrived while a check was running → look once more after
      _checkAgain = true;
      return;
    }
    _checking = true;
    try {
      final cur = (await _lic.resolveLicense()).license;
      if (cur == null || cur.cloudPackage != CloudPackage.cloud) return;
      final raw = await _conn.cloudLicence(cur.clinicId);
      if (raw == null) return;
      if (await _lic.applyFromCloud(raw)) {
        state = AsyncData(await _resolve());
      }
    } catch (_) {
      // best-effort; the next check tries again
    } finally {
      _checking = false;
      if (_checkAgain) {
        _checkAgain = false;
        unawaited(_checkCloudLicence());
      }
    }
  }

  Future<LicenseState> _resolve() async {
    final s = await _lic.resolveLicense();
    if (s.status != LicenseStatus.active) {
      return s; // notActivated / invalid / expired
    }

    // ── OFFLINE LICENCE: no cloud package means no heartbeat, ever.
    // These installs never sync, so requiring an internet check would lock
    // out software that was sold as fully offline.
    if (s.license!.cloudPackage == CloudPackage.none) {
      return s;
    }

    if (await _conn.withinWindow()) return s;
    final hb = await _conn.heartbeat(
      clinicId: s.license!.clinicId,
      licenseExpiry: s.license!.expiresAt,
    );
    return switch (hb) {
      HeartbeatResult.ok => await _lic.resolveLicense(),
      HeartbeatResult.subscriptionInvalid => LicenseState(
        status: LicenseStatus.expired,
        license: s.license,
      ),
      HeartbeatResult.offline => LicenseState(
        status: LicenseStatus.reconnectRequired,
        license: s.license,
        setupComplete: s.setupComplete,
      ),
    };
  }

  Future<({bool ok, String? error})> activate(String raw) async {
    final r = await _lic.activate(raw);
    if (r.ok) {
      final lic = (await _lic.resolveLicense()).license;
      if (lic?.cloudPackage == CloudPackage.cloud) {
        await _conn.seedContact();
      }
      state = AsyncData(await _resolve());
    }
    return r;
  }

  Future<void> completeSetup({
    required String clinicName,
    required String branch,
    required String currency,
    required String ownerName,
    required String username,
    required String email,
    required String password,
  }) async {
    final lic = state.value?.license;
    if (lic == null) return;
    final svc = ref.read(licenseServiceProvider); // <- was _svc
    await svc.completeSetup(
      lic: lic,
      clinicName: clinicName,
      branch: branch,
      currency: currency,
      ownerName: ownerName,
      username: username,
      email: email,
      password: password,
    );
    state = AsyncData(await svc.resolveLicense());
    if (lic.cloudPackage == CloudPackage.cloud) {
      unawaited(
        _conn.heartbeat(clinicId: lic.clinicId, licenseExpiry: lic.expiresAt),
      );
    }
  }

  Future<void> reload() async => state = AsyncData(await _resolve());

  /// Settings → Licence → "Check for a renewal now".
  Future<void> checkCloudNow() => _checkCloudLicence();

  /// The "Check subscription" button on the locked and reconnect screens.
  ///
  /// Asks the cloud for a renewal saved by the licence tool and applies it
  /// (signature checked, newer only — exactly like the automatic check),
  /// then checks the subscription with the server again. When everything
  /// is in order the state turns active and the router unlocks by itself.
  /// Offline licences never call out — they unlock with a pasted key only.
  Future<CloudCheck> checkSubscriptionNow() async {
    try {
      final cur = (await _lic.resolveLicense()).license;
      if (cur == null) return const CloudCheck(CloudCheckResult.failed);
      if (cur.cloudPackage != CloudPackage.cloud) {
        return const CloudCheck(CloudCheckResult.notCloud);
      }
      try {
        await ref
            .read(cloudServiceProvider)
            .ensureSignedIn()
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        return CloudCheck(CloudCheckResult.offline, until: cur.expiresAt);
      }
      final raw = await _conn.cloudLicence(cur.clinicId);
      if (raw != null) await _lic.applyFromCloud(raw);

      // the saved licence AND the server's subscription record, re-checked
      final s = await _resolve();
      state = AsyncData(s);
      final until = s.license?.expiresAt;
      return switch (s.status) {
        LicenseStatus.active => CloudCheck(
          CloudCheckResult.renewed,
          until: until,
        ),
        LicenseStatus.reconnectRequired => CloudCheck(
          CloudCheckResult.offline,
          until: until,
        ),
        _ => CloudCheck(CloudCheckResult.notRenewed, until: until),
      };
    } catch (_) {
      return const CloudCheck(CloudCheckResult.failed);
    }
  }

  /// Called by the wizard once a join or recovery has restored the data.
  Future<void> completeJoin({
    required String cloudEmail,
    required String cloudPassword,
    required String deviceLetter,
  }) async {
    final lic = state.value?.license;
    if (lic == null) return;
    final svc = ref.read(licenseServiceProvider);
    await svc.completeJoin(
      lic: lic,
      cloudEmail: cloudEmail,
      cloudPassword: cloudPassword,
      deviceLetter: deviceLetter,
    );
    await _conn.seedContact();
    state = AsyncData(await svc.resolveLicense());
  }

  /// Apply a new licence to an already-set-up install — an upgrade or renewal.
  /// Nothing is deleted: the clinic id is unchanged, so patients, staff,
  /// settings and cloud data all stay exactly as they are.
  /// Apply a new licence to an already-set-up install.
  ///
  /// The cloud row is updated FIRST. If that fails nothing is stored locally,
  /// so the licence and the cloud record can never drift apart — a stale
  /// `clinics.expires_at` would otherwise lock the clinic out on heartbeat.
  Future<({bool ok, String? error})> reactivate(String raw) async {
    final current = state.value?.license;
    final r = await _lic.activate(raw, expectedClinicId: current?.clinicId);
    if (!r.ok) return r;

    final fresh = (await _lic.resolveLicense()).license;
    if (fresh != null) await _lic.syncProfileTier(fresh);

    state = AsyncData(await _resolve());
    return r;
  }

  /// Returns null on success, or a message describing the failure.
}

final licenseControllerProvider =
    AsyncNotifierProvider<LicenseController, LicenseState>(
      LicenseController.new,
    );
