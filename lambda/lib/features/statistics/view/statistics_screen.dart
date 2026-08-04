import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/press_squash.dart';

/// Landing hub for the Statistics tab: two cards leading into the PR
/// catalog and the Insights analysis screen.
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
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: const [
                _HubCard(
                  icon: Icons.flag_outlined,
                  title: 'Personal Records',
                  subtitle: 'Exercise catalog with per-exercise PR breakdowns',
                  route: '/statistics/prs',
                ),
                SizedBox(height: AppSpacing.md),
                _HubCard(
                  icon: Icons.insights_outlined,
                  title: 'Insights',
                  subtitle: 'PR frequency, volume, weight & rep analysis',
                  route: '/statistics/insights',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: PressSquash(
        onTap: () => context.push(route),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.xs, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
