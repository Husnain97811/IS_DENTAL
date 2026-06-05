import 'package:flutter/material.dart';
import '../../../core/theme/dent_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Settings', style: TextStyle(color: context.dent.text3, fontSize: 22)));
}
