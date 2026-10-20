import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/views.dart';

/// How many patient files are open on the Patients tab (one, or more when
/// a file is opened from another file). The side drawer previews a patient
/// from the list, so it hides while a full file is open.
class PatientDetailDepth extends Notifier<int> {
  @override
  int build() => 0;
  void opened() => state = state + 1;
  void closed() => state = state > 0 ? state - 1 : 0;
}

final patientDetailDepthProvider = NotifierProvider<PatientDetailDepth, int>(
  PatientDetailDepth.new,
);

/// The `/patients/:id` page: the patient's file, and it tells the shell
/// a file is open while it's on screen.
class PatientDetailRoute extends ConsumerStatefulWidget {
  const PatientDetailRoute({super.key, required this.patientId});
  final int patientId;
  @override
  ConsumerState<PatientDetailRoute> createState() => _PatientDetailRouteState();
}

class _PatientDetailRouteState extends ConsumerState<PatientDetailRoute> {
  late final PatientDetailDepth _depth;

  @override
  void initState() {
    super.initState();
    _depth = ref.read(patientDetailDepthProvider.notifier);
    // once this build is done — providers can't change mid-build
    scheduleMicrotask(_depth.opened);
  }

  @override
  void dispose() {
    scheduleMicrotask(_depth.closed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PatientDetailScreen(patientId: widget.patientId);
}
