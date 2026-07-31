import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/session_viewmodel.dart';

void showPrModal(BuildContext context, {required SessionViewModel vm}) {
  showLambdaModal(
    context,
    fitContent: true,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('THIS SESSION',
                style: AppFonts.mono(fontSize: 9, letterSpacing: 1.2, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text('PRs Achieved 🏆',
                style: AppFonts.ui(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(height: AppSpacing.lg),
            ...vm.prsThisSession.map((pr) => Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pr.exercise,
                                style: AppFonts.ui(
                                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            Text('${pr.weight ?? '—'}kg × ${pr.reps ?? '—'} reps',
                                style: AppFonts.mono(fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('PR',
                            style: AppFonts.ui(
                                fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentText)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    ),
  );
}
