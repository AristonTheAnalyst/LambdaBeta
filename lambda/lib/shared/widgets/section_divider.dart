import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';

/// `─── LABEL ───` section headline — the prep screen's PREVIOUS SESSION /
/// THIS SESSION divider, shared so any screen can mark a section the same
/// way. Larger and primary-toned, unlike the muted mono micro-labels, so the
/// section reads as a headline.
class SectionDivider extends StatelessWidget {
  const SectionDivider(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Container(height: 1, color: AppColors.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Text(
          text,
          style: AppFonts.mono(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.primary,
          ),
        ),
      ),
      Expanded(child: Container(height: 1, color: AppColors.border)),
    ],
  );
}
