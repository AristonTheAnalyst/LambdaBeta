import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/session_format.dart';
import '../../features/session/model/pr_engine.dart';
import 'container_styles.dart';

/// One PR event, rendered the same way everywhere it appears.
///
/// Extracted from the session's PR modal so the review sheet's achievement
/// panel shows a PR identically — the same lift, the same before-facts, the
/// same accent. A second hand-rolled row is how two surfaces end up disagreeing
/// about what a PR looked like.
class PrEventRow extends StatelessWidget {
  const PrEventRow(
    this.event, {
    super.key,
    this.showExercise = false,
  });

  final PrEvent event;

  /// Adds the exercise name. The session modal omits it — the sheet is scoped
  /// to one session and its filter names the exercise — while the review sheet
  /// shows a whole run's worth and needs the name on every row.
  final bool showExercise;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: lambdaBox(ContainerTone.accent, radius: AppRadius.md),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showExercise)
                  Text(
                    eventName(event.exerciseName, event.exerciseId),
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                if (event.variationName != null)
                  Text(
                    toProperCase(event.variationName!),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      letterSpacing: 0.6,
                      color: AppColors.accent,
                    ),
                  ),
                Text(
                  '${formatPrNumber(event.weight)}kg × '
                  '${formatPrNumber(event.reps)}',
                  style: AppFonts.mono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                Text(
                  prBeforeFacts(event),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A dim name can be null — an id the local mirror hasn't seen, or a set logged
/// before the exercise row existed. The id is a poor label but a better one
/// than a blank line.
String eventName(String? name, String fallback) =>
    toProperCase((name == null || name.isEmpty) ? fallback : name);

/// `100` not `100.0`, but `92.5` stays `92.5`.
String formatPrNumber(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

/// The before-facts for one event — the previous frontier values it beat on
/// each dimension ("was 100 × 3 · 105 × 2"), or "First PR" when it beat nothing
/// (it was the first time either dimension was attempted).
String prBeforeFacts(PrEvent e) {
  final facts = <String>[
    if (e.beforeWeight != null)
      'was ${formatPrNumber(e.beforeWeight!)}kg × ${formatPrNumber(e.reps)}',
    if (e.beforeReps != null)
      'was ${formatPrNumber(e.weight)}kg × ${formatPrNumber(e.beforeReps!)}',
  ];
  return facts.isEmpty ? 'First PR' : facts.join(' · ');
}
