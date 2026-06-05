import 'package:flutter/material.dart';
import '../../../core/theme/dent_colors.dart';

class TreatmentsScreen extends StatelessWidget {
  const TreatmentsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Treatments', style: TextStyle(color: context.dent.text3, fontSize: 22)));
}
