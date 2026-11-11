// Checks one licence key against vendor_keypair.json and shows exactly what
// the app signs. Run from the project root:
//   dart run tool/check_key.dart key.txt
// key.txt = the licence key copied from the licence tool. Delete it after.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

void main(List<String> args) {
  final path = args.isEmpty ? 'key.txt' : args.first;
  final raw = File(path).readAsStringSync();
  final s = raw.indexOf('{'), e = raw.lastIndexOf('}');
  if (s < 0 || e <= s) {
    print('No { … } found in $path');
    exit(1);
  }
  final j = jsonDecode(raw.substring(s, e + 1)) as Map<String, dynamic>;

  final kp = jsonDecode(File('vendor_keypair.json').readAsStringSync());
  final n = BigInt.parse(kp['n']), ex = BigInt.parse(kp['e']);

  bool verify(String text) {
    try {
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(false, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(n, ex)));
      return signer.verifySignature(
        Uint8List.fromList(utf8.encode(text)),
        RSASignature(base64.decode(j['signature'] as String)),
      );
    } catch (err) {
      print('  (verify error: $err)');
      return false;
    }
  }

  print('Key n starts: ${n.toString().substring(0, 20)}');
  print('\nFields in the key:');
  j.forEach((k, v) {
    final shown = k == 'signature' ? '${(v as String).length} chars' : v;
    print('  $k = $shown   (${v.runtimeType})');
  });

  // 1 · the text exactly as the key carries it (what the tool signed)
  final asIs = Map<String, dynamic>.of(j)
    ..remove('signature')
    ..remove('maxDevices');
  final toolText = jsonEncode(asIs);

  // 2 · the text the app builds (License.fromJson → canonicalPayload)
  final feats = [
    for (final f in (j['features'] as List?) ?? const []) f.toString(),
  ]..sort();
  final appText = jsonEncode({
    'clinicId': j['clinicId'],
    'clinicName': j['clinicName'],
    'tier': j['tier'],
    'cloudPackage': j['cloudPackage'],
    'maxBranches': j['maxBranches'],
    'maxUsers': j['maxUsers'],
    'issuedAt': DateTime.parse(j['issuedAt']).toUtc().toIso8601String(),
    'expiresAt': DateTime.parse(j['expiresAt']).toUtc().toIso8601String(),
    'machineFingerprint': j['machineFingerprint'],
    if (feats.isNotEmpty) 'features': feats,
  });

  print('\nA · signature matches the key as written:   ${verify(toolText)}');
  print('B · signature matches what the app builds:   ${verify(appText)}');

  if (toolText != appText) {
    var i = 0;
    while (i < toolText.length &&
        i < appText.length &&
        toolText.codeUnitAt(i) == appText.codeUnitAt(i)) {
      i++;
    }
    final from = i < 40 ? 0 : i - 40;
    print('\nThe two texts differ at character $i:');
    print(
      '  key: …${toolText.substring(from, (i + 60).clamp(0, toolText.length))}',
    );
    print(
      '  app: …${appText.substring(from, (i + 60).clamp(0, appText.length))}',
    );
  } else {
    print('\nThe key text and the app text are identical.');
  }
}
