import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/invoice.dart';
import '../../../core/utils/qr_payload.dart';

String _rs(int v) =>
    'Rs ${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

String _date(DateTime dt) {
  const mon = [
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
  return '${dt.day} ${mon[dt.month - 1]} ${dt.year}';
}

({String label, PdfColor bg, PdfColor fg}) _statusStyle(InvoiceStatus s) =>
    switch (s) {
      InvoiceStatus.paid => (
        label: 'PAID',
        bg: PdfColor.fromInt(0xFFE7F7EE),
        fg: PdfColor.fromInt(0xFF15803D),
      ),
      InvoiceStatus.pending => (
        label: 'PENDING',
        bg: PdfColor.fromInt(0xFFFEF3E2),
        fg: PdfColor.fromInt(0xFFB45309),
      ),
      InvoiceStatus.overdue => (
        label: 'OVERDUE',
        bg: PdfColor.fromInt(0xFFFDE7EC),
        fg: PdfColor.fromInt(0xFFBE123C),
      ),
    };

// Brand accents
const _ice = PdfColor.fromInt(0xFF0EA5E9);
const _ink = PdfColor.fromInt(0xFF0D1626);
const _muted = PdfColor.fromInt(0xFF64748B);
const _line = PdfColor.fromInt(0xFFE2E8F0);

Future<Uint8List> buildInvoicePdf(
  Invoice inv, {
  required String clinicName,
  required String clinicId,
  required String patientUuid,
  String? patientCode,
  String? clinicBranch,
}) async {
  final doc = pw.Document();
  final st = _statusStyle(inv.status);

  // Per-unit math: each line = amount × qty.
  int lineTotal(InvoiceItem it) => it.amount * it.qty;
  final computedSubtotal = inv.items.fold<int>(0, (s, it) => s + lineTotal(it));
  // Prefer stored subtotal if present, else computed.
  final subtotal = inv.subtotal != 0 ? inv.subtotal : computedSubtotal;

  final qrPayload = buildPatientQrPayload(
    clinicId: clinicId,
    patientUuid: patientUuid,
  );

  pw.Widget cell(
    String t, {
    pw.Alignment align = pw.Alignment.centerLeft,
    bool bold = false,
    PdfColor color = _ink,
    double size = 10,
  }) => pw.Container(
    alignment: align,
    padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ---------- HEADER ----------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    clinicName,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  if (clinicBranch != null && clinicBranch.isNotEmpty)
                    pw.Text(
                      clinicBranch,
                      style: const pw.TextStyle(fontSize: 10, color: _muted),
                    ),
                  // pw.SizedBox(height: 2),
                  // pw.Text(
                  //   'TAX INVOICE',
                  //   style: pw.TextStyle(
                  //     fontSize: 11,
                  //     color: _ice,
                  //     fontWeight: pw.FontWeight.bold,
                  //     letterSpacing: 1.5,
                  //   ),
                  // ),
                ],
              ),
              // QR block — the patient's app login/setup code.
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(color: _line),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(
                        errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
                      ),
                      data: qrPayload,
                      width: 90, // ~32mm printed
                      height: 90,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.SizedBox(
                    width: 102,
                    child: pw.Text(
                      'Scan to access your appointments',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 7, color: _muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Divider(color: _line, thickness: 1),
          pw.SizedBox(height: 14),

          // ---------- META ROW ----------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BILLED TO',
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    inv.patientName,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (patientCode != null && patientCode.isNotEmpty)
                    pw.Text(
                      '#$patientCode',
                      style: const pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(
                    children: [
                      pw.Text(
                        'Invoice  ',
                        style: const pw.TextStyle(fontSize: 9, color: _muted),
                      ),
                      pw.Text(
                        inv.invoiceNo,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    _date(inv.issuedAt),
                    style: const pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: st.bg,
                      borderRadius: pw.BorderRadius.circular(20),
                    ),
                    child: pw.Text(
                      st.label,
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: st.fg,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ---------- ITEMS TABLE ----------
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line),
              bottom: pw.BorderSide(color: _line),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(5),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _ink),
                children: [
                  cell(
                    'DESCRIPTION',
                    bold: true,
                    color: PdfColors.white,
                    size: 9,
                  ),
                  cell(
                    'QTY',
                    align: pw.Alignment.center,
                    bold: true,
                    color: PdfColors.white,
                    size: 9,
                  ),
                  cell(
                    'UNIT PRICE',
                    align: pw.Alignment.centerRight,
                    bold: true,
                    color: PdfColors.white,
                    size: 9,
                  ),
                  cell(
                    'AMOUNT',
                    align: pw.Alignment.centerRight,
                    bold: true,
                    color: PdfColors.white,
                    size: 9,
                  ),
                ],
              ),
              for (final it in inv.items)
                pw.TableRow(
                  children: [
                    cell(it.description),
                    cell('${it.qty}', align: pw.Alignment.center),
                    cell(_rs(it.amount), align: pw.Alignment.centerRight),
                    cell(
                      _rs(lineTotal(it)),
                      align: pw.Alignment.centerRight,
                      bold: true,
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),

          // ---------- TOTALS BLOCK ----------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 230,
                child: pw.Column(
                  children: [
                    _totalRow('Subtotal', _rs(subtotal)),
                    if (inv.adjustment != 0)
                      _totalRow('Adjust./Discount', '- ${_rs(inv.adjustment)}'),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 8),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: _ink, width: 1.4),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'TOTAL DUE',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                          pw.Text(
                            _rs(inv.total),
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: _ice,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          pw.Spacer(),

          // ---------- FOOTER ----------
          pw.Divider(color: _line),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Thank you for choosing $clinicName.',
                      style: const pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Scan the QR above with the DentOS patient app to book '
                      'and manage your appointments.',
                      style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                    ),
                  ],
                ),
              ),
              pw.Text(
                'Clinic ID: $clinicId',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

pw.Widget _totalRow(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.Text(value, style: const pw.TextStyle(fontSize: 10, color: _ink)),
    ],
  ),
);
