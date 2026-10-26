import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';

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
              // The shell's bar floats over the page, so the last card has to
              // be able to scroll clear of it.
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                ScrollShrinkNavBar.contentInset(context),
              ),
              child: Column(
                children: [
                  _HubCard(
                    icon: Icons.person_outline,
                    title: 'User Profile',
                    subtitle: 'View and edit your personal details',
                    onTap: () => context.push('/profile/detail'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _HubCard(
                    icon: Icons.sports_outlined,
                    title: 'Coach',
                    subtitle: "Read your athletes' training",
                    onTap: () => context.push('/profile/coach'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _HubCard(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    subtitle: 'Choose how the app looks',
                    onTap: () => context.push('/profile/appearance'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One hub row: a tinted glyph, the name and its one-line purpose, and the
/// chevron that says this opens a page.
class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accentBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextStyles.lg,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
        ],
      ),
    );
  }
}
