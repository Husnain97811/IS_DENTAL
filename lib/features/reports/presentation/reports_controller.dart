import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';

class ReportsSummary {
  ReportsSummary({
    required this.totalRevenue,
    required this.patientCount,
    required this.procedureCount,
    required this.monthly,
    required this.monthLabels,
    required this.mix,
    required this.dentists,
  });
  final int totalRevenue, patientCount, procedureCount;
  final List<double> monthly; // thousands
  final List<String> monthLabels;
  final List<({String label, double value})> mix;
  final List<({String name, int value})> dentists;
}

String _classify(String s) {
  final l = s.toLowerCase();
  if (l.contains('root canal') || l.contains('endo')) return 'Endodontics';
  if (l.contains('crown') ||
      l.contains('fill') ||
      l.contains('composite') ||
      l.contains('scaling'))
    return 'Restorative';
  if (l.contains('brace') || l.contains('ortho')) return 'Orthodontics';
  if (l.contains('extraction') ||
      l.contains('implant') ||
      l.contains('surgery') ||
      l.contains('wisdom'))
    return 'Surgery';
  return 'Other';
}

final reportsSummaryProvider = FutureProvider.autoDispose<ReportsSummary>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  final invoices = await (db.select(
    db.invoices,
  )..where((t) => t.isDeleted.equals(false))).get();
  final patients = await (db.select(
    db.patients,
  )..where((t) => t.isDeleted.equals(false))).get();
  final appts = await (db.select(
    db.appointments,
  )..where((t) => t.isDeleted.equals(false))).get();

  final totalRevenue = invoices
      .where((i) => i.status == 'paid')
      .fold<int>(0, (s, i) => s + i.total);

  const months = [
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
  final now = DateTime.now();
  final monthly = <double>[];
  final labels = <String>[];
  for (var k = 5; k >= 0; k--) {
    final m = DateTime(now.year, now.month - k);
    labels.add(months[m.month - 1]);
    final sum = invoices
        .where((i) => i.issuedAt.year == m.year && i.issuedAt.month == m.month)
        .fold<int>(0, (s, i) => s + i.total);
    monthly.add(sum / 1000);
  }

  final mixMap = <String, double>{};
  for (final i in invoices) {
    mixMap.update(
      _classify(i.summary),
      (v) => v + i.total,
      ifAbsent: () => i.total.toDouble(),
    );
  }
  final mix = mixMap.entries.map((e) => (label: e.key, value: e.value)).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final dMap = <String, int>{};
  for (final a in appts) {
    dMap.update(a.dentist, (v) => v + 1, ifAbsent: () => 1);
  }
  final dentists =
      dMap.entries.map((e) => (name: e.key, value: e.value)).toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  return ReportsSummary(
    totalRevenue: totalRevenue,
    patientCount: patients.length,
    procedureCount: appts.length,
    monthly: monthly,
    monthLabels: labels,
    mix: mix,
    dentists: dentists,
  );
});
