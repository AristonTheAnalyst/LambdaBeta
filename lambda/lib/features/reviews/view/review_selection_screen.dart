import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/floating_bar.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../viewmodel/reviews_viewmodel.dart';
import 'review_picker_rows.dart';

/// What the picker answered: the workouts and goals the pass will cover, each
/// in the order the picker listed them — the order the review stores, and so
/// the order its landing reads back.
class ReviewSelection {
  const ReviewSelection({required this.sessionIds, this.goalIds = const []});

  final List<String> sessionIds;
  final List<String> goalIds;
}

/// The second question the + button asks: what is this pass about?
///
/// One screen rather than a second wizard step, because the two halves are one
/// answer — a review contains workouts *and* goals — and doing them on one page
/// keeps the goals visible while the workouts are picked.
///
/// Ticking is the add-exercise modal's interaction, unchanged: rows tick in
/// place and the bar counts what is ticked. The result carries the set in
/// picker order, never tick order: the review's landing reads back in the order
/// the user was shown, and a set ticked bottom-up would open in a sequence
/// nobody chose.
///
/// It writes nothing. The caller takes the answer, starts the review and opens
/// the ceremony on it — the picker's whole job is the answer.
class ReviewSelectionScreen extends StatefulWidget {
  const ReviewSelectionScreen({
    super.key,
    required this.name,
    required this.workouts,
    required this.goals,
  });

  /// The pass's name, from the name sheet — the title says what this set is
  /// being picked for.
  final String name;

  /// Every workout on offer, in the recency order the loader returned.
  final List<ReviewableWorkout> workouts;

  /// Every goal on offer. Not grouped by program on purpose: a goal's scope is
  /// a chip on its own row, and grouping would bury the goals of a program the
  /// user is not reviewing.
  final List<ReviewableGoal> goals;

  @override
  State<ReviewSelectionScreen> createState() => _ReviewSelectionScreenState();
}

class _ReviewSelectionScreenState extends State<ReviewSelectionScreen> {
  final _pickedWorkouts = <String>{};
  final _pickedGoals = <String>{};

  void _toggle(Set<String> picked, String id) {
    setState(() {
      if (!picked.remove(id)) picked.add(id);
    });
  }

  void _submit() {
    Navigator.of(context).pop(
      ReviewSelection(
        sessionIds: [
          for (final workout in widget.workouts)
            if (_pickedWorkouts.contains(workout.sessionId)) workout.sessionId,
        ],
        goalIds: [
          for (final goal in widget.goals)
            if (_pickedGoals.contains(goal.goalId)) goal.goalId,
        ],
      ),
    );
  }

  /// What the bar counts, so "Start review" is never a leap: the same numbers
  /// the button is gated on.
  String get _countLabel {
    final workouts = _pickedWorkouts.length;
    if (workouts == 0 && _pickedGoals.isEmpty) return 'Pick what to review';
    return [
      workouts == 1 ? '1 workout' : '$workouts workouts',
      if (_pickedGoals.isNotEmpty)
        _pickedGoals.length == 1 ? '1 goal' : '${_pickedGoals.length} goals',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FloatingBarOverlay(
        bar: FloatingBar(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                GlassButton(
                  label: 'Start review',
                  compact: true,
                  solid: true,
                  // A review contains workouts — goals are the other half of
                  // one, but they ride along with the workouts that are
                  // examined. Nothing to walk = nothing to start.
                  disabled: _pickedWorkouts.isEmpty,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        child: Builder(
          // Below the overlay, so the inset knows a bar is there.
          builder: (context) => Column(
            children: [
              PageHeader(
                title: widget.name,
                left: IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.primary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: widget.workouts.isEmpty
                    ? const _EmptyLibrary()
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          FloatingBarOverlay.contentInset(context),
                        ),
                        children: [
                          const ReviewSectionLabel('WORKOUTS'),
                          const SizedBox(height: AppSpacing.sm),
                          for (final workout in widget.workouts)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: ReviewTickRow(
                                title: workout.label,
                                caption: [
                                  workout.sinceReviewLabel,
                                  workout.finishedLabel,
                                ],
                                ticked: _pickedWorkouts.contains(
                                  workout.sessionId,
                                ),
                                onTap: () =>
                                    _toggle(_pickedWorkouts, workout.sessionId),
                              ),
                            ),
                          if (widget.goals.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            const ReviewSectionLabel('GOALS'),
                            const SizedBox(height: AppSpacing.sm),
                            for (final goal in widget.goals)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: ReviewTickRow(
                                  title: goal.exerciseName,
                                  target: goal.target,
                                  ticked: _pickedGoals.contains(goal.goalId),
                                  onTap: () =>
                                      _toggle(_pickedGoals, goal.goalId),
                                ),
                              ),
                          ],
                          // Goals without a workout is not a review. Saying so
                          // here, while the Start button sits disabled, beats
                          // letting the dead button be the explanation.
                          if (_pickedWorkouts.isEmpty &&
                              _pickedGoals.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: Text(
                                'A review needs at least one workout — goals '
                                'ride along with the workouts you pick.',
                                style: AppFonts.ui(
                                  fontSize: AppTextStyles.xs,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A library with nothing to review: there is no honest confirm button, so the
/// screen says why it is empty instead of offering a start it cannot make.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nothing to review yet',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A review looks through workouts you already have. Create one '
            'first — then a review has something to walk.',
            textAlign: TextAlign.center,
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}
