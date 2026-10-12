import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/lambda_readout.dart';
import '../../../shared/widgets/pr_event_row.dart' show formatPrNumber;
import '../../../shared/widgets/slide_up_modal.dart';
import '../../exercises/model/exercise_insights.dart';
import '../../session/model/pr_engine.dart';
import 'goal_row.dart';

/// The focused view of one goal — what it is, what to say about it, and the
/// history that measures it.
///
/// "Similar to PRs" is the whole idea. A goal is a set to beat (weight × reps
/// on one exercise × variation), and the PR lenses already answer the two
/// questions that set raises: every set that raised the best reps at exactly
/// this weight ([weightAxisHistory]), and every set that raised the best
/// weight at this many reps or better ([repAxisHistory]) — the same
/// equal-or-better reading `evaluateGoals` uses. The sheet invents no
/// comparison of its own; it shows the two histories the target sits on.
///
/// The description is writable here and only here, but the sheet **rests** in
/// view mode: looking at a goal must not be able to change it, so the notes
/// read back through [LambdaReadout] and edit mode is entered on purpose.
/// Writes fire per keystroke through [onDescriptionChanged] — one less thing
/// to lose to a dismiss — and nothing else on this sheet is editable.
///
/// A null [onDescriptionChanged] is the **record** state — a completed
/// review's goal opened to be read. The notes then rest read-only with no way
/// into edit mode at all: no pencil, no tap-to-edit, no "Add a note…" invite
/// on a goal the record left nothing about, and an empty section not drawn.
/// The two states differ in what can be reached, never in what is shown.
///
/// [exerciseName] is built by the caller with `goalExerciseNameFor`, because
/// the caller is the one holding the exercise detail map. The target needs no
/// such help — it is the goal's own two numbers ([goalTargetValue]).
Future<void> showGoalSheet(
  BuildContext context, {
  required Goal goal,
  required String exerciseName,
  required Future<void> Function(String description)? onDescriptionChanged,
  required Future<List<PastSetRow>> Function() loadPastSets,
}) => showLambdaModal<void>(
  context,
  fitContent: true,
  keyboardAware: true,
  child: _GoalSheet(
    goal: goal,
    exerciseName: exerciseName,
    onDescriptionChanged: onDescriptionChanged,
    loadPastSets: loadPastSets,
  ),
);

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({
    required this.goal,
    required this.exerciseName,
    required this.onDescriptionChanged,
    required this.loadPastSets,
  });

  final Goal goal;
  final String exerciseName;

  /// Writes the notes as they are typed. Null on a record: the sheet is a
  /// reading, and every way into edit mode is gone with the callback.
  final Future<void> Function(String description)? onDescriptionChanged;

  final Future<List<PastSetRow>> Function() loadPastSets;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final TextEditingController _ctrl;

  /// The last text a write carried — the per-keystroke guard. Opening and
  /// closing the sheet writes nothing (the seed is the stored value), and
  /// A → B → A writes each step. It only advances on success, so a failed
  /// write is carried again by the next keystroke: the whole text is written
  /// every time, so nothing can be stranded by one failure.
  late String _lastWritten;

  bool _editing = false;

  /// The exercise's whole logged history, null until it arrives. A failed
  /// read is [_historyFailed] rather than an empty list — "no sets at this
  /// weight" must never be claimed for a read that never happened.
  List<PastSetRow>? _sets;
  bool _historyFailed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.goal.description ?? '');
    _lastWritten = _ctrl.text;
    // Only an exercise goal with a target has axes to read for; a text-only
    // goal never touches the timeline.
    if (_hasAxes) _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hasAxes =>
      widget.goal.exerciseId != null &&
      (widget.goal.targetWeight != null || widget.goal.targetReps != null);

  Future<void> _load() async {
    try {
      final sets = await widget.loadPastSets();
      if (!mounted) return;
      setState(() => _sets = sets);
    } catch (_) {
      if (!mounted) return;
      setState(() => _historyFailed = true);
    }
  }

  /// Whether the notes can be written at all — false on a record, where the
  /// sheet shows and writes nothing.
  bool get _editable => widget.onDescriptionChanged != null;

  Future<void> _write(String text) async {
    final onDescriptionChanged = widget.onDescriptionChanged;
    if (onDescriptionChanged == null || text == _lastWritten) return;
    try {
      await onDescriptionChanged(text);
      _lastWritten = text;
    } catch (_) {
      if (!mounted) return;
      // The box keeps what was typed — the next keystroke carries it again.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not save the description.')),
      );
    }
  }

  void _startEditing() => setState(() => _editing = true);

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final description = goal.description?.trim() ?? '';
    final sets = _sets;
    // Scoped to the goal's exact pair: null variation is its own scope, the
    // same rule the lenses and evaluateGoals apply.
    final pairSets = (goal.exerciseId == null || sets == null)
        ? const <PastSetRow>[]
        : setsScoped(sets, goal.exerciseId!, goal.variationId);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Goal',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              GoalRow(
                exerciseName: widget.exerciseName,
                target: goalTargetValue(goal.targetWeight, goal.targetReps),
                onDelete: null,
              ),
              const SizedBox(height: AppSpacing.lg),
              // A record that left nothing about this goal gets no NOTES
              // section at all: there is nothing to read back, and an empty
              // header over an empty space would only promise one.
              if (_editable || description.isNotEmpty) ...[
                Row(
                  children: [
                    const _SectionLabel('NOTES'),
                    const Spacer(),
                    if (_editable && !_editing && description.isNotEmpty)
                      GestureDetector(
                        onTap: _startEditing,
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_editing)
                  LambdaInput(
                    controller: _ctrl,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 5,
                    elevated: true,
                    placeholder: 'Why this goal, or what to watch…',
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _write,
                  )
                else if (description.isNotEmpty)
                  GestureDetector(
                    // Inert on a record — the box is read there, not entered.
                    onTap: _editable ? _startEditing : null,
                    child: LambdaReadout(value: description),
                  )
                else
                  GestureDetector(
                    onTap: _startEditing,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Add a note…',
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              // One section per axis the target carries: the picker takes
              // weight and reps independently, so a goal may have only one.
              if (_hasAxes) ...[
                if (goal.targetWeight != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _axis(
                    title: 'AT ${formatPrNumber(goal.targetWeight!)} KG',
                    empty: 'No sets at ${formatPrNumber(goal.targetWeight!)} '
                        'kg yet.',
                    rungs: sets == null
                        ? null
                        : weightAxisHistory(pairSets, goal.targetWeight!),
                    // Every rung is at the same weight — the reps are what
                    // moved.
                    value: (s) => '${_repsOf(s)} reps',
                  ),
                ],
                if (goal.targetReps != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _axis(
                    title: 'AT ${goal.targetReps} REPS',
                    empty: 'No sets of ${goal.targetReps}+ reps yet.',
                    rungs: sets == null
                        ? null
                        : repAxisHistory(pairSets, goal.targetReps!),
                    // The rung's weight is the value; the reps it was done for
                    // are the context (a better rung may beat the target).
                    value: (s) =>
                        '${formatPrNumber(s.weight ?? 0)} kg × ${_repsOf(s)}',
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One axis: its header, then the rungs newest-first.
  ///
  /// A null [rungs] is the read still in flight. Capped and scrollable like
  /// every other list on a sheet — a long history must not push the notes box
  /// off the sheet, and the keyboard makes the room smaller still.
  Widget _axis({
    required String title,
    required String empty,
    required List<PastSetRow>? rungs,
    required String Function(PastSetRow) value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(title),
        const SizedBox(height: AppSpacing.sm),
        if (_historyFailed)
          _muted("Couldn't read your history.")
        else if (rungs == null)
          _muted('Loading…')
        else if (rungs.isEmpty)
          _muted(empty)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final (i, s) in rungs.reversed.indexed)
                    _RungRow(
                      value: value(s),
                      date: _shortDate(s.sessionCreatedDate.toLocal()),
                      // The lens returns oldest-first; the newest entry is
                      // the current best and wears the accent.
                      newest: i == 0,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _muted(String text) => Text(
    text,
    style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted),
  );
}

/// One rung of an axis — a set that raised the best on that axis, with the
/// day it happened.
///
/// Not [PrEventRow]: that row states the before-facts of a [PrEvent] ("was
/// 100 kg × 3"), which a lens rung never claims — a rung is the progression
/// itself, one value. The mono numbers and the accent on the latest are the
/// same, because the latest rung *is* the current best.
class _RungRow extends StatelessWidget {
  const _RungRow({
    required this.value,
    required this.date,
    required this.newest,
  });

  final String value;
  final String date;
  final bool newest;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: lambdaBox(
        newest ? ContainerTone.accent : ContainerTone.outline,
        radius: AppRadius.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: AppFonts.mono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: newest ? AppColors.accent : AppColors.muted,
              ),
            ),
          ),
          Text(
            date,
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppFonts.mono(
      fontSize: AppTextStyles.xs,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: AppColors.muted,
    ),
  );
}

/// The reps a set logged. A lens never emits a set without them, but the row
/// degrades to a dash rather than crashing on one that somehow has none.
String _repsOf(PastSetRow s) =>
    s.reps.isEmpty ? '—' : formatPrNumber(s.reps.first);

String _shortDate(DateTime d) => DateFormat('d MMM').format(d);
