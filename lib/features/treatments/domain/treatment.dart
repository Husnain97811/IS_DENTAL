import 'package:freezed_annotation/freezed_annotation.dart';
part 'treatment.freezed.dart';

@freezed
abstract class Treatment with _$Treatment {
  const factory Treatment({
    required int id,
    required String uuid,
    required String name,
    required String category,
    @Default(0) int price,
    @Default('') String duration,
  }) = _Treatment;
}
