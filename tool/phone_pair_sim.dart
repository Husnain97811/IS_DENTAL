// ═════════════════════════════════════════════════════════════════════
//  Phone simulator — tests "Connect a phone" before the owner app exists.
//  It does exactly what the real phone app will do.
//
//  1. On the computer: Settings → Connected phones → Connect a phone →
//     Hub PIN → (debug build) "Copy for simulator".
//  2. In a terminal, from the project folder:
//       dart run tool/phone_pair_sim.dart pair "<pasted code>" 03001234567
//     It shows a 6-digit code — compare it with the computer, press Approve.
//  3. Afterwards:
//       dart run tool/phone_pair_sim.dart ping
//       dart run tool/phone_pair_sim.dart unlock 1234
//
//  Needs SUPABASE_URL (and optionally SUPABASE_ANON_KEY) in tool/.env.
//  The simulator's key is saved in tool/.phone_sim.json — never commit it.
// ═════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const _stateFile = 'tool/.phone_sim.json';

/// SPKI header for a P-256 public key; the 65-byte point follows it.
final _spkiHeader = Uint8List.fromList([
  0x30,
  0x59,
  0x30,
  0x13,
  0x06,
  0x07,
  0x2a,
  0x86,
  0x48,
  0xce,
  0x3d,
  0x02,
  0x01,
  0x06,
  0x08,
  0x2a,
  0x86,
  0x48,
  0xce,
  0x3d,
  0x03,
  0x01,
  0x07,
  0x03,
  0x42,
  0x00,
]);

final _curve = ECDomainParameters('secp256r1');

Future<void> main(List<String> args) async {
  if (args.isEmpty) return _usage();
  final env = _env();
  final url = env['SUPABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('tool/.env has no SUPABASE_URL.');
    exit(1);
  }
  final api = _Api(
    '$url/functions/v1/owner-pair-phone',
    env['SUPABASE_ANON_KEY'],
  );

  switch (args[0]) {
    case 'pair':
      if (args.length < 3) return _usage();
      await _pair(api, args[1], args[2]);
    case 'ping':
      final r = await _signed(api, 'ping', '');
      stdout.writeln(
        r['ok'] == true
            ? '✓ Connected to ${r['clinic_name']} as ${r['model']}.'
            : '✗ ${r['error']}',
      );
    case 'unlock':
      if (args.length < 2) return _usage();
      final r = await _signed(api, 'unlock', jsonEncode({'pin': args[1]}));
      stdout.writeln(
        r['ok'] == true
            ? '✓ Hub PIN accepted — the app would open.'
            : '✗ ${r['error']}${r['tries_left'] != null ? ' (${r['tries_left']} tries left)' : ''}',
      );
    default:
      _usage();
  }
  exit(0);
}

void _usage() {
  stdout.writeln('''
Usage:
  dart run tool/phone_pair_sim.dart pair "<code from the computer>" <owner mobile>
  dart run tool/phone_pair_sim.dart ping
  dart run tool/phone_pair_sim.dart unlock <hub pin>''');
  exit(64);
}

Future<void> _pair(_Api api, String qr, String phone) async {
  final uri = Uri.tryParse(qr.trim());
  final s = uri?.queryParameters['s'], k = uri?.queryParameters['k'];
  if (uri == null ||
      uri.scheme != 'dentos' ||
      uri.host != 'pair' ||
      s == null ||
      k == null) {
    stderr.writeln('That is not a DentOS pairing code (dentos://pair?...).');
    exit(1);
  }

  // A brand-new key for this phone — the private half never leaves here.
  final rnd = _random();
  final gen = ECKeyGenerator()
    ..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), rnd));
  final pair = gen.generateKeyPair();
  final pub = pair.publicKey as ECPublicKey;
  final priv = pair.privateKey as ECPrivateKey;
  final spki = Uint8List.fromList([
    ..._spkiHeader,
    0x04,
    ..._bytes32(pub.Q!.x!.toBigInteger()!),
    ..._bytes32(pub.Q!.y!.toBigInteger()!),
  ]);

  stdout.writeln('→ Claiming the code with owner number $phone …');
  final c = await api.post({
    'action': 'claim',
    's': s,
    'k': k,
    'phone': phone,
    'pubkey': base64.encode(spki),
    'model': 'DentOS Simulator (${Platform.operatingSystem})',
    'platform': 'sim',
  });
  if (c['ok'] != true) {
    stdout.writeln(
      '✗ ${c['error']}${c['tries_left'] != null ? ' (${c['tries_left']} tries left)' : ''}',
    );
    exit(1);
  }
  final code = '${c['code']}';
  stdout.writeln('');
  stdout.writeln(
    '   CODE ON THE PHONE:  ${code.substring(0, 3)} ${code.substring(3)}',
  );
  stdout.writeln('');
  stdout.writeln(
    '   Check the computer shows the same code, then press Approve.',
  );
  stdout.writeln('   Waiting (up to 3 minutes) …');

  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 2));
    final ts = DateTime.now().millisecondsSinceEpoch;
    final f = await api.post({
      'action': 'finish',
      's': s,
      'ts': ts,
      'sig': _sign(priv, 'dentos-pair|finish|$s|$ts'),
    });
    if (f['ok'] == true && f['status'] == 'waiting') continue;
    if (f['ok'] == true && f['status'] == 'done') {
      File(_stateFile).writeAsStringSync(
        jsonEncode({
          'device_id': f['device_id'],
          'd': priv.d!.toRadixString(16),
          'spki': base64.encode(spki),
        }),
      );
      stdout.writeln(
        '✓ Connected to ${f['clinic_name']}. Device ${f['device_id']}.',
      );
      stdout.writeln(
        '  Key saved in $_stateFile. Try: dart run tool/phone_pair_sim.dart ping',
      );
      return;
    }
    stdout.writeln('✗ ${f['error']}');
    exit(1);
  }
  stdout.writeln('✗ Nobody approved it in time.');
  exit(1);
}

/// A request signed with the saved key:
/// "dentos-owner|<action>|<device_id>|<ts>|<nonce>|<sha256hex(p)>".
Future<Map<String, dynamic>> _signed(_Api api, String action, String p) async {
  final f = File(_stateFile);
  if (!f.existsSync()) {
    stderr.writeln(
      'Not paired yet. Run: dart run tool/phone_pair_sim.dart pair ...',
    );
    exit(1);
  }
  final st = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final priv = ECPrivateKey(BigInt.parse(st['d'] as String, radix: 16), _curve);
  final id = st['device_id'] as String;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rnd = Random.secure();
  final nonce = base64Url
      .encode(List.generate(18, (_) => rnd.nextInt(256)))
      .replaceAll('=', '');
  final hash = _hex(SHA256Digest().process(Uint8List.fromList(utf8.encode(p))));
  return api.post({
    'action': action,
    'device_id': id,
    'ts': ts,
    'nonce': nonce,
    'p': p,
    'sig': _sign(priv, 'dentos-owner|$action|$id|$ts|$nonce|$hash'),
  });
}

/// ECDSA P-256 / SHA-256 → raw r||s (64 bytes), base64.
String _sign(ECPrivateKey priv, String message) {
  final signer = ECDSASigner(SHA256Digest())
    ..init(
      true,
      ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(priv), _random()),
    );
  final sig =
      signer.generateSignature(Uint8List.fromList(utf8.encode(message)))
          as ECSignature;
  return base64.encode([..._bytes32(sig.r), ..._bytes32(sig.s)]);
}

Uint8List _bytes32(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

SecureRandom _random() {
  final r = Random.secure();
  return FortunaRandom()..seed(
    KeyParameter(Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)))),
  );
}

Map<String, String> _env() {
  final f = File('.env');
  if (!f.existsSync()) return {};
  final out = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    var v = t.substring(i + 1).trim();
    if (v.length >= 2 &&
        (v.startsWith('"') && v.endsWith('"') ||
            v.startsWith("'") && v.endsWith("'"))) {
      v = v.substring(1, v.length - 1);
    }
    out[t.substring(0, i).trim()] = v;
  }
  return out;
}

class _Api {
  _Api(this.url, this.anonKey);
  final String url;
  final String? anonKey;

  Future<Map<String, dynamic>> post(Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      final key = anonKey;
      if (key != null && key.isNotEmpty) {
        req.headers.set('apikey', key);
        req.headers.set('Authorization', 'Bearer $key');
      }
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      try {
        return Map<String, dynamic>.from(jsonDecode(text) as Map);
      } catch (_) {
        return {'ok': false, 'error': 'HTTP ${res.statusCode}: $text'};
      }
    } catch (e) {
      return {'ok': false, 'error': 'network: $e'};
    } finally {
      client.close();
    }
  }
}
