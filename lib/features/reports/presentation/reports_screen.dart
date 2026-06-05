import 'package:flutter/material.dart';
import '../../../core/theme/dent_colors.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Reports', style: TextStyle(color: context.dent.text3, fontSize: 22)));
}
