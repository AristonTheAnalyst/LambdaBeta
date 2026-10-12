import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';

/// What the user answered when a reviewed run had reached its length.
enum RunFinishedAnswer {
  /// Keep the plan as it now stands and carry on. Nothing is written: the
  /// completed review is itself the record of the answer, and the length
  /// stays where it is — "how long" was not the question [changeLength]
  /// would have answered.
  continueRun,

  /// Reopens the run config to set a new length.
  changeLength,

  /// Ends the attempt, recording what it got to.
  endRun,
}

/// The question a run asks once its review is finished: what now?
///
/// Deliberately its own moment rather than part of the review bar: the review
/// is about the PLAN, and this is about the ATTEMPT — whether the run that
/// asked for the review should carry on, change shape, or stop. Asking it
/// here, with the review behind the user and the run still theirs to decide,
/// is what keeps "reached its length" a checkpoint instead of an ending.
///
/// Returns null when dismissed, which is read as "no answer yet": the run
/// keeps running exactly as it was, and — like [RunFinishedAnswer.continueRun]
/// — nothing is written.
Future<RunFinishedAnswer?> showRunFinishedSheet(
  BuildContext context, {
  required String lengthLabel,
}) => showLambdaModal<RunFinishedAnswer>(
  context,
  fitContent: true,
  child: SafeArea(child: _RunFinishedSheet(lengthLabel: lengthLabel)),
);

class _RunFinishedSheet extends StatelessWidget {
  const _RunFinishedSheet({required this.lengthLabel});

  /// The run's length, phrased by the caller — it owns the block/program
  /// distinction the number alone cannot carry.
  final String lengthLabel;

  void _answer(BuildContext context, RunFinishedAnswer answer) =>
      Navigator.of(context, rootNavigator: true).pop(answer);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The run has reached its length',
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The plan is reviewed. Carry on with it, change how long this '
            'attempt runs, or end it here.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'PLANNED · $lengthLabel',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              letterSpacing: 0.8,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassButton(
            label: 'Continue',
            solid: true,
            onPressed: () => _answer(context, RunFinishedAnswer.continueRun),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Change length',
                  onPressed: () =>
                      _answer(context, RunFinishedAnswer.changeLength),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GlassButton(
                  label: 'End run',
                  color: AppColors.danger,
                  onPressed: () => _answer(context, RunFinishedAnswer.endRun),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
