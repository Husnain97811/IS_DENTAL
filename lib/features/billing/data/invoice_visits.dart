import 'package:drift/drift.dart';
import 'package:is_dental/core/db/app_database.dart';

/// One of a patient's appointments an invoice can belong to. The visit is
/// what tells Dentist payouts whose work the money was for.
class InvoiceVisit {
  const InvoiceVisit({
    required this.id,
    required this.dentist,
    required this.startsAt,
    required this.procedure,
    required this.status,
  });

  final int id;
  final String dentist, procedure, status;
  final DateTime startsAt;

  static const _mon = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Today · 4:30 PM", "Yesterday · 11:00 AM", "14 Oct · 6:15 PM"
  String get when {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(startsAt.year, startsAt.month, startsAt.day)).inDays;
    final h = startsAt.hour % 12 == 0 ? 12 : startsAt.hour % 12;
    final time =
        '$h:${startsAt.minute.toString().padLeft(2, '0')} ${startsAt.hour < 12 ? 'AM' : 'PM'}';
    final date = switch (days) {
      0 => 'Today',
      1 => 'Yesterday',
      -1 => 'Tomorrow',
      _ =>
        '${startsAt.day} ${_mon[startsAt.month - 1]}${startsAt.year == now.year ? '' : ' ${startsAt.year}'}',
    };
    return '$date · $time';
  }

  /// "Dr Muneeba · Today · 4:30 PM · Scaling"
  String get label => [
    dentist.trim().isEmpty ? 'No dentist' : dentist.trim(),
    when,
    if (procedure.trim().isNotEmpty) procedure.trim(),
  ].join(' · ');
}

/// How far back a bill can belong to a visit (treatment billed later).
const kVisitLookbackDays = 60;

/// The patient's visits an invoice can be linked to, newest first: from
/// [kVisitLookbackDays] back to the end of tomorrow, never cancelled or
/// no-show ones. [include] is always listed (the visit being billed, or
/// the one an invoice is already linked to), whatever its date. [around]
/// moves the window to another date (an older payment); default today.
Future<List<InvoiceVisit>> patientVisits(
  AppDatabase db,
  int patientId, {
  int? include,
  DateTime? around,
}) async {
  final now = around ?? DateTime.now();
  final from = DateTime(now.year, now.month, now.day - kVisitLookbackDays);
  final to = DateTime(now.year, now.month, now.day + 2);
  final rows =
      await (db.select(db.appointments)
            ..where(
              (t) =>
                  (include == null
                      ? const Constant(false)
                      : t.id.equals(include)) |
                  (t.patientId.equals(patientId) &
                      t.isDeleted.equals(false) &
                      t.status.isNotIn(const ['cancelled', 'noShow']) &
                      t.startsAt.isBiggerOrEqualValue(from) &
                      t.startsAt.isSmallerThanValue(to)),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.startsAt)]))
          .get();
  return [
    for (final r in rows)
      InvoiceVisit(
        id: r.id,
        dentist: r.dentist,
        startsAt: r.startsAt,
        procedure: r.procedure,
        status: r.status,
      ),
  ];
}

/// The visit a new bill most likely belongs to: today's visit, else the
/// most recent one before today. Null when there is none — or when the
/// patient saw two different dentists that day, so nobody gets credited by
/// mistake.
InvoiceVisit? likelyVisit(List<InvoiceVisit> visits, DateTime billedAt) {
  final day = DateTime(billedAt.year, billedAt.month, billedAt.day);
  DateTime dayOf(InvoiceVisit v) =>
      DateTime(v.startsAt.year, v.startsAt.month, v.startsAt.day);

  // same day first, then the latest earlier day
  final sameDay = visits.where((v) => dayOf(v) == day).toList();
  final pool = sameDay.isNotEmpty
      ? sameDay
      : () {
          final before = visits.where((v) => dayOf(v).isBefore(day)).toList();
          if (before.isEmpty) return <InvoiceVisit>[];
          final latest = before
              .map(dayOf)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          return before.where((v) => dayOf(v) == latest).toList();
        }();
  if (pool.isEmpty) return null;
  final dentists = {for (final v in pool) v.dentist.trim().toLowerCase()};
  return dentists.length == 1 ? pool.first : null;
}

/// Links (or unlinks, with null) an invoice to a visit. Bumps updatedAt so
/// the link syncs to the clinic's other computers.
Future<void> linkInvoiceToVisit(
  AppDatabase db,
  int invoiceId,
  int? appointmentId,
) => (db.update(db.invoices)..where((t) => t.id.equals(invoiceId))).write(
  InvoicesCompanion(
    appointmentId: Value(appointmentId),
    updatedAt: Value(DateTime.now()),
  ),
);
