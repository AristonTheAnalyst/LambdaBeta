import 'package:flutter/material.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/page_header.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Statistics'),
          Expanded(
            child: Center(
              child: Text(
                'Coming soon.',
                style: TextStyle(color: AppColors.muted, fontSize: AppTextStyles.md),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
