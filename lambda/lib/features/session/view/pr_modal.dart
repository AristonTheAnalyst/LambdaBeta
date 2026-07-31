import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/workout_format.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../model/pr_engine.dart';

void showPrModal(BuildContext context, {required List<PrRecord> prs}) {
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PRs Achieved 🏆',
                          style: AppFonts.ui(
                              fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      if (prs.isEmpty)
                        const SizedBox(height: 8),
                      if (prs.isEmpty)
                        Text('No PRs this session',
                            style: AppFonts.ui(fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
                ),
                GlassButton(
                  label: 'All PRs',
                  compact: true,
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    context.push('/statistics');
                  },
                ),
              ],
            ),
            if (prs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              ...prs.map((pr) => _PrRow(pr: pr)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.pr});
  final PrRecord pr;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                Text(
                  pr.exerciseName != null ? toProperCase(pr.exerciseName!) : pr.exerciseId,
                  style: AppFonts.ui(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
                Text(
                  '${_fmt(pr.weight)}kg × ${_fmt(pr.reps)}',
                  style: AppFonts.mono(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(pr.typeLabel,
                style: AppFonts.ui(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentText)),
          ),
        ],
      ),
    );
  }

  static String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}
