import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';

/// What this installation is allowed to do.
///
/// Two independent gates:
///  • cloudPackage — `none` means no backend exists, so every cloud feature
///    is impossible and the tier is meaningless (treated as basic).
///  • tier — only meaningful when cloud is on.
///
/// Screens never check the tier themselves — they ask for a feature here
/// (`ent.showcase`, `ent.insights` …), so moving a feature between plans is
/// a one-line change in this file.
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

  /// Standard or Premium, on a cloud licence.
  bool get standard => cloud && _standardUp;

  // ── Basic (cloud) ──
  bool get sync => cloud;
  bool get restoreFromCloud => cloud;

  // ── Standard and up ──
  bool get patientApp => standard;
  bool get bookingRequests => standard;
  bool get patientQr => standard;
  bool get clinicQr => standard;
  bool get reminders => standard;
  bool get whatsapp => standard;

  /// Prescription PDFs to the patient on WhatsApp — automatic and Send/Resend.
  bool get rxOnWhatsapp => whatsapp;

  /// Reports → Insights tab and the "Insights at a glance" card.
  bool get insights => standard;

  /// Reports overview: Still owed to you, Patients seen, Procedures done.
  bool get practiceStats => standard;

  /// Before & After photos on the patient file.
  bool get beforeAfterPhotos => standard;

  /// Smile Showcase screen.
  bool get showcase => standard;

  /// Expenses → Dentist payouts.
  bool get dentistPayouts => standard;

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
