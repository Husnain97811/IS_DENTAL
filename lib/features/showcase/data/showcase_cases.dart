import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/views.dart';
import '../../patients/data/photo_compare_image.dart';

/// One before & after result the patient agreed to share.
///
/// Built from the Before & After cases on patient records: a case appears
/// here only when consent is ticked AND it has both a Before and an After
/// photo. No patient name is ever carried into the Showcase.
class ShowcaseCase {
  ShowcaseCase._(this.id, this.photos, this.before, this.after);

  final String id; // the case (pairGroup)
  final List<XrayRow> photos;
  final XrayRow before; // earliest Before photo
  final XrayRow after; // latest After photo

  /// null when the case can't be shown (no Before or no After yet).
  static ShowcaseCase? from(String id, List<XrayRow> photos) {
    XrayRow? b, a;
    for (final p in photos) {
      if (p.kind == 'before' && (b == null || p.takenAt.isBefore(b.takenAt)))
        b = p;
      if (p.kind == 'after' && (a == null || p.takenAt.isAfter(a.takenAt)))
        a = p;
    }
    return b == null || a == null ? null : ShowcaseCase._(id, photos, b, a);
  }

  /// The patient the photos belong to — used only for staff search,
  /// never displayed in the Showcase.
  String get patientUuid => before.patientUuid;

  String get treatment => _first((p) => p.treatment);
  String get tooth => _first((p) => p.tooth);
  String get title => treatment.isEmpty ? 'Smile transformation' : treatment;
  bool get featured => photos.any((p) => p.featured);
  bool get isLocal => before.isLocal && after.isLocal;
  bool get isCropped => before.crop != null || after.crop != null;
  NormRect? get beforeCrop => parseCrop(before.crop);
  NormRect? get afterCrop => parseCrop(after.crop);

  /// Who ticked consent and when (empty for cases from before v32).
  String get consentBy => _first((p) => p.consentBy);
  DateTime? get consentAt {
    for (final p in photos) {
      if (p.consentAt != null) return p.consentAt;
    }
    return null;
  }

  int get days => after.takenAt.difference(before.takenAt).inDays.abs();

  /// "6 months", "3 weeks", "Same visit"
  String get durationShort {
    final d = days;
    if (d == 0) return 'Same visit';
    if (d < 14) return '$d day${d == 1 ? '' : 's'}';
    if (d < 60) return '${(d / 7).round()} weeks';
    final m = (d / 30.44).round();
    return '$m month${m == 1 ? '' : 's'}';
  }

  /// The line under the headline on a post.
  String get durationLine =>
      days == 0 ? 'Done in a single visit' : 'Completed in $durationShort';

  /// True when every word of [query] appears in the treatment, tooth,
  /// duration or the patient's name ("ali", "cleaning", "tooth 11",
  /// "ali veneers").
  bool matches(String query, {String patientName = ''}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final hay = [
      title,
      treatment,
      if (tooth.isNotEmpty) 'tooth $tooth #$tooth',
      durationShort,
      patientName,
    ].join(' ').toLowerCase();
    return words.every(hay.contains);
  }

  String _first(String Function(XrayRow) f) {
    for (final p in photos) {
      final v = f(p);
      if (v.isNotEmpty) return v;
    }
    return '';
  }
}

/// All showcase cases for the branch in view: starred first, newest first.
final showcaseCasesProvider = StreamProvider.autoDispose<List<ShowcaseCase>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  final branch = ref.watch(activeBranchProvider);
  return db.watchShowcasePhotos(branchId: branch).map((rows) {
    final groups = <String, List<XrayRow>>{};
    for (final r in rows) {
      (groups[r.pairGroup ?? r.uuid] ??= <XrayRow>[]).add(r);
    }
    final out = <ShowcaseCase>[];
    for (final e in groups.entries) {
      final c = ShowcaseCase.from(e.key, e.value);
      if (c != null) out.add(c);
    }
    out.sort((a, b) {
      if (a.featured != b.featured) return a.featured ? -1 : 1;
      return b.after.takenAt.compareTo(a.after.takenAt);
    });
    return out;
  });
});

/// What the top bar's search box holds while the Showcase is open. The
/// grid narrows to matching cases as you type.
class ShowcaseSearch extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final showcaseSearchProvider = NotifierProvider<ShowcaseSearch, String>(
  ShowcaseSearch.new,
);

/// Just enough of a patient to search showcase cases by name.
class ShowcasePatient {
  const ShowcasePatient(this.id, this.name, this.code);
  final int id;
  final String name, code;
}

/// Patient uuid → patient, so cases can be found by the patient's name.
final showcasePatientsProvider =
    StreamProvider.autoDispose<Map<String, ShowcasePatient>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.patients,
      )..where((t) => t.isDeleted.equals(false))).watch().map(
        (rows) => {
          for (final r in rows)
            r.uuid: ShowcasePatient(r.id, r.fullName, r.code),
        },
      );
    });
