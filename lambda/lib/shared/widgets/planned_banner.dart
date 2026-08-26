import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';

/// The planned-source banner — planned-blue ghost container with the event
/// icon and the planned session's name. Shared between the prep page's LAST
/// SESSION card and the past-session viewer's Summary tab.
class PlannedBanner extends StatelessWidget {
  const PlannedBanner({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.plannedBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.planned, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.event_outlined, size: 16, color: AppColors.planned),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                letterSpacing: 0.6,
                color: AppColors.planned,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
