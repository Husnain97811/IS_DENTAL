import 'package:freezed_annotation/freezed_annotation.dart';
part 'treatment_plan.freezed.dart';

enum StepStatus { done, current, todo }

@freezed
abstract class TreatmentStep with _$TreatmentStep {
  const factory TreatmentStep({
    required int id,
    required int order,
    required String label,
    @Default('') String detail,
    required StepStatus status,
  }) = _TreatmentStep;
}

@freezed
abstract class TreatmentPlan with _$TreatmentPlan {
  const factory TreatmentPlan({
    required int id,
    required String title,
    required List<TreatmentStep> steps,
  }) = _TreatmentPlan;
}
