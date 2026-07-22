import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';

class ProfileHubScreen extends StatelessWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Profile'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: AppCard(
                onTap: () => context.push('/profile/detail'),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accentBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.person_outline,
                          color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('User Profile',
                              style: TextStyle(
                                  fontSize: AppTextStyles.lg,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                          const SizedBox(height: 2),
                          Text('View and edit your personal details',
                              style: TextStyle(
                                  fontSize: AppTextStyles.sm,
                                  color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
