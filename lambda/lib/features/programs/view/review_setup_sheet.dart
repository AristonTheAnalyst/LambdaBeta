import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/program_history_viewmodel.dart';

/// What the user asked for when they set a review up.
///
/// Two answers, one per step: the workouts being reviewed, and what to call the
/// pass. Everything else the review needs is derived — it starts now, so there
/// is no date, and notes at the start would be notes about a plan the user has
/// not examined yet.
class ReviewSetupRequest {
  const ReviewSetupRequest({required this.sessionIds, this.title});

  /// The workouts the review covers, in the order the picker lists them. This
  /// is the whole scope — a review is a pass over a set, and the set is what
  /// the row stores.
  final List<String> sessionIds;

  /// What to call the review. Null when the user left it unnamed: a review
  /// without a name is still a review, and naming it is a convenience, not a
  /// condition.
  final String? title;
}

/// Sets a review up, one question at a time: which workouts, then what to call
/// the pass.
///
/// A wizard rather than one form because the two questions are read at
/// different moments — which workouts is a choice about the plan, the name is
/// about the pass — and stacking them made the common decision (which ones)
/// share a screen with the rare one (a name). Each step carries only its own
/// question, and the second one names what the first chose, so the set is never
/// in doubt while it is being named.
///
/// The first step is **tick-to-select**, the same interaction as the
/// add-exercise modal: a row ticks rather than navigates, and the confirm
/// button counts what is ticked. [preselectedIds] is how the run's
/// length-reached prompt offers its block already ticked — the user can add or
/// drop any of them, so it is a starting point, not a scope.
///
/// A review starts **now**, always: the sheet writes nothing itself, and the
/// caller takes the set and opens the ceremony on it. Scheduling is retired
/// for now — the repository and view model keep the plumbing, nothing in the
/// UI reaches it.
Future<ReviewSetupRequest?> showReviewSetupSheet(
  BuildContext context, {
  required List<WorkoutOption> workouts,
  List<String> preselectedIds = const [],
}) {
  return showLambdaModal<ReviewSetupRequest>(
    context,
    keyboardAware: true,
    child: SafeArea(
      child: _ReviewSetupSheet(
        workouts: workouts,
        preselectedIds: preselectedIds,
      ),
    ),
  );
}

class _ReviewSetupSheet extends StatefulWidget {
  const _ReviewSetupSheet({
    required this.workouts,
    required this.preselectedIds,
  });

  final List<WorkoutOption> workouts;
  final List<String> preselectedIds;

  @override
  State<_ReviewSetupSheet> createState() => _ReviewSetupSheetState();
}

class _ReviewSetupSheetState extends State<_ReviewSetupSheet> {
  final _title = TextEditingController();

  /// 1 = which workouts, 2 = what to call it. One question per step, and the
  /// second step does not exist until the first has an answer — the set is
  /// what the step is about.
  int _step = 1;

  late final Set<String> _picked = {...widget.preselectedIds};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// The workouts on offer, grouped under the block that holds them.
  ///
  /// Grouped rather than annotated on every row because the block is what the
  /// user is thinking in: "everything in Block 2" is one glance at one group,
  /// where a repeated block name on every row would bury the workout names.
  /// Groups appear in the program's own order, and a blockless program is a
  /// single group with no heading.
  List<({String? blockId, String? name, List<WorkoutOption> workouts})>
  get _groups {
    final byBlock = <String?, List<WorkoutOption>>{};
    final names = <String?, String?>{};
    for (final workout in widget.workouts) {
      (byBlock[workout.blockId] ??= []).add(workout);
      names[workout.blockId] = workout.blockName;
    }
    return [
      for (final entry in byBlock.entries)
        (
          blockId: entry.key,
          name: names[entry.key],
          workouts: entry.value,
        ),
    ];
  }

  void _toggle(String sessionId) {
    setState(() {
      if (!_picked.remove(sessionId)) _picked.add(sessionId);
    });
  }

  void _submit() {
    final title = _title.text.trim();
    Navigator.of(context).pop(
      ReviewSetupRequest(
        // In the order the picker lists them, not tick order: the review's
        // landing reads like the program afterwards, and a set ticked out of
        // order would open in a sequence the user never chose.
        sessionIds: [
          for (final workout in widget.workouts)
            if (_picked.contains(workout.sessionId)) workout.sessionId,
        ],
        title: title.isEmpty ? null : title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Start a review',
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _step == 1 ? 'STEP 1 OF 2' : 'STEP 2 OF 2',
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_step == 1) ..._stepOne() else ..._stepTwo(),
        ],
      ),
    );
  }

  List<Widget> _stepOne() {
    if (widget.workouts.isEmpty) return _emptyState();
    return [
      Text(
        'Which workouts',
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final group in _groups) ...[
        if (group.name case final name?) _GroupHeading(name),
        for (final workout in group.workouts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _WorkoutRow(
              workout: workout,
              ticked: _picked.contains(workout.sessionId),
              onTap: () => _toggle(workout.sessionId),
            ),
          ),
      ],
      const SizedBox(height: AppSpacing.md),
      SizedBox(
        width: double.infinity,
        child: GlassButton(
          label: _picked.length == 1
              ? 'Review 1 workout'
              : 'Review ${_picked.length} workouts',
          solid: true,
          disabled: _picked.isEmpty,
          onPressed: () => setState(() => _step = 2),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Opens each one so you can look through it and change what needs '
        'changing. Tick them off as you go — what it looks like when you '
        'finish is saved with the review.',
        style: AppFonts.ui(fontSize: AppTextStyles.xs, color: AppColors.muted),
      ),
    ];
  }

  /// A program with nothing in it can be opened, and the only honest thing the
  /// picker can say there is why it is empty — a confirm button that would
  /// write a review of nothing is not offered.
  List<Widget> _emptyState() => [
    Text(
      'Nothing to review yet',
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
    Text(
      'This program has no workouts in it. Add one first — then a review has '
      'something to look through.',
      style: AppFonts.ui(fontSize: AppTextStyles.xs, color: AppColors.muted),
    ),
  ];

  List<Widget> _stepTwo() => [
    Text(
      _picked.length == 1
          ? 'Reviewing ${_labelFor(_picked.single)}'
          : 'Reviewing ${_picked.length} workouts',
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    LambdaInput(
      controller: _title,
      // Short on purpose: a longer label overflows the field's own label row,
      // and "optional" is the one word that has to fit.
      label: 'Name (optional)',
      placeholder: 'End of block 1',
      textCapitalization: TextCapitalization.sentences,
      // The sheet's default background is a surface ground.
      elevated: true,
    ),
    const SizedBox(height: AppSpacing.xl),
    SizedBox(
      width: double.infinity,
      child: GlassButton(label: 'Start review', solid: true, onPressed: _submit),
    ),
    const SizedBox(height: AppSpacing.xs),
    Center(
      child: TextButton(
        onPressed: () => setState(() => _step = 1),
        child: Text(
          'Back',
          style: AppFonts.ui(color: AppColors.accent, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  ];

  String _labelFor(String sessionId) {
    for (final workout in widget.workouts) {
      if (workout.sessionId == sessionId) return workout.label;
    }
    return 'workout';
  }
}

/// A block's name over its workouts — the group's heading in the picker.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        name.toUpperCase(),
        style: AppFonts.mono(
          fontSize: AppTextStyles.xs,
          color: AppColors.muted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// One workout on offer: its name, how much is in it, and whether it is ticked.
///
/// Ticking is the same reading as the add-exercise modal — accent row, green
/// tick — because it is the same gesture (a sheet that stays open while the
/// user builds a set by tapping rows).
class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({
    required this.workout,
    required this.ticked,
    required this.onTap,
  });

  final WorkoutOption workout;
  final bool ticked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: glassBox(ticked ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Expanded(
              child: Text(
                workout.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(
                  fontSize: 14,
                  fontWeight: ticked ? FontWeight.w700 : FontWeight.w600,
                  color: ticked ? AppColors.accent : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              workout.exerciseCount == 1
                  ? '1 EXERCISE'
                  : '${workout.exerciseCount} EXERCISES',
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                color: AppColors.muted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              ticked ? Icons.check_circle : Icons.circle_outlined,
              size: 14,
              color: ticked ? AppColors.success : AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
