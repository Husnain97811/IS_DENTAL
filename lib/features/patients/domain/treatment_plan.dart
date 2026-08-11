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
    DateTime? completedAt, // ← NEW: stamped when marked done
  }) = _TreatmentStep;
}

@freezed
abstract class TreatmentPlan with _$TreatmentPlan {
  const factory TreatmentPlan({
    required int id,
    required String title,
    required List<TreatmentStep> steps,
  }) = _TreatmentPlan;

  const TreatmentPlan._();

  /// A plan is "active" while it still has a step that isn't done.
  bool get isActive => steps.any((s) => s.status != StepStatus.done);

  /// The next step to work on (first non-done), or null if complete.
  TreatmentStep? get nextStep {
    for (final s in steps) {
      if (s.status != StepStatus.done) return s;
    }
    return null;
  }
}
