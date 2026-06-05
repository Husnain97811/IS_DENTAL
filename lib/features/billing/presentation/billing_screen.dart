import 'package:flutter/material.dart';
import '../../../core/theme/dent_colors.dart';

class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Billing', style: TextStyle(color: context.dent.text3, fontSize: 22)));
}
