import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';

/// What this installation is allowed to do.
///
/// Two independent gates:
///  • cloudPackage — `none` means no backend exists, so every cloud feature
///    is impossible and the tier is meaningless (treated as basic).
///  • tier — only meaningful when cloud is on.
class Entitlements {
  const Entitlements({
    required this.cloud,
    required this.tier,
    required this.maxBranches,
    required this.maxUsers,
  });

  final bool cloud;
  final LicenseTier tier;
  final int maxBranches;
  final int maxUsers;

  bool get _standardUp =>
      tier == LicenseTier.standard || tier == LicenseTier.premium;

  // ── Basic (cloud) ──
  bool get sync => cloud;
  bool get restoreFromCloud => cloud;

  // ── Standard and up ──
  bool get patientApp => cloud && _standardUp;
  bool get bookingRequests => cloud && _standardUp;
  bool get patientQr => cloud && _standardUp;
  bool get clinicQr => cloud && _standardUp;
  bool get reminders => cloud && _standardUp;
  bool get whatsapp => cloud && _standardUp;

  // ── Premium only ──
  bool get offers => cloud && tier == LicenseTier.premium;

  // ── Tier-only (works offline) ──
  bool get unlimitedXrays => tier != LicenseTier.basic;

  /// The 48h reconnect requirement only applies to cloud installs.
  bool get enforcesOnlineCheck => cloud;

  /// Label for upgrade prompts.
  String get tierLabel => switch (tier) {
    LicenseTier.premium => 'Premium',
    LicenseTier.standard => 'Standard',
    LicenseTier.basic => cloud ? 'Basic' : 'Offline',
  };
}

final entitlementsProvider = Provider<Entitlements>((ref) {
  final lic = ref.watch(licenseControllerProvider).value?.license;
  if (lic == null) {
    return const Entitlements(
      cloud: false,
      tier: LicenseTier.basic,
      maxBranches: 1,
      maxUsers: 3,
    );
  }
  final cloud = lic.cloudPackage == CloudPackage.cloud;
  return Entitlements(
    // offline installs are always basic, whatever the licence says
    cloud: cloud,
    tier: cloud ? lic.tier : LicenseTier.basic,
    maxBranches: lic.maxBranches,
    maxUsers: lic.maxUsers,
  );
});
