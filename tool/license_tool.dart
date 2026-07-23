import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

final _clinicName = 'Fast Dental Clinic';
final _clinicCity = 'Islamabad';

// Edit the license you want to issue (defaults are fine for testing):
final licenseFields = <String, dynamic>{
  'clinicId': generateClinicId(_clinicName, _clinicCity),
  'clinicName': _clinicName,
  'tier': 'premium',
  'cloudPackage': 'cloud',
  'maxBranches': 3,
  'maxUsers': 8,
  'issuedAt': DateTime.now(),
  // 'expiresAt': DateTime.now().add(const Duration(days: -1)),
  'expiresAt': DateTime.now().add(const Duration(days: 365)),
  'machineFingerprint': 'ANY',
};

/// FAST-ISL-482913  →  <first word of name>-<city code>-<6 random digits>
/// Run ONCE per clinic at first mint. Reuse the SAME id verbatim for renewals.
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
  final manual_digits = 987463;
  return '$slug-$code-$manual_digits';
}

void main() {
  licenseFields['clinicId'] = generateClinicId(_clinicName, _clinicCity);
  final pair = _loadOrCreateKeys();
  final pub = pair.publicKey as RSAPublicKey;
  final priv = pair.privateKey as RSAPrivateKey;

  final payload = _canonical(licenseFields);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
  final sig = signer.generateSignature(
    Uint8List.fromList(utf8.encode(payload)),
  );
  final license = {
    ...jsonDecode(payload),
    'signature': base64.encode(sig.bytes),
  };

  File(
    'license.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(license));
  print('Wrote license.json — paste its contents into the activation screen.');
}

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
  final f = File('vendor_keypair.json');
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
  print('Generated vendor_keypair.json — keep it private.');
  return pair;
}
