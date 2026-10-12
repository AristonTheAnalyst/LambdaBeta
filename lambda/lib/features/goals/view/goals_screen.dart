import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/goal.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../viewmodel/goals_viewmodel.dart';
import 'goal_row.dart';
import 'goal_sheet.dart';

/// The goals library: every target the user is chasing, and the picker that
/// adds one.
///
/// Goals live by themselves (2026-10-08) — no program, no block — so this is
/// their own home beside Reviews, built from the same parts: the library's
/// embedded form, the shared [GoalRow], and the focused sheet a tap opens.
/// The add control is inline at the foot of the list rather than a + in the
/// header, because adding a goal *is* the list's last row — that is where the
/// eye is when the previous one is read.
///
/// [showHeader] false is the embedded form — the Library's Goals tab — where
/// the host owns the header and this screen contributes a caption line
/// instead, the same idiom as the workout and review libraries.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, this.showHeader = true, this.viewModel});

  final bool showHeader;

  /// The view model to render, when a caller already has one.
  ///
  /// Null = the screen loads its own. The seam exists for host tests: the
  /// repositories this screen reads through reach PowerSync, which a widget
  /// test has no way to stand up, so the only place to inject a fake is above
  /// them. A real caller never passes one — this screen owns its goals.
  final GoalsViewModel? viewModel;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late final GoalsViewModel _vm;

  /// Whether [_vm] is this screen's to dispose. An injected view model belongs
  /// to whoever passed it — and a host test that supplies one goes on asserting
  /// against it after the widget is gone.
  var _ownsVm = true;

  @override
  void initState() {
    super.initState();
    final injected = widget.viewModel;
    _ownsVm = injected == null;
    _vm = injected ?? GoalsViewModel();
    _vm.state.addListener(_onState);
    // A caller that supplied the view model supplied its state too — loading
    // over it would replace what they set up.
    if (injected == null) _vm.load();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.state.removeListener(_onState);
    if (_ownsVm) _vm.dispose();
    super.dispose();
  }

  /// The focused view. The goal's own history is read fresh here rather than
  /// served from the list's load — a sheet opened after a workout is logged
  /// must see that workout.
  Future<void> _open(Goal goal) => showGoalSheet(
    context,
    goal: goal,
    exerciseName: goalExerciseNameFor(goal, _vm.state.value.exerciseDetailMap),
    // The view model rethrows; the sheet keeps the typed text and says so.
    onDescriptionChanged: (description) =>
        _vm.setGoalDescription(goal.goalId, description),
    loadPastSets: _vm.loadPastSets,
  );

  void _add(ExerciseTarget target) {
    _vm.addGoal(
      exerciseId: target.exerciseId,
      exerciseName: target.exerciseName,
      variationId: target.variationId,
      targetWeight: target.weight,
      targetReps: target.reps,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _vm.state.value;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          if (widget.showHeader) const PageHeader(title: 'Goals'),
          if (!widget.showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sets to beat — a weight × reps target on any exercise.',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  Widget _body(GoalsState state) {
    // The list stays up through a refresh — only a cold open has nothing to
    // show while the read is in flight.
    if (state.isLoading && state.goals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.goals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GlassButton(label: 'Retry', onPressed: _vm.load),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        // Zero unless the shell's bar is floating over this list, which is
        // where the Library's Goals tab lives.
        AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
      ),
      children: [
        // A failure with rows still on screen — a delete that did not go
        // through — says so above them rather than replacing them.
        if (state.error != null) ...[
          Text(
            state.error!,
            textAlign: TextAlign.center,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (state.goals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              "No goals set — add a PR target you'd like to hit.",
              textAlign: TextAlign.center,
              style: AppFonts.ui(
                fontSize: AppTextStyles.md,
                color: AppColors.muted,
              ),
            ),
          )
        else
          for (final goal in state.goals) ...[
            // The × inside keeps its own gesture — a delete must not also
            // open the sheet.
            GestureDetector(
              onTap: () => _open(goal),
              child: GoalRow(
                exerciseName: goalExerciseNameFor(goal, state.exerciseDetailMap),
                target: goalTargetValue(goal.targetWeight, goal.targetReps),
                outcome: state.outcomes[goal.goalId],
                onDelete: () => _vm.deleteGoal(goal.goalId),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        const SizedBox(height: AppSpacing.sm),
        ExerciseTargetPicker(
          detailMap: state.exerciseDetailMap,
          variations: state.variations,
          onAdd: _add,
        ),
      ],
    );
  }
}
