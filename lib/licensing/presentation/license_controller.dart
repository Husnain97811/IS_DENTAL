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
    if (s.status != LicenseStatus.active)
      return s; // notActivated / invalid / expired
    if (await _conn.withinWindow())
      return s; // synced within 48h → full offline use
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
      await _conn.seedContact();
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
    unawaited(
      _conn.heartbeat(clinicId: lic.clinicId, licenseExpiry: lic.expiresAt),
    );
  }

  Future<void> reload() async => state = AsyncData(await _resolve());
}

final licenseControllerProvider =
    AsyncNotifierProvider<LicenseController, LicenseState>(
      LicenseController.new,
    );
