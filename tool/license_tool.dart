// DentOS — Licence Tool
//
//   dart run tool/license_tool.dart
//
// Starts a local web UI at http://127.0.0.1:8787 and opens your browser.
// Mint new clinic licences, renew/recover existing ones, and keep a permanent
// record of every clinic id you have ever issued.
//
// ⚠ vendor_keypair.json is your PRIVATE signing key. Never commit it, never
//   ship it inside the app you give clinics.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

const _port = 8787;
const _recordFile = 'tool/clinics.json';
const _keyFile = 'vendor_keypair.json';
const _outFile = 'license.json';
const _envFile = '.env';

({String? url, String? key}) _supabaseCreds() {
  final f = File(_envFile);
  if (!f.existsSync()) return (url: null, key: null);
  String? url, key;
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 0) continue;
    final k = t.substring(0, i).trim();
    final v = t.substring(i + 1).trim();
    if (k == 'SUPABASE_URL') url = v;
    if (k == 'SUPABASE_SERVICE_ROLE_KEY') key = v;
  }
  return (url: url, key: key);
}

// ══════════════════════════════════════════════════════════════
//  CLINIC ID
// ══════════════════════════════════════════════════════════════

/// SMILE-ISL-482913 — first word of the name, city code, 6 random digits.
/// Generated ONCE per clinic. Every renewal reuses it verbatim.
String generateClinicId(String clinicName, String city) {
  final slug = clinicName
      .trim()
      .split(RegExp(r'\s+'))
      .first
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  const cityCodes = <String, String>{
    'islamabad': 'ISL',
    'rawalpindi': 'RWP',
    'lahore': 'LHR',
    'karachi': 'KHI',
    'peshawar': 'PEW',
    'faisalabad': 'FSD',
    'multan': 'MUX',
    'quetta': 'UET',
    'hyderabad': 'HYD',
    'sialkot': 'SKT',
    'gujranwala': 'GUJ',
    'abbottabad': 'ATD',
  };
  final key = city.trim().toLowerCase();
  final code =
      cityCodes[key] ??
      city
          .trim()
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9]'), '')
          .padRight(3, 'X')
          .substring(0, 3);

  final rnd = Random.secure();
  final digits = List.generate(6, (_) => rnd.nextInt(10)).join();
  return '$slug-$code-$digits';
}

// ══════════════════════════════════════════════════════════════
//  SIGNING  (unchanged logic — same canonical payload + RSA/SHA-256)
// ══════════════════════════════════════════════════════════════

String _canonical(Map<String, dynamic> p) => jsonEncode({
  'clinicId': p['clinicId'],
  'clinicName': p['clinicName'],
  'tier': p['tier'],
  'cloudPackage': p['cloudPackage'],
  'maxBranches': p['maxBranches'],
  'maxUsers': p['maxUsers'],
  'issuedAt': (p['issuedAt'] as DateTime).toUtc().toIso8601String(),
  'expiresAt': (p['expiresAt'] as DateTime).toUtc().toIso8601String(),
  'machineFingerprint': p['machineFingerprint'],
});

AsymmetricKeyPair _loadOrCreateKeys() {
  final f = File(_keyFile);
  if (f.existsSync()) {
    final j = jsonDecode(f.readAsStringSync());
    final n = BigInt.parse(j['n']), e = BigInt.parse(j['e']);
    return AsymmetricKeyPair(
      RSAPublicKey(n, e),
      RSAPrivateKey(
        n,
        BigInt.parse(j['d']),
        BigInt.parse(j['p']),
        BigInt.parse(j['q']),
      ),
    );
  }
  final rnd = FortunaRandom()
    ..seed(
      KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        ),
      ),
    );
  final gen = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        rnd,
      ),
    );
  final pair = gen.generateKeyPair();
  final pub = pair.publicKey as RSAPublicKey,
      priv = pair.privateKey as RSAPrivateKey;
  f.writeAsStringSync(
    jsonEncode({
      'n': pub.modulus.toString(),
      'e': pub.exponent.toString(),
      'd': priv.privateExponent.toString(),
      'p': priv.p.toString(),
      'q': priv.q.toString(),
    }),
  );
  stdout.writeln('⚠ Generated $_keyFile — keep it private, never commit it.');
  return pair;
}

Map<String, dynamic> _mintLicence(Map<String, dynamic> fields) {
  final pair = _loadOrCreateKeys();
  final priv = pair.privateKey as RSAPrivateKey;
  final payload = _canonical(fields);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
  final sig = signer.generateSignature(
    Uint8List.fromList(utf8.encode(payload)),
  );
  return {
    ...jsonDecode(payload) as Map<String, dynamic>,
    'signature': base64.encode(sig.bytes),
  };
}

/// Updates the clinic's row in Supabase to match the licence just issued.
///
/// UPDATE only — never inserts. A clinic row is created by `register-clinic`
/// when the clinic first runs setup; if there is no row yet, there is nothing
/// to correct.
///
/// Returns null on success, or a message describing the failure.
Future<String?> _pushToSupabase({
  required String clinicId,
  required String clinicName,
  required String tier,
  required DateTime expiresAt,
}) async {
  final creds = _supabaseCreds();
  if (creds.url == null || creds.key == null) {
    return 'tool/.env is missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.';
  }

  final client = HttpClient();
  try {
    final uri = Uri.parse(
      '${creds.url}/rest/v1/clinics?id=eq.${Uri.encodeComponent(clinicId)}',
    );
    final req = await client.patchUrl(uri);
    req.headers
      ..set('apikey', creds.key!)
      ..set('Authorization', 'Bearer ${creds.key}')
      ..set('Content-Type', 'application/json')
      ..set('Prefer', 'return=representation');
    req.write(
      jsonEncode({
        'name': clinicName,
        'tier': tier,
        'status': 'active',
        'expires_at': expiresAt.toUtc().toIso8601String(),
      }),
    );

    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return 'Supabase returned ${res.statusCode}: $body';
    }
    final rows = jsonDecode(body) as List;
    if (rows.isEmpty) {
      return 'No clinic row found for $clinicId. '
          'The row is created when the clinic first runs setup — '
          'this is expected for a brand-new clinic.';
    }
    return null;
  } catch (e) {
    return '$e';
  } finally {
    client.close();
  }
}

// ══════════════════════════════════════════════════════════════
//  CLINIC RECORD  (tool/clinics.json)
// ══════════════════════════════════════════════════════════════

List<Map<String, dynamic>> _loadRecord() {
  final f = File(_recordFile);
  if (!f.existsSync()) return [];
  try {
    return (jsonDecode(f.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
}

void _saveRecord(List<Map<String, dynamic>> rows) {
  final f = File(_recordFile);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
}

/// Upsert by clinicId — one row per clinic, with a history of every issue.
void _recordIssue({
  required String clinicId,
  required String clinicName,
  required String city,
  required String email,
  required String tier,
  required String cloudPackage,
  required int maxBranches,
  required int maxUsers,
  required DateTime issuedAt,
  required DateTime expiresAt,
  required bool isRenewal,
}) {
  final rows = _loadRecord();
  final idx = rows.indexWhere((r) => r['clinicId'] == clinicId);
  final issue = {
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'tier': tier,
    'cloudPackage': cloudPackage,
    'maxBranches': maxBranches,
    'maxUsers': maxUsers,
    'kind': isRenewal ? 'renewal' : 'new',
  };

  if (idx >= 0) {
    final r = rows[idx];
    r['clinicName'] = clinicName;
    if (city.isNotEmpty) r['city'] = city;
    if (email.isNotEmpty) r['email'] = email;
    r['tier'] = tier;
    r['cloudPackage'] = cloudPackage;
    r['maxBranches'] = maxBranches;
    r['maxUsers'] = maxUsers;
    r['expiresAt'] = expiresAt.toIso8601String();
    r['lastIssuedAt'] = issuedAt.toIso8601String();
    (r['history'] as List).insert(0, issue);
  } else {
    rows.insert(0, {
      'clinicId': clinicId,
      'clinicName': clinicName,
      'city': city,
      'email': email,
      'tier': tier,
      'cloudPackage': cloudPackage,
      'maxBranches': maxBranches,
      'maxUsers': maxUsers,
      'firstIssuedAt': issuedAt.toIso8601String(),
      'lastIssuedAt': issuedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'history': [issue],
    });
  }
  _saveRecord(rows);
}

// ══════════════════════════════════════════════════════════════
//  SERVER
// ══════════════════════════════════════════════════════════════

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
  final url = 'http://127.0.0.1:$_port';

  stdout.writeln('');
  stdout.writeln('  DentOS Licence Tool');
  stdout.writeln('  $url');
  stdout.writeln('  Ctrl-C to stop.');
  stdout.writeln('');

  _openBrowser(url);

  await for (final req in server) {
    try {
      switch ('${req.method} ${req.uri.path}') {
        case 'GET /':
          _send(req, _html, type: 'text/html; charset=utf-8');
        case 'GET /api/clinics':
          _json(req, {'ok': true, 'clinics': _loadRecord()});
        case 'POST /api/mint':
          await _handleMint(req);
        case 'POST /api/reset':
          await _handleReset(req);
        default:
          req.response.statusCode = 404;
          await req.response.close();
      }
    } catch (e) {
      try {
        _json(req, {'ok': false, 'error': '$e'}, status: 500);
      } catch (_) {}
    }
  }
}

Future<void> _handleMint(HttpRequest req) async {
  final body =
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;

  final isRenewal = body['mode'] == 'renewal';
  final clinicName = (body['clinicName'] ?? '').toString().trim();
  final city = (body['city'] ?? '').toString().trim();
  final email = (body['email'] ?? '').toString().trim();
  final tier = (body['tier'] ?? 'basic').toString();
  final cloudPackage = (body['cloudPackage'] ?? 'cloud').toString();
  final maxBranches = int.tryParse('${body['maxBranches']}') ?? 1;
  final maxUsers = int.tryParse('${body['maxUsers']}') ?? 3;
  final days = int.tryParse('${body['validDays']}') ?? 365;

  if (clinicName.isEmpty) {
    return _json(req, {'ok': false, 'error': 'Clinic name is required.'});
  }

  late final String clinicId;
  if (isRenewal) {
    clinicId = (body['clinicId'] ?? '').toString().trim();
    if (clinicId.isEmpty) {
      return _json(req, {
        'ok': false,
        'error': 'Select the existing clinic to renew.',
      });
    }
  } else {
    if (city.isEmpty) {
      return _json(req, {
        'ok': false,
        'error': 'City is required for a new clinic.',
      });
    }
    clinicId = generateClinicId(clinicName, city);
  }

  final issuedAt = DateTime.now();
  final expiresAt = issuedAt.add(Duration(days: days));

  final licence = _mintLicence({
    'clinicId': clinicId,
    'clinicName': clinicName,
    'tier': tier,
    'cloudPackage': cloudPackage,
    'maxBranches': maxBranches,
    'maxUsers': maxUsers,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'machineFingerprint': 'ANY',
  });

  final pretty = const JsonEncoder.withIndent('  ').convert(licence);

  // ── cloud licences must reach Supabase, or we don't issue at all ──
  String? cloudNote;
  if (cloudPackage == 'cloud') {
    final err = await _pushToSupabase(
      clinicId: clinicId,
      clinicName: clinicName,
      tier: tier,
      expiresAt: expiresAt,
    );
    if (err != null) {
      if (isRenewal) {
        // an existing cloud clinic MUST have its row corrected, or the
        // heartbeat will judge them against the old plan and lock them out
        stdout.writeln('CLOUD PUSH FAILED  $clinicId  ·  $err');
        return _json(req, {
          'ok': false,
          'error':
              'Could not update Supabase.\n\n$err\n\n'
              'No licence was issued. Fix this first — otherwise the clinic '
              'would hold a valid licence while the cloud still shows the old '
              'plan, and the heartbeat would lock them out.',
        });
      }
      // brand-new clinic: no row exists yet, which is normal
      cloudNote =
          'No Supabase row yet — it is created when the clinic runs '
          'setup. Re-issue as a renewal afterwards to sync the plan.';
    }
  }

  File(_outFile).writeAsStringSync(pretty);

  _recordIssue(
    clinicId: clinicId,
    clinicName: clinicName,
    city: city,
    email: email,
    tier: tier,
    cloudPackage: cloudPackage,
    maxBranches: maxBranches,
    maxUsers: maxUsers,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    isRenewal: isRenewal,
  );

  stdout.writeln(
    '${isRenewal ? "RENEWAL" : "NEW"}  $clinicId  ·  $clinicName'
    '  ·  $tier/$cloudPackage  ·  expires ${expiresAt.toIso8601String().split("T").first}'
    '${cloudPackage == "cloud" && cloudNote == null ? "  ·  cloud updated" : ""}',
  );

  _json(req, {
    'ok': true,
    'clinicId': clinicId,
    'isRenewal': isRenewal,
    'licence': pretty,
    'expiresAt': expiresAt.toIso8601String(),
    'cloudNote': cloudNote,
    'cloudUpdated': cloudPackage == 'cloud' && cloudNote == null,
    'clinics': _loadRecord(),
  });
}

Future<void> _handleReset(HttpRequest req) async {
  final body =
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
  final clinicId = (body['clinicId'] ?? '').toString().trim();
  final hours = int.tryParse('${body['validHours']}') ?? 24;
  if (clinicId.isEmpty) {
    return _json(req, {'ok': false, 'error': 'Select a clinic.'});
  }

  final rnd = Random.secure();
  final nonce = List.generate(
    16,
    (_) => rnd.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final issuedAt = DateTime.now();
  final expiresAt = issuedAt.add(Duration(hours: hours));

  // field order must match ResetToken.canonicalPayload() exactly
  final payload = jsonEncode({
    'action': 'ownerReset',
    'clinicId': clinicId,
    'nonce': nonce,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  });

  final pair = _loadOrCreateKeys();
  final priv = pair.privateKey as RSAPrivateKey;
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
  final sig = signer.generateSignature(
    Uint8List.fromList(utf8.encode(payload)),
  );

  final token = {
    ...jsonDecode(payload) as Map<String, dynamic>,
    'signature': base64.encode(sig.bytes),
  };
  final pretty = const JsonEncoder.withIndent('  ').convert(token);

  stdout.writeln('RESET  $clinicId  ·  expires ${expiresAt.toIso8601String()}');
  _json(req, {'ok': true, 'token': pretty, 'clinicId': clinicId});
}

void _send(HttpRequest req, String body, {String type = 'text/plain'}) {
  req.response
    ..headers.contentType = ContentType.parse(type)
    ..write(body);
  req.response.close();
}

void _json(HttpRequest req, Object body, {int status = 200}) {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  req.response.close();
}

void _openBrowser(String url) {
  try {
    if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      Process.run('xdg-open', [url]);
    }
  } catch (_) {
    stdout.writeln('Open $url in your browser.');
  }
}

// ══════════════════════════════════════════════════════════════
//  UI
// ══════════════════════════════════════════════════════════════

const _html = r'''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DentOS — Licence Tool</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700&family=Manrope:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root{
    --bg:#eef3f9;--surface:#fff;--surface-2:#f6f9fc;
    --t1:#0d1626;--t2:#33415c;--t3:#64748b;--t4:#94a3b8;
    --line:#e6edf5;--ice:#38bdf8;--teal:#13e0c4;--teal-deep:#0bb6a0;
    --ok:#15803d;--warn:#b45309;--alert:#be123c;
    --shadow:0 1px 2px rgba(13,22,38,.05),0 12px 32px rgba(13,22,38,.07);
  }
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Manrope',sans-serif;color:var(--t1);min-height:100vh;padding:24px;
    background:radial-gradient(1100px 520px at 80% -10%,rgba(56,189,248,.13),transparent 58%),
               radial-gradient(900px 480px at 2% 110%,rgba(19,224,196,.10),transparent 55%),var(--bg);}
  .wrap{max-width:1240px;margin:0 auto}
  header{display:flex;align-items:center;gap:12px;margin-bottom:20px}
  .logo{width:40px;height:40px;border-radius:11px;display:grid;place-items:center;
    background:linear-gradient(135deg,var(--ice),var(--teal));color:#04121f;
    font-family:'Sora';font-weight:700;font-size:19px}
  h1{font-family:'Sora';font-size:21px;font-weight:600}
  .sub{color:var(--t3);font-size:13px;margin-top:2px}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:18px;align-items:start}
  @media(max-width:1000px){.grid{grid-template-columns:1fr}}
  .card{background:var(--surface);border:1px solid var(--line);border-radius:18px;box-shadow:var(--shadow);overflow:hidden}
  .ch{padding:16px 18px;border-bottom:1px solid var(--line);display:flex;align-items:center;gap:10px}
  .ch h2{font-family:'Sora';font-size:15px;font-weight:600}
  .ch .s{color:var(--t4);font-size:12px;margin-top:2px}
  .ch .spacer{margin-left:auto}
  .body{padding:18px}
  .seg{display:flex;background:var(--surface-2);border:1px solid var(--line);border-radius:12px;padding:4px;margin-bottom:18px}
  .seg button{flex:1;border:none;background:none;padding:10px;border-radius:9px;cursor:pointer;
    font-family:'Manrope';font-weight:600;font-size:13px;color:var(--t3)}
  .seg button.on{background:linear-gradient(135deg,var(--t1),#1d2c46);color:#fff}
  label{display:block;font-size:10.5px;font-weight:700;letter-spacing:.5px;text-transform:uppercase;
    color:var(--t4);margin:14px 0 6px}
  input,select{width:100%;height:44px;border-radius:11px;border:1px solid var(--line);background:var(--surface-2);
    padding:0 13px;font-family:'Manrope';font-size:13.5px;color:var(--t1);outline:none}
  input:focus,select:focus{border-color:var(--ice);box-shadow:0 0 0 3px rgba(56,189,248,.13);background:#fff}
  input[readonly]{background:#eef3f9;color:var(--t3);font-family:'JetBrains Mono';font-size:12.5px}
  .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
  .row3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px}
  .btn{height:46px;width:100%;border:none;border-radius:12px;cursor:pointer;font-family:'Manrope';
    font-weight:700;font-size:14px;margin-top:20px;
    background:linear-gradient(135deg,var(--ice),var(--teal-deep));color:#04121f;
    box-shadow:0 8px 22px rgba(19,224,196,.3)}
  .btn:disabled{background:var(--line);color:var(--t4);box-shadow:none;cursor:not-allowed}
  .note{padding:11px 13px;border-radius:11px;font-size:12.5px;line-height:1.55;margin-top:14px}
  .n-ice{background:rgba(56,189,248,.09);border:1px solid rgba(56,189,248,.3);color:var(--t2)}
  .n-warn{background:rgba(245,158,11,.10);border:1px solid rgba(245,158,11,.4);color:#92400e}
  .n-ok{background:rgba(34,197,94,.10);border:1px solid rgba(34,197,94,.35);color:#166534}
  .n-alert{background:rgba(190,18,60,.07);border:1px solid rgba(190,18,60,.3);color:#9f1239}
  .search{height:40px;margin-bottom:10px}
  .list{max-height:560px;overflow-y:auto}
  .clinic{padding:13px 18px;border-bottom:1px solid var(--line);cursor:pointer}
  .clinic:last-child{border-bottom:none}
  .clinic:hover{background:var(--surface-2)}
  .clinic .top{display:flex;align-items:center;gap:8px}
  .clinic b{font-size:13.5px;color:var(--t1)}
  .clinic .id{font-family:'JetBrains Mono';font-size:11.5px;color:var(--ice);margin-top:3px}
  .clinic .meta{font-size:11.5px;color:var(--t4);margin-top:3px}
  .pill{font-size:10.5px;font-weight:700;padding:2px 8px;border-radius:20px;text-transform:uppercase;letter-spacing:.3px}
  .p-basic{background:rgba(100,116,139,.15);color:#475569}
  .p-standard{background:rgba(56,189,248,.16);color:#0284c7}
  .p-premium{background:rgba(19,224,196,.18);color:#0b8c7c}
  .p-none{background:rgba(148,163,184,.2);color:#64748b}
  .p-exp{background:rgba(190,18,60,.12);color:#be123c}
  .p-soon{background:rgba(245,158,11,.16);color:#b45309}
  .copy{border:1px solid var(--line);background:#fff;border-radius:8px;padding:4px 9px;cursor:pointer;
    font-size:11px;font-family:'Manrope';font-weight:600;color:var(--t3)}
  .copy:hover{border-color:var(--ice);color:var(--t1)}
  .out{margin-top:16px}
  .out pre{background:#0d1626;color:#cbd5e1;border-radius:12px;padding:14px;font-family:'JetBrains Mono';
    font-size:11.5px;line-height:1.65;overflow-x:auto;max-height:300px}
  .empty{padding:40px 18px;text-align:center;color:var(--t4);font-size:13px}
  /* modal */
  .mask{position:fixed;inset:0;background:rgba(13,22,38,.45);display:none;place-items:center;z-index:99;padding:20px}
  .mask.on{display:grid}
  .modal{background:#fff;border-radius:18px;max-width:460px;width:100%;padding:24px;box-shadow:0 24px 60px rgba(13,22,38,.3)}
  .modal h3{font-family:'Sora';font-size:17px;margin-bottom:8px}
  .modal p{font-size:13px;color:var(--t2);line-height:1.6}
  .modal .acts{display:flex;gap:10px;justify-content:flex-end;margin-top:20px}
  .modal button{height:42px;padding:0 18px;border-radius:11px;cursor:pointer;font-family:'Manrope';font-weight:600;font-size:13px}
  .modal .cancel{background:#fff;border:1px solid var(--line);color:var(--t2)}
  .modal .go{border:none;background:var(--alert);color:#fff}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">D</div>
    <div><h1>DentOS Licence Tool</h1>
      <div class="sub">Mint new clinic licences · renew · recover after a reinstall</div></div>
  </header>

  <div class="grid">
    <!-- ══ FORM ══ -->
    <div class="card">
      <div class="ch"><div><h2>Issue a licence</h2>
        <div class="s">Writes license.json and records the clinic id</div></div></div>
      <div class="body">
        <div class="seg">
          <button id="tabNew" class="on" onclick="setMode('new')">New clinic</button>
          <button id="tabRen" onclick="setMode('renewal')">Renewal / recovery</button>
        </div>

        <div id="renewalBox" style="display:none">
          <label>Existing clinic</label>
          <select id="existing" onchange="pickExisting()">
            <option value="">— select —</option>
          </select>
          <label>Clinic ID (reused verbatim)</label>
          <input id="clinicIdOut" readonly placeholder="select a clinic above">
          <div class="note n-ice">Renewing reuses the clinic's existing id, which is what
            lets them restore their data after a reinstall or a dead machine.</div>
        </div>

        <label>Clinic name</label>
        <input id="clinicName" placeholder="Fast Dental Clinic">

        <div id="cityBox">
          <label>City</label>
          <input id="city" placeholder="Islamabad" value="Islamabad">
        </div>

        <label>Owner email <span style="text-transform:none;letter-spacing:0;color:#94a3b8">— for your records</span></label>
        <input id="email" placeholder="owner@clinic.pk">

        <div class="row">
          <div><label>Tier</label>
            <select id="tier">
              <option value="basic">Basic</option>
              <option value="standard">Standard</option>
              <option value="premium" selected>Premium</option>
            </select></div>
          <div><label>Cloud package</label>
            <select id="cloudPackage">
              <option value="cloud" selected>Cloud</option>
              <option value="none">None (offline)</option>
            </select></div>
        </div>

        <div class="row3">
          <div><label>Branches</label><input id="maxBranches" type="number" min="1" value="1"></div>
          <div><label>Users</label><input id="maxUsers" type="number" min="1" value="3"></div>
          <div><label>Valid (days)</label><input id="validDays" type="number" min="1" value="365"></div>
        </div>
        <div id="expiryHint" class="note n-ice" style="margin-top:12px"></div>

        <button class="btn" id="mintBtn" onclick="preflight()">Generate licence</button>
        <div id="result"></div>
      </div>
    </div>

    <!-- ══ CLINICS ══ -->
    <div class="card">
      <div class="ch"><div><h2>Clinics</h2>
        <div class="s" id="count">—</div></div>
        <div class="spacer"></div>
        <button class="copy" onclick="exportCsv()">Export CSV</button></div>
      <div class="body" style="padding-bottom:10px">
        <input class="search" id="q" placeholder="Search name, id or email…" oninput="render()">
        <div class="note n-warn">Every clinic id here must be reused for that clinic's
          renewals. A new id makes them a different clinic and their data becomes unreachable.</div>
      </div>
      <div class="list" id="list"></div>
    </div>
  </div>
        <div class="list" id="list"></div>
    </div>
  </div>

  <div class="card" style="margin-top:18px">
    <div class="ch"><div><h2>Owner password reset</h2>
      <div class="s">Verify who you are speaking to before issuing one</div></div></div>
    <div class="body">
      <div class="note n-warn">A reset code lets someone set a new owner
        password, which is full access to that clinic's patient records.
        Confirm the caller's identity first — call back on the number you
        have on file.</div>
      <label>Clinic</label>
      <select id="rsClinic"><option value="">— select —</option></select>
      <label>Valid for (hours)</label>
      <input id="rsHours" type="number" min="1" value="24">
      <button class="btn" onclick="genReset()">Generate reset code</button>
      <div id="rsOut"></div>
    </div>
  </div>
</div>
</div>

<!-- confirmation modal -->
<div class="mask" id="mask">
  <div class="modal">
    <h3 id="mTitle">Confirm</h3>
    <p id="mBody"></p>
    <div class="acts">
      <button class="cancel" onclick="closeModal()">Cancel</button>
      <button class="go" id="mGo" onclick="confirmed()">Continue</button>
    </div>
  </div>
</div>

<script>
let clinics = [];
let mode = 'new';

const $ = id => document.getElementById(id);

async function load(){
  const r = await fetch('/api/clinics'); const j = await r.json();
  clinics = j.clinics || [];
  fillExisting();
  fillResetClinics();     // ← ADD
  render();
}


async function genReset(){
  const clinicId = document.getElementById('rsClinic').value;
  if(!clinicId){ alert('Select the clinic.'); return; }
  const hours = document.getElementById('rsHours').value;
  const out = document.getElementById('rsOut');
  out.innerHTML = '<div class="note n-ice" style="margin-top:14px">Signing…</div>';
  try{
    const r = await fetch('/api/reset', {
      method:'POST',
      body: JSON.stringify({ clinicId: clinicId, validHours: hours })
    });
    const j = await r.json();
    if(!j.ok){
      out.innerHTML = '<div class="note n-alert" style="margin-top:14px">' + esc(j.error) + '</div>';
      return;
    }
    window._lastResetToken = j.token;
    out.innerHTML =
      '<div class="note n-ok" style="margin-top:14px">Reset code for <b>' +
      esc(j.clinicId) + '</b> — send it to the clinic.</div>' +
      '<div style="margin:10px 0"><button class="copy" onclick="copyReset()">Copy reset code</button></div>' +
      '<pre>' + esc(j.token) + '</pre>';
  }catch(e){
    out.innerHTML = '<div class="note n-alert" style="margin-top:14px">' + e + '</div>';
  }
}

function copyReset(){
  navigator.clipboard.writeText(window._lastResetToken || '');
}


function setMode(m){
  mode = m;
  $('tabNew').classList.toggle('on', m==='new');
  $('tabRen').classList.toggle('on', m==='renewal');
  $('renewalBox').style.display = m==='renewal' ? 'block' : 'none';
  $('cityBox').style.display = m==='renewal' ? 'none' : 'block';
  $('mintBtn').textContent = m==='renewal' ? 'Issue renewal' : 'Generate licence';
}

function fillExisting(){
  const s = $('existing');
  s.innerHTML = '<option value="">— select —</option>' +
    clinics.map(c=>`<option value="${c.clinicId}">${esc(c.clinicName)} · ${c.clinicId}</option>`).join('');
}

function pickExisting(){
  const id = $('existing').value;
  const c = clinics.find(x=>x.clinicId===id);
  $('clinicIdOut').value = id || '';
  if(c){
    $('clinicName').value = c.clinicName || '';
    $('email').value = c.email || '';
    $('tier').value = c.tier || 'basic';
    $('cloudPackage').value = c.cloudPackage || 'cloud';
    $('maxBranches').value = c.maxBranches || 1;
    $('maxUsers').value = c.maxUsers || 3;
  }
}

function esc(s){ return (s||'').replace(/[&<>"]/g, m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m])); }

function daysLeft(iso){
  return Math.ceil((new Date(iso) - new Date())/86400000);
}

function render(){
  const q = ($('q').value||'').toLowerCase();
  const rows = clinics.filter(c =>
    !q || (c.clinicName||'').toLowerCase().includes(q) ||
    (c.clinicId||'').toLowerCase().includes(q) ||
    (c.email||'').toLowerCase().includes(q));
  $('count').textContent = `${clinics.length} clinic${clinics.length===1?'':'s'} on record`;
  $('list').innerHTML = rows.length===0
    ? `<div class="empty">${clinics.length===0
        ? 'No clinics yet. Issue your first licence and it will be recorded here.'
        : 'No match.'}</div>`
    : rows.map(c=>{
        const dl = daysLeft(c.expiresAt);
        const exp = dl < 0 ? `<span class="pill p-exp">expired</span>`
                  : dl <= 30 ? `<span class="pill p-soon">${dl}d left</span>` : '';
        const cloud = c.cloudPackage==='none' ? `<span class="pill p-none">offline</span>` : '';
        return `<div class="clinic" onclick="renewThis('${c.clinicId}')">
          <div class="top">
            <b>${esc(c.clinicName)}</b>
            <span class="pill p-${c.tier}">${c.tier}</span>${cloud}${exp}
            <span style="margin-left:auto"></span>
            <button class="copy" onclick="event.stopPropagation();copyId('${c.clinicId}')">Copy ID</button>
          </div>
          <div class="id">${c.clinicId}</div>
          <div class="meta">${esc(c.email||'no email on record')} ·
            ${c.maxBranches} branch(es) · ${c.maxUsers} users ·
            expires ${(c.expiresAt||'').split('T')[0]} ·
            ${(c.history||[]).length} issue(s)</div>
        </div>`;
      }).join('');
}

function renewThis(id){
  setMode('renewal');
  $('existing').value = id;
  pickExisting();
  window.scrollTo({top:0,behavior:'smooth'});
}

function copyId(id){
  navigator.clipboard.writeText(id);
}

function updateExpiry(){
  const d = parseInt($('validDays').value||'0',10);
  const dt = new Date(Date.now() + d*86400000);
  $('expiryHint').textContent = d>0
    ? `Expires ${dt.toDateString()}  (${d} days from today)`
    : 'Enter a number of days.';
}
$('validDays').addEventListener('input', updateExpiry);

// ── confirmation ──
let pending = null;
function showModal(title, body, goLabel){
  $('mTitle').textContent = title;
  $('mBody').innerHTML = body;
  $('mGo').textContent = goLabel;
  $('mask').classList.add('on');
}
function closeModal(){ $('mask').classList.remove('on'); pending=null; }
function confirmed(){ const p = pending; closeModal(); if(p) mint(); }

function preflight(){
  const name = $('clinicName').value.trim();
  if(!name) return alert('Enter a clinic name.');

  if(mode==='renewal'){
    const id = $('clinicIdOut').value;
    if(!id) return alert('Select the clinic you are renewing.');
    const c = clinics.find(x=>x.clinicId===id);
    const newTier = $('tier').value, newCloud = $('cloudPackage').value;
    const warn = [];
    const rank = {basic:0, standard:1, premium:2};
    if(c && rank[newTier] < rank[c.tier])
      warn.push(`Tier drops from <b>${c.tier}</b> to <b>${newTier}</b> — the clinic loses those features.`);
    if(c && c.cloudPackage==='cloud' && newCloud==='none')
      warn.push(`Cloud package removed — sync, the patient app and reminders stop working.`);
    if(c && parseInt($('maxBranches').value) < (c.maxBranches||1))
      warn.push(`Branch limit drops from <b>${c.maxBranches}</b> to <b>${$('maxBranches').value}</b>.`);
    if(c && parseInt($('maxUsers').value) < (c.maxUsers||1))
      warn.push(`User limit drops from <b>${c.maxUsers}</b> to <b>${$('maxUsers').value}</b>.`);

    if(warn.length){
      pending = true;
      return showModal('This renewal downgrades the clinic',
        warn.map(w=>'• '+w).join('<br>') +
        '<br><br>Existing data is kept, but the clinic will lose access to the features above.',
        'Issue anyway');
    }
    pending = true;
    return showModal('Issue renewal?',
      `Reusing clinic id <b>${id}</b> for <b>${esc(name)}</b>.<br>` +
      `New expiry: ${new Date(Date.now()+parseInt($('validDays').value)*86400000).toDateString()}`,
      'Issue renewal');
  }

  // new clinic — warn if the name already exists
  const dupe = clinics.find(c =>
    (c.clinicName||'').trim().toLowerCase() === name.toLowerCase());
  if(dupe){
    pending = true;
    return showModal('A clinic with this name already exists',
      `<b>${esc(dupe.clinicName)}</b> is already on record as <b>${dupe.clinicId}</b>.<br><br>` +
      `If this is the same clinic, use <b>Renewal / recovery</b> instead — generating a new id ` +
      `would make them a separate clinic and their existing data would be unreachable.`,
      'Create a new clinic anyway');
  }
  mint();
}
function fillResetClinics(){
  const s = document.getElementById('rsClinic');
  if(!s) return;
  s.innerHTML = '<option value="">— select —</option>' +
    clinics.map(c=>`<option value="${c.clinicId}">${esc(c.clinicName)} · ${c.clinicId}</option>`).join('');
}

async function mint(){
  const btn = $('mintBtn');
  btn.disabled = true; btn.textContent = 'Signing…';
  const payload = {
    mode,
    clinicId: $('clinicIdOut').value,
    clinicName: $('clinicName').value.trim(),
    city: $('city').value.trim(),
    email: $('email').value.trim(),
    tier: $('tier').value,
    cloudPackage: $('cloudPackage').value,
    maxBranches: $('maxBranches').value,
    maxUsers: $('maxUsers').value,
    validDays: $('validDays').value,
  };
  try{
    const r = await fetch('/api/mint', {method:'POST',body:JSON.stringify(payload)});
    const j = await r.json();
    if(!j.ok){ $('result').innerHTML = `<div class="note n-alert">${esc(j.error)}</div>`; }
           else{
      clinics = j.clinics || clinics; fillExisting(); fillResetClinics(); render();
            const cloudLine = j.cloudUpdated
        ? '<br>Supabase clinic row updated.'
        : (j.cloudNote ? `<br><span style="color:#92400e">${esc(j.cloudNote)}</span>` : '');
      $('result').innerHTML = `
        <div class="out">
          <div class="note n-ok">
            <b>${j.isRenewal ? 'Renewal issued' : 'New clinic created'}</b><br>
            Clinic ID: <b style="font-family:JetBrains Mono">${j.clinicId}</b><br>
            Written to <b>license.json</b> and recorded.${cloudLine}
          </div>
          <div style="display:flex;gap:8px;margin:12px 0">
            <button class="copy" onclick="navigator.clipboard.writeText(\`${j.licence.replace(/`/g,'\\`')}\`)">Copy licence JSON</button>
            <button class="copy" onclick="copyId('${j.clinicId}')">Copy clinic ID</button>
          </div>
          <pre>${esc(j.licence)}</pre>
        </div>`;
    }
  }catch(e){
    $('result').innerHTML = `<div class="note n-alert">${e}</div>`;
  }
  btn.disabled = false;
  btn.textContent = mode==='renewal' ? 'Issue renewal' : 'Generate licence';
}

function exportCsv(){
  const head = 'clinicId,clinicName,city,email,tier,cloudPackage,maxBranches,maxUsers,firstIssuedAt,lastIssuedAt,expiresAt';
  const rows = clinics.map(c=>[c.clinicId,c.clinicName,c.city,c.email,c.tier,c.cloudPackage,
    c.maxBranches,c.maxUsers,c.firstIssuedAt,c.lastIssuedAt,c.expiresAt]
    .map(v=>`"${(v??'').toString().replace(/"/g,'""')}"`).join(','));
  const blob = new Blob([[head,...rows].join('\n')],{type:'text/csv'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'dentos-clinics.csv';
  a.click();
}

updateExpiry();
load();
</script>
</body>
</html>
''';
