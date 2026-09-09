import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../../core/db/app_database.dart';

class XrayExportResult {
  XrayExportResult({
    required this.fileCount,
    required this.patientCount,
    this.error,
  });
  final int fileCount;
  final int patientCount;
  final String? error;
  bool get ok => error == null;
}

class XrayExport {
  /// Builds a ZIP of all X-rays, grouped into one folder per patient.
  /// Folder name: "PT-0000123 Fatima Aslam" (code + name, sanitised).
  /// Files inside are named "YYYY-MM-DD_<original>" and ordered newest→oldest.
  static Future<XrayExportResult> buildZip({
    required AppDatabase db,
    required String savePath,
    String? branchId,
  }) async {
    try {
      final xrays = await db.allXrays(
        branchId: branchId,
      ); // already newest-first
      if (xrays.isEmpty) {
        return XrayExportResult(
          fileCount: 0,
          patientCount: 0,
          error: 'No X-rays to export.',
        );
      }

      // resolve patient code + name per patientId (cache to avoid repeat queries)
      final folderFor = <int, String>{};
      Future<String> folderName(int patientId) async {
        if (folderFor.containsKey(patientId)) return folderFor[patientId]!;
        final pat = await (db.select(
          db.patients,
        )..where((t) => t.id.equals(patientId))).getSingleOrNull();
        final name = pat == null
            ? 'Unknown_$patientId'
            : '${pat.code} ${pat.fullName}';
        final safe = _sanitize(name);
        folderFor[patientId] = safe;
        return safe;
      }

      final encoder = ZipFileEncoder();
      encoder.create(savePath);

      var added = 0;
      for (final x in xrays) {
        final f = File(x.filePath);
        if (!await f.exists()) continue; // file missing on disk — skip
        final folder = await folderName(x.patientId);
        final date =
            '${x.takenAt.year}-'
            '${x.takenAt.month.toString().padLeft(2, '0')}-'
            '${x.takenAt.day.toString().padLeft(2, '0')}';
        final ext = p.extension(x.filePath);
        final base = _sanitize(p.basenameWithoutExtension(x.fileName));
        final entryName = '$folder/${date}_$base$ext';
        await encoder.addFile(f, entryName);
        added++;
      }

      await encoder.close();

      if (added == 0) {
        return XrayExportResult(
          fileCount: 0,
          patientCount: 0,
          error: 'No X-ray files found on disk.',
        );
      }
      return XrayExportResult(fileCount: added, patientCount: folderFor.length);
    } catch (e) {
      return XrayExportResult(fileCount: 0, patientCount: 0, error: '$e');
    }
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  static String sanitizePublic(String s) => _sanitize(s);
}
