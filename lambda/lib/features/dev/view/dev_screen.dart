import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';

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
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NavCard(
                    icon: Icons.palette_outlined,
                    label: 'Gallery',
                    subtitle: 'Colors, typography, spacing & components',
                    onTap: () => context.push('/dev/gallery'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _NavCard(
                    icon: Icons.science_outlined,
                    label: 'Experimental Features',
                    subtitle: 'Theme picker and in-progress features',
                    onTap: () => context.push('/dev/experimental'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Session Info',
                            style: TextStyle(
                                fontSize: AppTextStyles.md,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                        const SizedBox(height: AppSpacing.sm),
                        _InfoRow('User ID', session?.user.id ?? 'none'),
                        _InfoRow('Email', session?.user.email ?? 'none'),
                        _InfoRow(
                          'Expires',
                          session?.expiresAt != null
                              ? DateTime.fromMillisecondsSinceEpoch(
                                      session!.expiresAt! * 1000)
                                  .toLocal()
                                  .toString()
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
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: AppTextStyles.sm, color: AppColors.muted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
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
          Text('$label: ',
              style: TextStyle(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value,
                style:
                    TextStyle(fontSize: AppTextStyles.sm, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
