import 'package:flutter/material.dart';
import '../../../core/theme/dent_colors.dart';

class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Appointments', style: TextStyle(color: context.dent.text3, fontSize: 22)));
}
