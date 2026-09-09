import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class XrayStorage {
  /// Root folder: <Documents>/DentOS/xrays
  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'DentOS', 'xrays'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Per-patient folder.
  static Future<Directory> patientDir(String patientUuid) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, patientUuid));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies a picked file into the patient's folder. Returns the new path.
  static Future<String> store({
    required String patientUuid,
    required String sourcePath,
    required String newBaseName, // e.g. uuid
  }) async {
    final dir = await patientDir(patientUuid);
    final ext = p.extension(sourcePath).toLowerCase();
    final dest = p.join(dir.path, '$newBaseName$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static bool isPdf(String path) => p.extension(path).toLowerCase() == '.pdf';
}
