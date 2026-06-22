import 'package:freezed_annotation/freezed_annotation.dart';
part 'tooth_record.freezed.dart';

enum ToothState {
  healthy,
  caries,
  treated, // filled / restored
  crown,
  rootCanal,
  bridge,
  implant,
  missing,
}

@freezed
abstract class ToothRecord with _$ToothRecord {
  const factory ToothRecord({
    required int fdi,
    required ToothState state,
    String? note,
  }) = _ToothRecord;
}
