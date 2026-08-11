import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../domain/treatment_plan.dart';
import '../patients_controller.dart';

Future<void> showPlanEditor(
  BuildContext context, {
  required int patientId,
  TreatmentPlan? existing, // null = create new
}) => showDialog(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: _PlanEditor(patientId: patientId, existing: existing),
  ),
);

class _EditStep {
  _EditStep({
    this.label = '',
    this.detail = '',
    this.status = StepStatus.todo,
    this.completedAt,
  });
  final TextEditingController labelC = TextEditingController();
  final TextEditingController detailC = TextEditingController();
  StepStatus status;
  DateTime? completedAt;
  String label;
  String detail;
  void dispose() {
    labelC.dispose();
    detailC.dispose();
  }
}

class _PlanEditor extends ConsumerStatefulWidget {
  const _PlanEditor({required this.patientId, this.existing});
  final int patientId;
  final TreatmentPlan? existing;
  @override
  ConsumerState<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends ConsumerState<_PlanEditor> {
  late final TextEditingController _title;
  final List<_EditStep> _steps = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    if (widget.existing != null) {
      for (final s in widget.existing!.steps) {
        final es = _EditStep(status: s.status, completedAt: s.completedAt);
        es.labelC.text = s.label;
        es.detailC.text = s.detail;
        _steps.add(es);
      }
    } else {
      _steps.add(_EditStep());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final s in _steps) s.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final steps = <TreatmentStep>[];
    for (var i = 0; i < _steps.length; i++) {
      final s = _steps[i];
      if (s.labelC.text.trim().isEmpty) continue;
      steps.add(
        TreatmentStep(
          id: 0,
          order: i,
          label: s.labelC.text.trim(),
          detail: s.detailC.text.trim(),
          status: s.status,
          completedAt: s.status == StepStatus.done
              ? (s.completedAt ?? DateTime.now())
              : null,
        ),
      );
    }
    if (steps.isEmpty) return;

    setState(() => _busy = true);
    final repo = ref.read(patientRepositoryProvider);
    if (widget.existing == null) {
      await repo.createPlan(widget.patientId, title, steps);
    } else {
      await repo.updatePlan(widget.existing!.id, title, steps);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 54.w, maxHeight: 86.h),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'New Treatment Plan'
                          : 'Edit Treatment Plan',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 12.sp,
                      color: d.text3,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(d, 'Plan Title'),
                    _box(
                      d,
                      TextField(
                        controller: _title,
                        style: TextStyle(fontSize: 9.sp, color: d.text1),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'e.g. Full Mouth Rehabilitation',
                          hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _lbl(d, 'Steps'),
                    for (var i = 0; i < _steps.length; i++) _stepRow(d, i),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 15.w,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _steps.add(_EditStep())),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: d.ice,
                            side: BorderSide(color: d.text1),
                            minimumSize: Size.fromHeight(5.h),
                          ),
                          label: const Text('Add step'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  widget.existing == null ? 'Create Plan' : 'Save Changes',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepRow(DentColors d, int i) {
    final s = _steps[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: d.ice,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: s.labelC,
                  style: TextStyle(fontSize: 10.5.sp, color: d.text2),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Step label (e.g. Root Canal · #36)',
                    hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
                  ),
                ),
              ),
              if (_steps.length > 1)
                IconButton(
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 18,
                    color: d.text4,
                  ),
                  onPressed: () => setState(() {
                    _steps[i].dispose();
                    _steps.removeAt(i);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: s.detailC,
            style: TextStyle(fontSize: 8.5.sp, color: d.text2),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Detail (optional)',
              hintStyle: TextStyle(color: d.text4, fontSize: 8.5.sp),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: DropdownButton<StepStatus>(
              value: s.status,
              isDense: true,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: StepStatus.todo, child: Text('To do')),
                DropdownMenuItem(
                  value: StepStatus.current,
                  child: Text('Current'),
                ),
                DropdownMenuItem(value: StepStatus.done, child: Text('Done')),
              ],
              onChanged: (v) => setState(() => s.status = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lbl(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 12, 0, 7),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        color: d.text1,
        fontSize: 9.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  Widget _box(DentColors d, Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: d.line),
    ),
    child: child,
  );
}
