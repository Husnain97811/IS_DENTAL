// lib/features/patients/presentation/tooth_chart_screen.dart
import 'package:flutter/material.dart';
import 'tooth_model_3d.dart'; // adjust import path

class ToothChartScreen extends StatelessWidget {
  const ToothChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1422), // matches 3D background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white70,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '3D Tooth Chart',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: const ToothModel3D(), // the whole screen is the 3D model
    );
  }
}
