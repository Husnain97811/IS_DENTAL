import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../presentation/reports_controller.dart';

final _accent = PdfColor.fromInt(0xFF0BB6A0);

String _rs(int v) =>
    'Rs ${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

Future<Uint8List> buildReportsPdf(
  ReportsSummary s, {
  required String clinicName,
  String? rangeLabel,
}) async {
  final doc = pw.Document();
  final now = DateTime.now();
  final mixTotal = s.mix.fold<double>(0, (a, b) => a + b.value);

  pw.Widget heading(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(
      t,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  );

  pw.Widget kpi(String label, String value) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  clinicName,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Practice Report · ${rangeLabel ?? 'Last 12 months'}',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Text(
              'Generated ${now.toString().split(' ').first}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.Divider(color: _accent),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            kpi('Total Revenue', _rs(s.totalRevenue)),
            kpi('Patients', '${s.patientCount}'),
            kpi('Procedures', '${s.procedureCount}'),
          ],
        ),

        heading('Monthly Revenue'),
        pw.Table.fromTextArray(
          headers: const ['Month', 'Revenue'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignments: {1: pw.Alignment.centerRight},
          data: [
            for (var i = 0; i < s.monthly.length; i++)
              [s.monthLabels[i], _rs((s.monthly[i] * 1000).round())],
          ],
        ),

        // heading('Procedure Mix'),
        // pw.Table.fromTextArray(
        //   headers: const ['Category', 'Revenue', 'Share'],
        //   headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        //   cellAlignments: {
        //     1: pw.Alignment.centerRight,
        //     2: pw.Alignment.centerRight,
        //   },
        //   data: [
        //     for (final m in s.mix)
        //       [
        //         m.label,
        //         _rs(m.value.round()),
        //         mixTotal == 0 ? '0%' : '${(m.value / mixTotal * 100).round()}%',
        //       ],
        //   ],
        // ),
        heading('Dentist Performance'),
        pw.Table.fromTextArray(
          headers: const ['Dentist', 'Appointments'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignments: {1: pw.Alignment.centerRight},
          data: [
            for (final dd in s.dentists) [dd.name, '${dd.value}'],
          ],
        ),

        heading('Transactions · Last 12 months'),
        pw.Table.fromTextArray(
          headers: const ['Invoice', 'Date', 'Patient', 'Amount', 'Status'],
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {3: pw.Alignment.centerRight},
          data: [
            for (final t in s.transactions)
              [
                t.invoiceNo,
                t.date.toString().split(' ').first,
                t.patient,
                _rs(t.amount),
                t.status,
              ],
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
