import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Text(
          'λ',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
