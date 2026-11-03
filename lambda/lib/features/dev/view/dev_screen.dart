import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';

/// The debug build's toolbox (2026-10-31): reference pages and layout labs
/// only. The retired demos — the PR History/PR Lab pair, the review-flow
/// lab, the nav-bar demo, Experimental, Visual Pairings, Coach Icons, the
/// sample-data seeder and the exercise-note dump — are gone; each had
/// settled its question.
class DevScreen extends StatelessWidget {
  const DevScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Dev'),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NavCard(
                    icon: LucideIcons.palette,
                    label: 'Gallery',
                    subtitle: 'Colors, typography, spacing & components',
                    onTap: () => context.push('/dev/gallery'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _NavCard(
                    icon: LucideIcons.user,
                    label: 'Friend Screen',
                    subtitle: 'Static layout prototype — identity, numbers, tabs',
                    onTap: () => context.push('/dev/friend-screen'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _NavCard(
                    icon: LucideIcons.rectangleHorizontal,
                    label: 'Session Cards',
                    subtitle: 'The shipped card against three drawn from scratch',
                    onTap: () => context.push('/dev/session-cards'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Session Info',
                          style: TextStyle(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _InfoRow('User ID', session?.user.id ?? 'none'),
                        _InfoRow('Email', session?.user.email ?? 'none'),
                        _InfoRow(
                          'Expires',
                          session?.expiresAt != null
                              ? DateTime.fromMillisecondsSinceEpoch(
                                  session!.expiresAt! * 1000,
                                ).toLocal().toString()
                              : 'none',
                        ),
                      ],
                    ),
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

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppTextStyles.sm,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
