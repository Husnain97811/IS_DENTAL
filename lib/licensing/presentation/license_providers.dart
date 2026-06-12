import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/license.dart';
import 'license_controller.dart';

final currentLicenseProvider = Provider<License?>(
  (ref) => ref.watch(licenseControllerProvider).value?.license,
);
final isPremiumProvider = Provider<bool>(
  (ref) => ref.watch(currentLicenseProvider)?.tier == LicenseTier.premium,
);
final maxBranchesProvider = Provider<int>(
  (ref) => ref.watch(currentLicenseProvider)?.maxBranches ?? 1,
);
final maxUsersProvider = Provider<int>(
  (ref) => ref.watch(currentLicenseProvider)?.maxUsers ?? 1,
);
