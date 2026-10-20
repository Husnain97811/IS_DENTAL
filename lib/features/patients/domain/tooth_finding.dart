import 'tooth_record.dart';

/// What was observed or done on a tooth.
enum ToothKind {
  caries,
  filling,
  sealant,
  crown,
  rct,
  extraction,
  implant,
  bridge,
  missing,
}

/// found    — a diagnosis (caries)
/// existing — present when the patient arrived
/// planned  — to be done
/// done     — done in this clinic
enum FindingStatus { found, existing, planned, done }

extension ToothKindX on ToothKind {
  String get label => switch (this) {
    ToothKind.caries => 'Caries',
    ToothKind.filling => 'Filling',
    ToothKind.sealant => 'Sealant',
    ToothKind.crown => 'Crown',
    ToothKind.rct => 'Root canal',
    ToothKind.extraction => 'Extraction',
    ToothKind.implant => 'Implant',
    ToothKind.bridge => 'Bridge unit',
    ToothKind.missing => 'Missing',
  };

  /// Charted on individual surfaces rather than the whole tooth.
  bool get bySurface =>
      this == ToothKind.caries ||
      this == ToothKind.filling ||
      this == ToothKind.sealant;

  /// Caries is always a finding and Missing is always a fact on arrival —
  /// neither can be "planned" or "done".
  FindingStatus? get forcedStatus => switch (this) {
    ToothKind.caries => FindingStatus.found,
    ToothKind.missing => FindingStatus.existing,
    _ => null,
  };
}

extension FindingStatusX on FindingStatus {
  String get label => switch (this) {
    FindingStatus.found => 'Found',
    FindingStatus.existing => 'Existing',
    FindingStatus.planned => 'Planned',
    FindingStatus.done => 'Done',
  };

  /// Which status wins when several findings cover the same surface.
  int get rank => switch (this) {
    FindingStatus.planned => 4,
    FindingStatus.found => 3,
    FindingStatus.done => 2,
    FindingStatus.existing => 1,
  };
}

/// Clinical writing order: M O/I D B L — "MOD", "MO", "DOB".
const kSurfaceOrder = ['M', 'O', 'I', 'D', 'B', 'L'];

String surfaceNotation(Iterable<String> s) =>
    kSurfaceOrder.where(s.contains).join();

class ToothFinding {
  const ToothFinding({
    required this.id,
    required this.uuid,
    required this.fdi,
    required this.kind,
    required this.status,
    required this.surfaces,
    required this.createdBy,
    required this.createdAt,
    this.note,
    this.completedBy,
    this.completedAt,
    this.isDeleted = false,
    this.deletedBy,
    this.deletedAt,
  });

  final int id;
  final String uuid;
  final int fdi;
  final ToothKind kind;
  final FindingStatus status;
  final Set<String> surfaces;
  final String? note;
  final String createdBy;
  final DateTime createdAt;
  final String? completedBy;
  final DateTime? completedAt;
  final bool isDeleted;
  final String? deletedBy;
  final DateTime? deletedAt;

  String get notation => surfaceNotation(surfaces);

  /// "Filling MO", "Crown".
  String get label => notation.isEmpty ? kind.label : '${kind.label} $notation';

  /// A surface-type finding imported from the old chart, where surfaces
  /// were never recorded. Drawn across the whole crown.
  bool get surfacesUnknown => kind.bySurface && surfaces.isEmpty;

  bool get isImported => uuid.startsWith('mig-');
}

// ── tooth geometry ─────────────────────────────────────────────────────────

int quadrantOf(int fdi) => fdi ~/ 10;
bool isPrimaryTooth(int fdi) => quadrantOf(fdi) >= 5;
bool isUpperTooth(int fdi) => const [1, 2, 5, 6].contains(quadrantOf(fdi));
bool isPosteriorTooth(int fdi) => fdi % 10 >= 4;
bool isMultiRoot(int fdi) => fdi % 10 >= (isPrimaryTooth(fdi) ? 4 : 6);

const _quadName = {
  1: 'Upper right',
  2: 'Upper left',
  3: 'Lower left',
  4: 'Lower right',
  5: 'Upper right',
  6: 'Upper left',
  7: 'Lower left',
  8: 'Lower right',
};
const _adultNames = [
  '',
  'central incisor',
  'lateral incisor',
  'canine',
  'first premolar',
  'second premolar',
  'first molar',
  'second molar',
  'third molar',
];
const _primaryNames = [
  '',
  'central incisor',
  'lateral incisor',
  'canine',
  'first molar',
  'second molar',
];

String toothName(int fdi) {
  final names = isPrimaryTooth(fdi) ? _primaryNames : _adultNames;
  final i = fdi % 10;
  final n = i < names.length ? names[i] : '';
  return '${_quadName[quadrantOf(fdi)] ?? ''} $n'
      '${isPrimaryTooth(fdi) ? ' (primary)' : ''}';
}

/// A tooth that is no longer there — nothing can be charted on its surfaces.
bool isToothGone(Iterable<ToothFinding> live) => live.any(
  (f) =>
      f.kind == ToothKind.missing ||
      (f.kind == ToothKind.extraction && f.status != FindingStatus.planned),
);

/// The single state the OLD chart stored for this tooth.
///
/// The new chart keeps writing it, so anything still reading
/// `tooth_records` — the patient mobile app, exports, older computers that
/// haven't updated yet — keeps showing a sensible picture. Planned work is
/// not reality yet, so it doesn't count.
ToothState legacyStateFor(Iterable<ToothFinding> live) {
  bool has(ToothKind k) =>
      live.any((f) => f.kind == k && f.status != FindingStatus.planned);
  if (has(ToothKind.missing) || has(ToothKind.extraction)) {
    return ToothState.missing;
  }
  if (has(ToothKind.implant)) return ToothState.implant;
  if (has(ToothKind.bridge)) return ToothState.bridge;
  if (has(ToothKind.crown)) return ToothState.crown;
  if (has(ToothKind.rct)) return ToothState.rootCanal;
  if (has(ToothKind.caries)) return ToothState.caries;
  if (has(ToothKind.filling) || has(ToothKind.sealant)) {
    return ToothState.treated;
  }
  return ToothState.healthy;
}
