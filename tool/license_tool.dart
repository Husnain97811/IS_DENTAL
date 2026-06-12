import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// Edit the license you want to issue (defaults are fine for testing):
final licenseFields = <String, dynamic>{
  'clinicId': 'CL-0001',
  'clinicName': 'Smile Dental Care',
  'tier': 'premium',
  'cloudPackage': 'cloud',
  'maxBranches': 3,
  'maxUsers': 8,
  'issuedAt': DateTime.now(),
  'expiresAt': DateTime.now().add(const Duration(days: 365)),
  'machineFingerprint': 'ANY',
};

void main() {
  final pair = _loadOrCreateKeys();
  final pub = pair.publicKey as RSAPublicKey;
  final priv = pair.privateKey as RSAPrivateKey;

  print('\n>>> PASTE THIS MODULUS into license_verifier.dart (_modulus):\n');
  print(pub.modulus);
  print('');

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
