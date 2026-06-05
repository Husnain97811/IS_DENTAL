import 'package:flutter/material.dart';
import '../../../core/theme/dent_colors.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Inventory', style: TextStyle(color: context.dent.text3, fontSize: 22)));
}
