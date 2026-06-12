enum AppRole { owner, admin, clinician, receptionist }

AppRole roleFromString(String s) => AppRole.values.firstWhere(
  (r) => r.name == s,
  orElse: () => AppRole.receptionist,
);

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.fullName,
    required this.username,
    required this.role,
    this.branchId,
  });
  final int userId;
  final String fullName, username;
  final AppRole role;
  final String? branchId; // null = clinic-wide (owner/admin)

  bool get isAdmin => role == AppRole.owner || role == AppRole.admin;
  String get initials => fullName
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? '' : w[0])
      .take(2)
      .join()
      .toUpperCase();
}
