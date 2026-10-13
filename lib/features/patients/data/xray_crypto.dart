import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// On-disk format of an encrypted X-ray (.dxr):
///
///   "DXR1" (4) | version (1) | keyId (8) | nonce (12) | ciphertext + GCM tag
///
/// AES-256-GCM. The header AND the X-ray's uuid are authenticated, so the
/// header can't be edited and a file copied onto another record won't open.
/// The keyId is a fingerprint of the key, never the key itself — it only
/// tells DentOS which key in the keyring opens this file.
class XrayCrypto {
  static const _magic = [0x44, 0x58, 0x52, 0x31]; // "DXR1"
  static const _version = 1;
  static const _keyIdLen = 8;
  static const _nonceLen = 12;
  static const headerLen = 4 + 1 + _keyIdLen + _nonceLen;

  static Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static Uint8List newKey() => randomBytes(32);

  static String keyIdHex(Uint8List key) =>
      _hex(SHA256Digest().process(key).sublist(0, _keyIdLen));

  static String sha256Hex(Uint8List data) => _hex(SHA256Digest().process(data));

  static bool isDxr(Uint8List data) =>
      data.length > headerLen &&
      data[0] == _magic[0] &&
      data[1] == _magic[1] &&
      data[2] == _magic[2] &&
      data[3] == _magic[3];

  /// Which key opened this file — read without decrypting anything.
  static String keyIdOf(Uint8List data) =>
      _hex(Uint8List.sublistView(data, 5, 5 + _keyIdLen));

  static Uint8List encrypt(Uint8List plain, Uint8List key, String uuid) {
    final nonce = randomBytes(_nonceLen);
    final header =
        (BytesBuilder(copy: false)
              ..add(_magic)
              ..addByte(_version)
              ..add(SHA256Digest().process(key).sublist(0, _keyIdLen))
              ..add(nonce))
            .takeBytes();
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, nonce, _aad(header, uuid)),
      );
    final body = gcm.process(plain);
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(body))
        .takeBytes();
  }

  /// Throws if the key is wrong, the file was altered, or it belongs to a
  /// different X-ray record.
  static Uint8List decrypt(Uint8List data, Uint8List key, String uuid) {
    if (!isDxr(data)) {
      throw const FormatException('Not a DentOS X-ray file.');
    }
    final header = Uint8List.sublistView(data, 0, headerLen);
    final nonce = Uint8List.sublistView(data, 5 + _keyIdLen, headerLen);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), 128, nonce, _aad(header, uuid)),
      );
    return gcm.process(Uint8List.sublistView(data, headerLen));
  }

  // Off the UI thread, so a large panoramic doesn't freeze a normal PC.
  static Future<Uint8List> encryptAsync(
    Uint8List plain,
    Uint8List key,
    String uuid,
  ) => Isolate.run(() => encrypt(plain, key, uuid));

  static Future<Uint8List> decryptAsync(
    Uint8List data,
    Uint8List key,
    String uuid,
  ) => Isolate.run(() => decrypt(data, key, uuid));

  static Future<String> sha256Async(Uint8List data) =>
      Isolate.run(() => sha256Hex(data));

  static Uint8List _aad(Uint8List header, String uuid) =>
      (BytesBuilder(copy: false)
            ..add(header)
            ..add(utf8.encode(uuid)))
          .takeBytes();

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
