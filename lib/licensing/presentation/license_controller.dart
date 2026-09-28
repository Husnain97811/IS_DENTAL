import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/connectivity_service.dart';
import '../data/license_service.dart';
import '../domain/license.dart';

class LicenseController extends AsyncNotifier<LicenseState> {
  Timer? _timer;
  LicenseService get _lic => ref.read(licenseServiceProvider);
  ConnectivityService get _conn => ref.read(connectivityServiceProvider);

  @override
  Future<LicenseState> build() async {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => reload());
    ref.onDispose(() => _timer?.cancel());
    return _resolve();
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
