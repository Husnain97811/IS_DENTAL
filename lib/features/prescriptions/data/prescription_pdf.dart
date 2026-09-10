import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:is_dental/features/prescriptions/data/domain/prescription.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class RxPdfData {
  const RxPdfData({
    required this.clinicName,
    required this.branchLine,
    required this.contactLine,
    required this.regLine,
    required this.footer,
    required this.patientName,
    required this.patientCode,
    required this.age,
    required this.gender,
    this.allergies,
    required this.qrPayload,
    required this.rx,
  });
  final String clinicName, branchLine, contactLine, regLine, footer;
  final String patientName, patientCode, gender;
  final int age;
  final String? allergies;
  final String qrPayload;
  final Prescription rx;
}

class PrescriptionPdf {
  static const _ice = PdfColor.fromInt(0xFF38BDF8);
  static const _teal = PdfColor.fromInt(0xFF0BB6A0);
  static const _tealB = PdfColor.fromInt(0xFFE7FBF8);
  static const _ink = PdfColor.fromInt(0xFF0D1626);
  static const _body = PdfColor.fromInt(0xFF334155);
  static const _mute = PdfColor.fromInt(0xFF64748B);
  static const _light = PdfColor.fromInt(0xFF94A3B8);
  static const _line = PdfColor.fromInt(0xFFE2E8F0);
  static const _rule = PdfColor.fromInt(0xFFCBD5E1);
  static const _red = PdfColor.fromInt(0xFF9F1239);
  static const _redBg = PdfColor.fromInt(0xFFFDF2F5);
  static const _redLn = PdfColor.fromInt(0xFFBE123C);

  static Future<Uint8List> build(RxPdfData d) async {
    final urdu = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNaskhArabic.ttf'),
    );
    final doc = pw.Document(title: 'Prescription ${d.rx.rxNo}');
    final rx = d.rx;

    pw.Widget lbl(String t, {double s = 8, PdfColor c = _mute}) => pw.Text(
      t,
      style: pw.TextStyle(fontSize: s, color: c),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(50, 40, 50, 56),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── letterhead ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 6,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        d.clinicName,
                        style: pw.TextStyle(
                          fontSize: 17,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      if (d.branchLine.isNotEmpty) lbl(d.branchLine),
                      if (d.contactLine.isNotEmpty) lbl(d.contactLine),
                      if (d.regLine.isNotEmpty) lbl(d.regLine),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        rx.doctorName.isEmpty ? '—' : rx.doctorName,
                        style: pw.TextStyle(
                          fontSize: 11.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        width: 64,
                        height:
                            64, // 22mm chnge it to bigger if ther is any complaint
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: d.qrPayload,
                          drawText: false,
                          color: _ink,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Patient QR',
                        style: const pw.TextStyle(fontSize: 6.5, color: _light),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 1.6, color: _ice),
            pw.SizedBox(height: 10),

            // ── patient block ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 6,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _kv(
                        'Patient',
                        '${d.patientName}    ·    ID: ${d.patientCode}',
                      ),
                      _kv('Age / Sex', '${d.age} yrs / ${d.gender}'),
                      if (rx.appointmentLabel.isNotEmpty)
                        _kv('Visit', rx.appointmentLabel),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _kv('Date', _fmt(rx.issuedAt), right: true),
                      _kv('Rx No', rx.rxNo, right: true),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 9),

            // ── allergy ──
            if ((d.allergies ?? '').trim().isNotEmpty)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: _redBg,
                  border: pw.Border.all(color: _redLn, width: 1.1),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  'ALLERGY   |   ${d.allergies}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _red,
                  ),
                ),
              ),
            pw.SizedBox(height: 10),

            // ── Rx mark ──
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'R',
                    style: pw.TextStyle(
                      fontSize: 23,
                      fontWeight: pw.FontWeight.bold,
                      color: _teal,
                    ),
                  ),
                  pw.TextSpan(
                    text: 'x',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: _teal,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 9),

            // ── medicines ──
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1.8),
                2: const pw.FlexColumnWidth(2.4),
                3: const pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _rule, width: 1.2),
                    ),
                  ),
                  children: [
                    _th('MEDICINE'),
                    _th('DOSAGE'),
                    _th('FREQUENCY'),
                    _th('DURATION'),
                  ],
                ),
                for (var i = 0; i < rx.items.length; i++)
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: _line, width: .5),
                      ),
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              '${i + 1}. ${rx.items[i].medicine}',
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                            if (rx.items[i].instructions.isNotEmpty)
                              pw.Text(
                                rx.items[i].instructions,
                                style: const pw.TextStyle(
                                  fontSize: 8,
                                  color: _mute,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _td(rx.items[i].dosage),
                      _td(rx.items[i].frequency),
                      _td(rx.items[i].duration),
                    ],
                  ),
              ],
            ),

            // ── advice ──
            if (rx.advice.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                'ADVICE',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _mute,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                rx.advice,
                style: const pw.TextStyle(fontSize: 9, color: _body),
              ),
            ],

            pw.Spacer(),

            // ── precautions ──
            if (rx.care.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _teal, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: double.infinity,
                      color: _tealB,
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'PRECAUTIONS & AFTERCARE',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF0B6B5F),
                            ),
                          ),
                          pw.Text(
                            'پرہیز اور احتیاط',
                            textDirection: pw.TextDirection.rtl,
                            style: pw.TextStyle(
                              font: urdu,
                              fontSize: 11,
                              color: const PdfColor.fromInt(0xFF0B6B5F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.fromLTRB(7, 4, 7, 4),
                      child: pw.Column(
                        children: [
                          for (var i = 0; i < rx.care.length; i++)
                            pw.Container(
                              decoration: i == rx.care.length - 1
                                  ? null
                                  : const pw.BoxDecoration(
                                      border: pw.Border(
                                        bottom: pw.BorderSide(
                                          color: PdfColor.fromInt(0xFFD6F2ED),
                                          width: .4,
                                        ),
                                      ),
                                    ),
                              padding: const pw.EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: pw.Row(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Container(
                                    width: 14,
                                    padding: const pw.EdgeInsets.only(top: 3),
                                    child: pw.Text(
                                      '•',
                                      style: pw.TextStyle(
                                        fontSize: 10,
                                        color: _teal,
                                      ),
                                    ),
                                  ),
                                  pw.Expanded(
                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.stretch,
                                      children: [
                                        if (rx.care[i].urdu.isNotEmpty)
                                          pw.Text(
                                            rx.care[i].urdu,
                                            textAlign: pw.TextAlign.right,
                                            textDirection: pw.TextDirection.rtl,
                                            style: pw.TextStyle(
                                              font: urdu,
                                              fontSize: 11,
                                              color: _ink,
                                              lineSpacing: 2,
                                            ),
                                          ),
                                        if (rx.care[i].english.isNotEmpty)
                                          pw.Text(
                                            rx.care[i].english,
                                            style: const pw.TextStyle(
                                              fontSize: 8.5,
                                              color: PdfColor.fromInt(
                                                0xFF475569,
                                              ),
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
                    ),
                  ],
                ),
              ),
            ],

            // ── signature ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Generated by DentOS · ${_fmt(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 7.5, color: _light),
                  ),
                ),
                pw.Container(
                  width: 165,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: _ink, width: 1.2),
                    ),
                  ),
                  padding: const pw.EdgeInsets.only(top: 5),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        rx.doctorName.isEmpty ? '' : rx.doctorName,
                        style: const pw.TextStyle(fontSize: 8.5, color: _body),
                      ),
                      pw.Text(
                        'Signature & Stamp',
                        style: const pw.TextStyle(fontSize: 7.5, color: _light),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(height: .6, color: _line),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                d.footer,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7.5, color: _light),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _th(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
        color: _mute,
      ),
    ),
  );

  static pw.Widget _td(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: pw.Text(
      t.isEmpty ? '—' : t,
      style: const pw.TextStyle(fontSize: 9, color: _body),
    ),
  );

  static pw.Widget _kv(String k, String v, {bool right = false}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$k: ',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.TextSpan(
            text: v,
            style: const pw.TextStyle(fontSize: 9, color: _body),
          ),
        ],
      ),
    ),
  );

  static String _fmt(DateTime dt) =>
      '${dt.day} '
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]} '
      '${dt.year}';
}
