class BookingRequestView {
  const BookingRequestView({
    required this.id,
    required this.uuid,
    required this.branchId,
    required this.patientUuid,
    required this.patientName,
    required this.dentist,
    required this.procedure,
    required this.slotPkt, // already +5, the real Pakistan time
    required this.durationMin,
    required this.status,
    required this.modifiedBy,
    required this.acceptedBy,
    required this.decidedAt,
    required this.createdAt,
  });

  final int id;
  final String uuid;
  final String? branchId;
  final String patientUuid;
  final String patientName;
  final String dentist;
  final String procedure;
  final DateTime slotPkt;
  final int durationMin;
  final String status; // pending | approved | rejected
  final String? modifiedBy;
  final String? acceptedBy;
  final DateTime? decidedAt;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}
