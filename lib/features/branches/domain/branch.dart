import 'package:freezed_annotation/freezed_annotation.dart';
part 'branch.freezed.dart';

@freezed
abstract class Branch with _$Branch {
  const factory Branch({
    required int id,
    required String uuid,
    required String name,
    @Default('') String location,
    @Default(false) bool isPrimary,
  }) = _Branch;
}
