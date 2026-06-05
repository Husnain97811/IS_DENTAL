import 'package:flutter/material.dart';
import '../../../core/theme/dent_colors.dart';

class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Patients', style: TextStyle(color: context.dent.text3, fontSize: 22)));
}
