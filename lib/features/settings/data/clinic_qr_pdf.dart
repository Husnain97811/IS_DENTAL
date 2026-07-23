import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildClinicQrPdf({
  required String clinicName,
  required String clinicCode,
  required String payload,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              clinicName,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Patient App — Clinic QR',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: payload,
                width: 220,
                height: 220,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Clinic ID',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              clinicCode,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 28),
            pw.Text(
              'Scan this code in the DentOS patient app, or enter the Clinic ID '
              'manually, to link your clinic.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    ),
  );
  return doc.save();
}
