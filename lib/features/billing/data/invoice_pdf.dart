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

String _dateTime(DateTime dt) {
  final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  final m = dt.minute.toString().padLeft(2, '0');
  return '${_date(dt)}  $h:$m $ap';
}

// ---- number → words (Indian/Pakistani system: lakh, crore) ----
String _amountInWords(int amount) {
  if (amount == 0) return 'Zero Rupees Only';
  const ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  const tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  String twoDigit(int n) {
    if (n < 20) return ones[n];
    return '${tens[n ~/ 10]}${n % 10 != 0 ? ' ${ones[n % 10]}' : ''}';
  }

  String threeDigit(int n) {
    final h = n ~/ 100;
    final rest = n % 100;
    final parts = <String>[];
    if (h > 0) parts.add('${ones[h]} Hundred');
    if (rest > 0) parts.add(twoDigit(rest));
    return parts.join(' ');
  }

  final parts = <String>[];
  final crore = amount ~/ 10000000;
  amount %= 10000000;
  final lakh = amount ~/ 100000;
  amount %= 100000;
  final thousand = amount ~/ 1000;
  amount %= 1000;
  final hundred = amount;

  if (crore > 0) parts.add('${threeDigit(crore)} Crore');
  if (lakh > 0) parts.add('${threeDigit(lakh)} Lakh');
  if (thousand > 0) parts.add('${threeDigit(thousand)} Thousand');
  if (hundred > 0) parts.add(threeDigit(hundred));

  return '${parts.join(' ')} Rupees Only';
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
  // ---- NEW optional medical-receipt fields (safe defaults) ----
  String? clinicAddress,
  String? clinicPhone,
  String? clinicEmail,
  String? clinicNtn, // National Tax Number (optional)
  String? patientAge, // e.g. '24'
  String? patientGender, // e.g. 'Male'
  String? patientPhone,
  String? patientCnic,
  String? dentistName, // treating dentist / authorised signatory
  String? dentistQualification, // e.g. 'BDS, RDS' or 'MDS · Prosthodontist'
  String? pmdcNumber, // PMDC registration (optional)
  String? paymentMode, // 'Cash' | 'Card' | 'JazzCash' | 'EasyPaisa'
  String? receiptNo, // defaults to invoiceNo
  String? termsText, // footer terms/policy
}) async {
  final doc = pw.Document();
  final st = _statusStyle(inv.status);

  int lineTotal(InvoiceItem it) => it.amount * it.qty;
  final computedSubtotal = inv.items.fold<int>(0, (s, it) => s + lineTotal(it));
  final subtotal = inv.subtotal != 0 ? inv.subtotal : computedSubtotal;
  final gross = inv.total;

  // Paid/unpaid derived from status (no partial-payment system).
  final isPaid = inv.status == InvoiceStatus.paid;
  final amountPaid = isPaid ? gross : 0;
  final balance = gross - amountPaid;

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

  // small label:value line for the meta grid
  pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 74,
          child: pw.Text(
            k,
            style: pw.TextStyle(
              fontSize: 9,
              color: _muted,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(': ', style: const pw.TextStyle(fontSize: 9, color: _muted)),
        pw.Expanded(
          child: pw.Text(
            v,
            style: pw.TextStyle(
              fontSize: 9.5,
              color: _ink,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );

  final ageGender = [
    if (patientAge != null && patientAge.isNotEmpty) patientAge,
    if (patientGender != null && patientGender.isNotEmpty) patientGender,
  ].join(' ');

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
              pw.Expanded(
                child: pw.Column(
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
                    if (clinicAddress != null && clinicAddress.isNotEmpty)
                      pw.Text(
                        clinicAddress,
                        style: const pw.TextStyle(fontSize: 9, color: _muted),
                      ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      [
                        if (clinicPhone != null && clinicPhone.isNotEmpty)
                          'Ph: $clinicPhone',
                        if (clinicEmail != null && clinicEmail.isNotEmpty)
                          clinicEmail,
                      ].join('   ·   '),
                      style: const pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                    if (clinicNtn != null && clinicNtn.isNotEmpty)
                      pw.Text(
                        'NTN: $clinicNtn',
                        style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
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
                      width: 90,
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
          pw.SizedBox(height: 14),
          pw.Divider(color: _line, thickness: 1),
          pw.SizedBox(height: 12),

          // ---------- META GRID (two columns) ----------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // left column — bill meta
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    kv('Bill No', inv.invoiceNo, bold: true),
                    if (patientCode != null && patientCode.isNotEmpty)
                      kv('Reg No', patientCode),
                    kv('Date', _date(inv.issuedAt)),
                    kv('Print', _dateTime(DateTime.now())),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              // right column — patient meta
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    kv('Patient', inv.patientName, bold: true),
                    if (ageGender.isNotEmpty) kv('Age/Gender', ageGender),
                    if (patientPhone != null && patientPhone.isNotEmpty)
                      kv('Phone', patientPhone),
                    if (patientCnic != null && patientCnic.isNotEmpty)
                      kv('CNIC', patientCnic),
                  ],
                ),
              ),
              // status chip
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
          pw.SizedBox(height: 16),

          // ---------- ITEMS TABLE ----------
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line),
              bottom: pw.BorderSide(color: _line),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.7),
              1: const pw.FlexColumnWidth(5),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _ink),
                children: [
                  cell('#', bold: true, color: PdfColors.white, size: 9),
                  cell(
                    'TREATMENT / DESCRIPTION',
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
              for (var i = 0; i < inv.items.length; i++)
                pw.TableRow(
                  children: [
                    cell('${i + 1}', align: pw.Alignment.center, color: _muted),
                    cell(inv.items[i].description),
                    cell('${inv.items[i].qty}', align: pw.Alignment.center),
                    cell(
                      _rs(inv.items[i].amount),
                      align: pw.Alignment.centerRight,
                    ),
                    cell(
                      _rs(lineTotal(inv.items[i])),
                      align: pw.Alignment.centerRight,
                      bold: true,
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ---------- TOTALS BLOCK ----------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 250,
                child: pw.Column(
                  children: [
                    _totalRow('Subtotal', _rs(subtotal)),
                    if (inv.adjustment != 0)
                      _totalRow('Adjust./Discount', '- ${_rs(inv.adjustment)}'),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 7),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: _ink, width: 1.4),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Gross Amount',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                          pw.Text(
                            _rs(gross),
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _totalRow('Amount Paid', _rs(amountPaid)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 6),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: _line, width: 1),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Balance Due',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: balance > 0 ? _ink : _ice,
                            ),
                          ),
                          pw.Text(
                            _rs(balance),
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: balance > 0
                                  ? PdfColor.fromInt(0xFFB45309)
                                  : _ice,
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
          pw.SizedBox(height: 10),

          // ---------- AMOUNT IN WORDS ----------
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _line),
            ),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  const pw.TextSpan(
                    text: 'Amount in words:  ',
                    style: pw.TextStyle(fontSize: 8.5, color: _muted),
                  ),
                  pw.TextSpan(
                    text: _amountInWords(gross),
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      color: _ink,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 10),

          // ---------- PAYMENT DETAILS ----------
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PAYMENT DETAILS',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: _muted,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: .5,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    _payCol('Receipt No', receiptNo ?? inv.invoiceNo),
                    _payCol('Amount Received', _rs(amountPaid)),
                    _payCol('Mode', paymentMode ?? (isPaid ? 'Cash' : '—')),
                    _payCol('Date', _date(inv.issuedAt)),
                  ],
                ),
              ],
            ),
          ),

          pw.Spacer(),

          // ---------- SIGNATORY ----------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (termsText != null && termsText.isNotEmpty)
                    pw.SizedBox(
                      width: 240,
                      child: pw.Text(
                        termsText,
                        style: const pw.TextStyle(fontSize: 7, color: _muted),
                      ),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 160,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: _ink, width: 0.8),
                      ),
                    ),
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          dentistName ?? 'Authorised Signatory',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (dentistQualification != null &&
                            dentistQualification.isNotEmpty)
                          pw.Text(
                            dentistQualification,
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: _muted,
                            ),
                          ),
                        if (pmdcNumber != null && pmdcNumber.isNotEmpty)
                          pw.Text(
                            'PMDC: $pmdcNumber',
                            style: const pw.TextStyle(
                              fontSize: 7.5,
                              color: _muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),

          // ---------- FOOTER ----------
          pw.Divider(color: _line),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Thank you for choosing $clinicName. Scan the QR with the '
                  'DentOS patient app to book and manage appointments.',
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted),
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

pw.Widget _payCol(String label, String value) => pw.Expanded(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ),
);

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
