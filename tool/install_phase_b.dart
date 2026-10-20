// Installs Phase B (daily cash closing + dentist commission) into
// app_database.dart and sync_engine.dart.
//
// Run it from the project folder (the one with pubspec.yaml):
//   dart run tool/install_phase_b.dart
//
// Safe to run more than once: an edit that is already there is skipped.
// If something it needs can't be found, it changes NOTHING and says which
// file to send.
import 'dart:io';

final _log = <String>[];
var _failed = false;

void main() {
  if (!File('pubspec.yaml').existsSync() || !Directory('lib').existsSync()) {
    stderr.writeln(
      '✗ Run this from your project folder (the one with pubspec.yaml).',
    );
    exit(1);
  }

  final db = _find('app_database.dart', 'lib/core/db/app_database.dart');
  final sync = _find('sync_engine.dart', 'lib/cloud/data/sync_engine.dart');
  if (db == null || sync == null) {
    print(_log.join('\n'));
    exit(1);
  }

  final out = <File, String>{};
  for (final (file, patch) in [(db, _patchDb), (sync, _patchSync)]) {
    _log.add('\n${file.path}');
    final before = file.readAsStringSync();
    final after = patch(before);
    if (after != before) out[file] = after;
  }

  print(_log.join('\n'));

  if (_failed) {
    stderr.writeln(
      '\n✗ Nothing was changed. Send Claude the file(s) marked ✗ above.',
    );
    exit(1);
  }
  if (out.isEmpty) {
    print('\n✓ Everything was already installed.');
    return;
  }

  final backup = Directory('phase_b_backup')..createSync();
  for (final e in out.entries) {
    final name = e.key.uri.pathSegments.last;
    e.key.copySync('${backup.path}/$name.bak');
    e.key.writeAsStringSync(e.value);
  }
  print('\n✓ Done. Originals saved in phase_b_backup/');
}

// ═══════════════════════════════ app_database.dart ═══════════════════════════

String _patchDb(String s) {
  s = _addImport(
    s,
    "import 'package:is_dental/features/cash/data/cash_tables.dart';",
  );

  if (RegExp(r'\bCashClosings,').hasMatch(s)) {
    _ok('table list', already: true);
  } else {
    final m = RegExp(r'ToothFindings,\s*\]').allMatches(s).toList();
    if (m.length != 1) {
      _fail(
        'table list (could not find "ToothFindings," before "]" — '
        'is the tooth chart installed?)',
      );
    } else {
      s = s.replaceRange(
        m.first.start,
        m.first.end,
        'ToothFindings,\n    CashClosings,\n    DentistRates,\n  ]',
      );
      _ok('table list');
    }
  }

  if (RegExp(r'schemaVersion\s*=>\s*30\s*;').hasMatch(s)) {
    _ok('schemaVersion 30', already: true);
  } else {
    final m = RegExp(r'schemaVersion\s*=>\s*29\s*;').firstMatch(s);
    if (m == null) {
      _fail('schemaVersion (expected "schemaVersion => 29;")');
    } else {
      s = s.replaceRange(m.start, m.end, 'schemaVersion => 30;');
      _ok('schemaVersion 29 → 30');
    }
  }

  if (s.contains('from < 30')) {
    _ok('migration', already: true);
  } else {
    final m = RegExp(r'if\s*\(\s*from\s*<\s*29\s*\)\s*\{').firstMatch(s);
    final close = m == null ? -1 : _matchingBrace(s, m.end - 1);
    if (close < 0) {
      _fail('migration (could not find the "if (from < 29) {" block)');
    } else {
      s = _insertAt(s, close + 1, _indentOf(s, m!.start), _migration);
      _ok('migration v30');
    }
  }
  return s;
}

const _migration = r'''
if (from < 30) {
  try {
    await m.createTable(cashClosings);
  } catch (_) {}
  try {
    await m.createTable(dentistRates);
  } catch (_) {}
}''';

// ═══════════════════════════════ sync_engine.dart ════════════════════════════

String _patchSync(String s) {
  s = _after(
    s,
    'sync steps',
    marker: "step('cash_closings'",
    anchor: "await step('xray_inventories', () => _syncInventories(clinicId));",
    snippet:
        "await step('cash_closings', () => _syncCashClosings(clinicId));\n"
        "await step('dentist_rates', () => _syncDentistRates(clinicId));",
  );
  s = _after(
    s,
    'wipe list',
    marker: '_db.cashClosings).go()',
    anchor: 'await _db.delete(_db.deviceInventories).go();',
    snippet:
        'await _db.delete(_db.cashClosings).go();\n'
        'await _db.delete(_db.dentistRates).go();',
  );
  // 'pull_inventories', can appear in more than one cursor list (e.g. a
  // reset list and a wipe list) — add the new keys next to every one.
  s = _afterEvery(
    s,
    'cursor keys',
    marker: "'pull_cash_closings'",
    anchor: "'pull_inventories',",
    snippet:
        "'pull_cash_closings',\n'push_cash_closings',\n"
        "'pull_dentist_rates',\n'push_dentist_rates',",
  );
  s = _after(
    s,
    'restore steps',
    marker: "part('cash_closings'",
    anchor:
        "await part('xray_inventories', () => _restoreInventories(clinicId));",
    snippet:
        "await part('cash_closings', () => _restoreCashClosings(clinicId));\n"
        "await part('dentist_rates', () => _restoreDentistRates(clinicId));",
  );

  if (s.contains('Future<void> _syncCashClosings')) {
    _ok('sync methods', already: true);
  } else {
    final m = _flex(
      '// ================= X-RAY LIST (metadata only) =================',
    ).firstMatch(s);
    if (m == null) {
      _fail('sync methods (could not find the "X-RAY LIST" section header)');
    } else {
      final lineStart = s.lastIndexOf('\n', m.start) + 1;
      final ind = _indentOf(s, m.start);
      s = s.replaceRange(lineStart, lineStart, '${_indent(_methods, ind)}\n\n');
      _ok('sync methods');
    }
  }
  return s;
}

const _methods = r'''
// ================= CASH CLOSINGS + DENTIST RATES =================
Future<void> _syncCashClosings(String clinicId) async {
  final since = await _cur('push_cash_closings');
  final changed = await (_db.select(
    _db.cashClosings,
  )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
  if (changed.isNotEmpty) {
    await _sb.from('cash_closings').upsert([
      for (final c in changed)
        {
          'uuid': c.uuid,
          'clinic_id': clinicId,
          'branch_id': c.branchId,
          'day': c.day,
          'opening_float': c.openingFloat,
          'cash_in': c.cashIn,
          'cash_out': c.cashOut,
          'expected': c.expected,
          'counted': c.counted,
          'taken_out': c.takenOut,
          'note': c.note,
          'closed_by_name': c.closedByName,
          'closed_at': _iso(c.closedAt),
          'is_deleted': c.isDeleted,
          'updated_at': _iso(c.updatedAt),
        },
    ], onConflict: 'uuid');
    await _setCur(
      'push_cash_closings',
      _max(changed.map((e) => e.updatedAt)),
    );
  }

  final pullSince = await _cur('pull_cash_closings');
  for (final r in await _pull('cash_closings', clinicId, pullSince)) {
    await _row('cash_closings', r['uuid'], () async {
      await _applyCashClosing(r, clinicId, force: false);
      final u = DateTime.parse(r['updated_at']);
      if (u.isAfter(pullSince)) await _setCur('pull_cash_closings', u);
    });
  }
}

Future<void> _applyCashClosing(
  Map<String, dynamic> r,
  String clinicId, {
  required bool force,
}) async {
  final u = DateTime.parse(r['updated_at']);
  final existing = await (_db.select(
    _db.cashClosings,
  )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
  if (!force && existing != null && !u.isAfter(existing.updatedAt)) return;
  int n(String k) => (r[k] as num?)?.toInt() ?? 0;
  final c = CashClosingsCompanion(
    uuid: Value(r['uuid']),
    clinicId: Value(clinicId),
    branchId: Value(r['branch_id'] ?? ''),
    day: Value(r['day']),
    openingFloat: Value(n('opening_float')),
    cashIn: Value(n('cash_in')),
    cashOut: Value(n('cash_out')),
    expected: Value(n('expected')),
    counted: Value(n('counted')),
    takenOut: Value(n('taken_out')),
    note: Value(r['note'] ?? ''),
    closedByName: Value(r['closed_by_name'] ?? ''),
    closedAt: Value(DateTime.parse(r['closed_at'] ?? r['updated_at'])),
    isDeleted: Value(r['is_deleted'] ?? false),
    updatedAt: Value(u),
  );
  if (existing == null) {
    await _db.into(_db.cashClosings).insert(c);
  } else {
    await (_db.update(
      _db.cashClosings,
    )..where((t) => t.id.equals(existing.id))).write(c);
  }
}

Future<void> _restoreCashClosings(String clinicId) async {
  for (final r in await _pullAll('cash_closings', clinicId)) {
    await _row(
      'cash_closings',
      r['uuid'],
      () => _applyCashClosing(r, clinicId, force: true),
    );
  }
}

Future<void> _syncDentistRates(String clinicId) async {
  final since = await _cur('push_dentist_rates');
  final changed = await (_db.select(
    _db.dentistRates,
  )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
  if (changed.isNotEmpty) {
    await _sb.from('dentist_rates').upsert([
      for (final c in changed)
        {
          'uuid': c.uuid,
          'clinic_id': clinicId,
          'dentist_name': c.dentistName,
          'percent': c.percent,
          'is_deleted': c.isDeleted,
          'updated_at': _iso(c.updatedAt),
        },
    ], onConflict: 'uuid');
    await _setCur(
      'push_dentist_rates',
      _max(changed.map((e) => e.updatedAt)),
    );
  }

  final pullSince = await _cur('pull_dentist_rates');
  for (final r in await _pull('dentist_rates', clinicId, pullSince)) {
    await _row('dentist_rates', r['uuid'], () async {
      await _applyDentistRate(r, clinicId, force: false);
      final u = DateTime.parse(r['updated_at']);
      if (u.isAfter(pullSince)) await _setCur('pull_dentist_rates', u);
    });
  }
}

Future<void> _applyDentistRate(
  Map<String, dynamic> r,
  String clinicId, {
  required bool force,
}) async {
  final u = DateTime.parse(r['updated_at']);
  final existing = await (_db.select(
    _db.dentistRates,
  )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
  if (!force && existing != null && !u.isAfter(existing.updatedAt)) return;
  final c = DentistRatesCompanion(
    uuid: Value(r['uuid']),
    clinicId: Value(clinicId),
    dentistName: Value(r['dentist_name'] ?? ''),
    percent: Value((r['percent'] as num?)?.toDouble() ?? 0),
    isDeleted: Value(r['is_deleted'] ?? false),
    updatedAt: Value(u),
  );
  if (existing == null) {
    await _db.into(_db.dentistRates).insert(c);
  } else {
    await (_db.update(
      _db.dentistRates,
    )..where((t) => t.id.equals(existing.id))).write(c);
  }
}

Future<void> _restoreDentistRates(String clinicId) async {
  for (final r in await _pullAll('dentist_rates', clinicId)) {
    await _row(
      'dentist_rates',
      r['uuid'],
      () => _applyDentistRate(r, clinicId, force: true),
    );
  }
}''';

// ═══════════════════════════════ helpers ═════════════════════════════════════

File? _find(String name, String? preferred) {
  if (preferred != null && File(preferred).existsSync()) return File(preferred);
  final hits = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last == name)
      .toList();
  if (hits.length == 1) return hits.first;
  _log.add(
    hits.isEmpty
        ? '✗ $name not found under lib/'
        : '✗ more than one $name: ${hits.map((f) => f.path).join(', ')}',
  );
  return null;
}

void _ok(String what, {bool already = false}) =>
    _log.add(already ? '  • $what — already there' : '  ✓ $what');

void _fail(String what) {
  _failed = true;
  _log.add('  ✗ $what');
}

/// Matches [anchor] with any amount of whitespace / line breaks between its
/// words, so formatting differences don't matter.
RegExp _flex(String anchor) =>
    RegExp(anchor.trim().split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s*'));

String _indentOf(String s, int index) {
  final lineStart = s.lastIndexOf('\n', index) + 1;
  return RegExp(r'^[ \t]*').firstMatch(s.substring(lineStart))!.group(0)!;
}

String _indent(String snippet, String ind) =>
    snippet.trim().split('\n').map((l) => l.isEmpty ? l : '$ind$l').join('\n');

String _insertAt(String s, int at, String ind, String snippet) =>
    s.replaceRange(at, at, '\n${_indent(snippet, ind)}');

String _after(
  String s,
  String what, {
  required String marker,
  required String anchor,
  required String snippet,
}) {
  if (s.contains(marker)) {
    _ok(what, already: true);
    return s;
  }
  final m = _flex(anchor).allMatches(s).toList();
  if (m.length != 1) {
    _fail(
      '$what (${m.isEmpty ? 'could not find' : 'found ${m.length} times'}: $anchor)',
    );
    return s;
  }
  _ok(what);
  return _insertAt(s, m.first.end, _indentOf(s, m.first.start), snippet);
}

/// Like [_after], but inserts after EVERY occurrence of [anchor].
String _afterEvery(
  String s,
  String what, {
  required String marker,
  required String anchor,
  required String snippet,
}) {
  if (s.contains(marker)) {
    _ok(what, already: true);
    return s;
  }
  final matches = _flex(anchor).allMatches(s).toList();
  if (matches.isEmpty) {
    _fail('$what (could not find: $anchor)');
    return s;
  }
  // Work from the end so earlier positions stay valid.
  for (final m in matches.reversed) {
    s = _insertAt(s, m.end, _indentOf(s, m.start), snippet);
  }
  _ok('$what (${matches.length} place${matches.length == 1 ? '' : 's'})');
  return s;
}

String _addImport(String s, String line) {
  final file = RegExp(r"'([^']+)'").firstMatch(line)!.group(1)!.split('/').last;
  if (s.contains(file)) {
    _ok('import $file', already: true);
    return s;
  }
  final imports = RegExp(r'^import\s[^;]*;', multiLine: true).allMatches(s);
  if (imports.isEmpty) {
    _fail('import $file (no imports found)');
    return s;
  }
  _ok('import $file');
  final end = imports.last.end;
  return s.replaceRange(end, end, '\n$line');
}

/// Index of the `}` closing the `{` at [open], or -1.
int _matchingBrace(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}' && --depth == 0) return i;
  }
  return -1;
}
