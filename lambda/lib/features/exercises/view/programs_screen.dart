import 'package:flutter/material.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/page_header.dart';

class ProgramsScreen extends StatelessWidget {
  const ProgramsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Programs',
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: AppColors.accent),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('Coming soon.',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppTextStyles.md)),
            ),
          ),
        ],
      ),
    );
  }
}
