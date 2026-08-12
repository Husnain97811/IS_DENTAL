class Offer {
  const Offer({
    required this.id,
    required this.uuid,
    required this.branchId,
    required this.title,
    required this.body,
    this.imageUrl,
    this.startsAt,
    this.expiresAt,
    required this.sentCount,
    this.createdBy,
    required this.createdAt,
  });

  final int id;
  final String uuid;
  final String? branchId;
  final String title;
  final String body;
  final String? imageUrl;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int sentCount;
  final String? createdBy;
  final DateTime createdAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}
