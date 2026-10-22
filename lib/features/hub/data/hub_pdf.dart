import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'hub_data.dart';
import 'hub_forecast.dart';

// The built-in PDF font only knows Latin-1: plain hyphens, no ≈ or ▲.

String _rs(int v) =>
    '${v < 0 ? '-' : ''}Rs ${v.abs().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

const _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String _date(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';
String _time(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _pct(int cur, int prev) {
  if (prev <= 0) return '';
  final p = ((cur - prev) / prev * 100).round();
  return p == 0 ? 'same as before' : '${p > 0 ? '+' : ''}$p% vs before';
}

/// The owner report: one A4 document with everything the Hub shows for the
/// chosen branch and period.
Future<Uint8List> buildHubPdf(
  HubData data, {
  required String clinicName,
  required String scopeName,
  required String periodLabel,
  required String preparedFor,
}) async {
  final doc = pw.Document(
    title: 'Owner report - $clinicName',
    author: 'DentOS',
  );
  const ink = PdfColor.fromInt(0xFF0D1626);
  const muted = PdfColor.fromInt(0xFF64748B);
  const line = PdfColor.fromInt(0xFFE2E8F0);
  const accent = PdfColor.fromInt(0xFF0EA5C6);
  const soft = PdfColor.fromInt(0xFFF1F5F9);

  pw.TextStyle st(double size, {bool bold = false, PdfColor color = ink}) =>
      pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

  pw.Widget heading(String text, [String? sub]) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(text, style: st(14, bold: true)),
        if (sub != null) pw.Text(sub, style: st(9, color: muted)),
      ],
    ),
  );

  pw.Widget tiles(List<(String, String, String)> items) => pw.Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final t in items)
        pw.Container(
          width: 160,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: soft,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(t.$1, style: st(8.5, color: muted)),
              pw.SizedBox(height: 3),
              pw.Text(t.$2, style: st(13, bold: true)),
              if (t.$3.isNotEmpty) pw.Text(t.$3, style: st(8, color: muted)),
            ],
          ),
        ),
    ],
  );

  pw.Widget table(
    List<String> head,
    List<List<String>> rows, {
    List<int>? rightCols,
  }) {
    final right = rightCols ?? const <int>[];
    pw.Widget cell(String text, int col, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: right.contains(col) ? pw.TextAlign.right : pw.TextAlign.left,
        style: header ? st(8.5, bold: true, color: muted) : st(9),
      ),
    );
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: line, width: .5),
        bottom: pw.BorderSide(color: line, width: .5),
      ),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: soft),
          children: [
            for (var i = 0; i < head.length; i++)
              cell(head[i], i, header: true),
          ],
        ),
        for (final r in rows)
          pw.TableRow(
            children: [for (var i = 0; i < r.length; i++) cell(r[i], i)],
          ),
      ],
    );
  }

  final t = data.today;
  final m = data.money;
  final f = data.forecast;
  final w = data.watch;
  final h = data.health;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 34, 36, 34),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                '$clinicName · owner report · ${_date(data.loadedAt)}',
                style: st(8, color: muted),
              ),
            ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Confidential · page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: st(8, color: muted),
        ),
      ),
      build: (ctx) => [
        // ── cover block ──
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          // pdf allows rounded corners only with an even border all round,
          // so the accent stripe stays square-cornered
          decoration: const pw.BoxDecoration(
            color: soft,
            border: pw.Border(left: pw.BorderSide(color: accent, width: 4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'DETAILED REPORTING HUB',
                style: st(8, bold: true, color: accent),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Owner report · $clinicName', style: st(18, bold: true)),
              pw.SizedBox(height: 4),
              pw.Text(
                '$scopeName · $periodLabel · prepared ${_date(data.loadedAt)} '
                '${_time(data.loadedAt)} for $preparedFor',
                style: st(9, color: muted),
              ),
            ],
          ),
        ),

        heading('Right now', 'Today and this month so far'),
        tiles([
          (
            'Collected today',
            _rs(t.collected),
            _pct(t.collected, t.lastWeekSameTime),
          ),
          (
            'Patients today',
            '${t.patients}',
            '${t.count('completed')} seen · ${t.count('noShow')} no-show',
          ),
          (
            'Collected this month',
            _rs(t.monthCollected),
            _pct(t.monthCollected, t.lastMonthToDate),
          ),
          (
            'Net profit this month',
            _rs(t.monthNet),
            'after ${_rs(t.monthExpenses)} expenses',
          ),
          (
            'Still owed',
            _rs(t.owedTotal),
            '${t.owedCount} invoices · ${_rs(t.owedOver60)} over 60 days',
          ),
        ]),
        if (data.alerts.isNotEmpty) ...[
          heading('Needs you'),
          table(
            ['Level', 'What', 'Detail'],
            [
              for (final a in data.alerts)
                [
                  switch (a.level) {
                    HubLevel.urgent => 'Urgent',
                    HubLevel.today => 'Today',
                    HubLevel.later => 'When you can',
                  },
                  a.title,
                  a.detail,
                ],
            ],
          ),
        ],

        heading('Money', periodLabel),
        tiles([
          ('Collected', _rs(m.collected), _pct(m.collected, m.prevCollected)),
          ('Expenses', _rs(m.expenses), _pct(m.expenses, m.prevExpenses)),
          ('Net profit', _rs(m.net), _pct(m.net, m.prevNet)),
          ('Billed', _rs(m.billed), '${m.billedCount} invoices'),
        ]),
        if (m.byCategory.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          table(
            ['Expenses by category', 'Amount'],
            [
              for (final c in m.byCategory) [c.name, _rs(c.total)],
            ],
            rightCols: [1],
          ),
        ],
        if (m.byMethod.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          table(
            ['Collected by method', 'Amount'],
            [
              for (final c in m.byMethod) [c.name, _rs(c.total)],
            ],
            rightCols: [1],
          ),
        ],
        pw.SizedBox(height: 10),
        table(
          ['Owed', '0-30 days', '31-60 days', '61-90 days', 'Over 90 days'],
          [
            ['Amount', for (final b in m.owedBuckets) _rs(b)],
            ['Invoices', for (final c in m.owedBucketCounts) '$c'],
          ],
          rightCols: [1, 2, 3, 4],
        ),

        if (data.dentists.isNotEmpty) ...[
          heading('Dentists', periodLabel),
          table(
            [
              'Dentist',
              'Visits',
              'No-shows',
              'Collected',
              'Avg bill',
              'Commission',
              'Still to pay',
            ],
            [
              for (final x in data.dentists)
                [
                  x.name,
                  '${x.completed} / ${x.booked}',
                  '${x.noShows}',
                  _rs(x.collected),
                  _rs(x.avgBill),
                  _rs(x.commission),
                  x.paidKnown ? _rs(x.due > 0 ? x.due : 0) : '-',
                ],
            ],
            rightCols: [1, 2, 3, 4, 5, 6],
          ),
          if (data.unassigned > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                '${_rs(data.unassigned)} collected is not linked to any dentist.',
                style: st(8.5, color: muted),
              ),
            ),
        ],

        heading("What's coming", 'Estimates from the clinic\'s own records'),
        if (!f.ready)
          pw.Text(
            'Forecasts start on ${_date(f.startsOn)} - they need $kForecastMinDays '
            'days of records (${f.dataDays} so far).',
            style: st(9.5, color: muted),
          )
        else ...[
          tiles([
            (
              'This month should end at',
              _rs(f.monthMid),
              '${_rs(f.monthLow)} to ${_rs(f.monthHigh)}',
            ),
            (
              'Next 30 days in',
              _rs(f.in30),
              'usual monthly spending ${_rs(f.out30)}',
            ),
            (
              'Owed likely to come back',
              _rs(f.owedLikely),
              'of ${_rs(f.owedTotal)} owed',
            ),
            (
              'This year should end at',
              _rs(f.yearMid),
              '${_rs(f.yearLow)} to ${_rs(f.yearHigh)}',
            ),
            (
              'Regulars at risk',
              '${f.atRiskTotal}',
              'late for their usual visit',
            ),
          ]),
          pw.SizedBox(height: 10),
          table(
            ['Next 7 days', 'Booked', 'Usual', 'A usual day brings'],
            [
              for (final d in f.week)
                [
                  '${_mon[d.day.month - 1]} ${d.day.day}',
                  d.closed ? 'Closed' : '${d.booked}',
                  d.closed ? '' : d.usual.toStringAsFixed(1),
                  d.closed ? '' : _rs(d.usualMoney),
                ],
            ],
            rightCols: [1, 2, 3],
          ),
          if (f.atRisk.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            table(
              ['Regular at risk', 'Phone', 'Usually every', 'Days since'],
              [
                for (final p in f.atRisk)
                  [p.name, p.phone, '${p.usualGap} days', '${p.daysSince}'],
              ],
              rightCols: [2, 3],
            ),
          ],
        ],

        heading('Watch list', periodLabel),
        tiles([
          ('Discounts', _rs(w.discountTotal), '${w.discountCount} bills'),
          ('Bills cancelled', '${w.cancelledCount}', _rs(w.cancelledTotal)),
          ('Payments removed', '${w.removedCount}', _rs(w.removedTotal)),
          ('Expenses deleted', '${w.deletedCount}', _rs(w.deletedTotal)),
          (
            'Failed sign-ins',
            '${w.failedSignIns}',
            '${w.afterHoursSignIns} outside hours',
          ),
        ]),
        if (w.changes.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          table(
            ['When', 'What', 'Who', 'Amount'],
            [
              for (final c in w.changes.take(25))
                [
                  '${c.at.day} ${_mon[c.at.month - 1]} ${_time(c.at)}',
                  (c.detail.isEmpty ? c.title : '${c.title} - ${c.detail}')
                      .replaceAll('→', '->'),
                  c.who,
                  c.amount == null ? '' : _rs(c.amount!),
                ],
            ],
            rightCols: [3],
          ),
        ],
        if (w.takenBy.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          table(
            ['Money taken by', 'Payments', 'Amount'],
            [
              for (final x in w.takenBy) [x.name, '${x.count}', _rs(x.total)],
            ],
            rightCols: [1, 2],
          ),
        ],

        if (data.branches.isNotEmpty) ...[
          heading('Branches', periodLabel),
          table(
            [
              'Branch',
              'Collected',
              'Expenses',
              'Net',
              'Visits',
              'No-shows',
              'Owed',
              'Last closed',
            ],
            [
              for (final b in data.branches)
                [
                  b.name,
                  _rs(b.collected),
                  _rs(b.expenses),
                  _rs(b.net),
                  '${b.completed}/${b.appts}',
                  '${b.noShows}',
                  _rs(b.owed),
                  b.lastClosed ?? 'never',
                ],
            ],
            rightCols: [1, 2, 3, 4, 5, 6],
          ),
        ],

        heading('System health'),
        table(
          ['Check', 'Status'],
          [
            [
              'Plan',
              '${h.plan}${h.expiresAt == null ? '' : ' until ${_date(h.expiresAt!)}'}',
            ],
            ['Staff logins', '${h.users} of ${h.maxUsers}'],
            ['Branches', '${h.branches} of ${h.maxBranches}'],
            for (final dv in h.devices)
              [
                'Computer ${dv.letter}${dv.name.isEmpty ? '' : ' (${dv.name})'}',
                dv.lastSeen == null
                    ? 'never synced'
                    : 'last sync ${_date(dv.lastSeen!)} ${_time(dv.lastSeen!)}',
              ],
            for (final x in h.wa)
              [
                'WhatsApp · ${x.branch}',
                !x.on
                    ? 'off'
                    : '${x.connected ? 'connected' : 'DISCONNECTED'}'
                          '${x.failed == null ? '' : ' · ${x.failed} failed this week'}',
              ],
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
