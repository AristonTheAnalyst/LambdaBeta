import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../programs/model/program_achievements.dart';

/// The focused view of one goal — the same form the New goal sheet composes,
/// resting (2026-10-19).
///
/// Previewing a goal and creating one are the same act seen from two sides:
/// the exercise selector, the KG · REPS · VARIATION row, the notes, the
/// deadline and the floor button are the [ExerciseTargetPicker], the identical
/// control the add sheet draws. The difference is mode, not layout — the sheet
/// **rests** in a reading, where every field shows its value and none can be
/// entered, and Edit (top right) turns the same form live. SAVE replaces ADD
/// at the floor and stays disabled until the draft actually differs from the
/// stored goal; saving writes the whole row and returns the sheet to rest.
///
/// There is no per-keystroke write and no "Add a note…" invite any more: a
/// goal's notes are one of its fields, edited with the rest of it.
///
/// A null [onSave] is the **record** state — a completed review's goal opened
/// to be read. There is no Edit and no way in; the form is the same form, and
/// a goal the record left nothing about gets no NOTES section at all rather
/// than an empty box offering a place to write. The two states differ in what
/// can be reached, never in what is shown.
///
/// [exerciseName] is built by the caller with `goalExerciseNameFor`, because
/// the caller is the one holding the exercise detail map — and it is the name
/// a goal keeps when its exercise has left the library, which the picker
/// falls back to for an id its [detailMap] no longer holds.
///
/// Under the title sits the **created date** — stamped by the row at insert,
/// never editable — and right of the deadline sits a **history button** (a
/// clock) that opens the vertical list of every move of that deadline
/// (2026-10-19). The draft's moves are not recorded until SAVE: a change that
/// was never written is not a fact.
///
/// **The completion reads under the deadline** (2026-10-20): once the stored
/// target has been met, "Completed 13 Oct 2026" sits beneath the TARGET DATE
/// field — the goal's two dates, one above the other — and tapping it opens
/// the workout that hit the goal, the same door the creation form's "you've
/// already beat this" caption offers. That caption is the creation form's
/// alone: a stored goal does not need its own target re-checked, and the
/// completion row says the settled fact instead.
Future<void> showGoalSheet(
  BuildContext context, {
  required Goal goal,
  required String exerciseName,
  Map<String, ExerciseDetail> detailMap = const {},
  List<CustomVariation> variations = const [],
  required Future<List<PastSetRow>> Function() loadPastSets,
  Future<Goal?> Function(ExerciseTarget target)? onSave,
  void Function(PastSetRow set)? onOpenWorkout,
}) => showLambdaModal<void>(
  context,
  fitContent: true,
  keyboardAware: true,
  child: _GoalSheet(
    goal: goal,
    exerciseName: exerciseName,
    detailMap: detailMap,
    variations: variations,
    loadPastSets: loadPastSets,
    onSave: onSave,
    onOpenWorkout: onOpenWorkout,
  ),
);

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({
    required this.goal,
    required this.exerciseName,
    required this.detailMap,
    required this.variations,
    required this.loadPastSets,
    required this.onSave,
    required this.onOpenWorkout,
  });

  final Goal goal;
  final String exerciseName;
  final Map<String, ExerciseDetail> detailMap;
  final List<CustomVariation> variations;
  final Future<List<PastSetRow>> Function() loadPastSets;

  /// Writes the whole goal, returning the row as stored. Null on a record:
  /// the report it would take is already made, so every way into edit mode —
  /// and the Edit control itself — is gone with it.
  final Future<Goal?> Function(ExerciseTarget target)? onSave;

  final void Function(PastSetRow set)? onOpenWorkout;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  /// The goal as it now stands — the row the save read back, so the form, the
  /// notes and the deadline history follow the write without closing.
  late Goal _goal = widget.goal;

  /// The form's contents, seeded from the goal. Sheet-local rather than held
  /// by the list: an edit is committed by SAVE, and a dismissal before it is
  /// a discarded edit, not a lost draft.
  final _draft = ExerciseTargetDraft();

  /// The timeline the "already beat this" check reads, empty until it
  /// arrives. A failed read leaves it empty: the sentence is an extra, and
  /// claiming nothing is the only honest answer a read that never happened
  /// has.
  List<PastSetRow> _sets = const [];

  /// The set that met the stored goal, when one has — the workout the
  /// completion row under the deadline opens, and the day it states
  /// (2026-10-20). Derived with the same rule the goal list's cards use
  /// ([earliestSetReaching] over the list's own "earliest set" evidence), so
  /// the sheet and the card can never disagree about which day the goal was
  /// hit.
  PastSetRow? _completedSet;

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _seedFrom(_goal);
    // A goal with no exercise has nothing to measure; opening it never reads
    // the timeline.
    if (_goal.exerciseId != null) _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _seedFrom(Goal goal) => _draft.seed(
    exerciseId: goal.exerciseId,
    variationId: goal.variationId,
    weight: goal.targetWeight,
    reps: goal.targetReps,
    // The values and the shape are separate facts: a single-set goal's one
    // pair arrives in weight/reps, a multi-set goal's rungs in targets —
    // and `multiSet` is what the toggle shows (2026-10-26).
    targets: goal.requirements,
    multiSet: goal.isMultiSet,
    notes: goal.description,
    targetDate: goal.targetDate,
  );

  Future<void> _load() async {
    try {
      final sets = await widget.loadPastSets();
      if (!mounted) return;
      setState(() {
        _sets = sets;
        _completedSet = _deriveCompletedSet();
      });
    } catch (_) {
      // Silent by design: the achieved sentence is a caption on the form, not
      // the form's reason to exist, and an error line would outrank the goal
      // it is about.
    }
  }

  /// The first set that met the STORED target — the set that achieved the
  /// goal, which is the one the grids mark with `G` and the one whose workout
  /// the completion row opens (2026-10-20). Read against the stored goal
  /// rather than the draft: the completion day belongs to the target that was
  /// actually met, and an edit in progress has not met anything yet. A
  /// multi-set goal is complete on its LAST rung (`goalCompletionSet`,
  /// 2026-10-26), because the earlier ones only finish it.
  PastSetRow? _deriveCompletedSet() =>
      goalCompletionSet(goal: _goal, sets: _sets);

  /// Whether the draft says something the stored goal does not. Text is
  /// compared trimmed (blank and absent are one spelling of no notes) and the
  /// day by calendar day, never by clock. The target is compared per shape
  /// (2026-10-26): a multi-set draft against the stored requirement list — a
  /// toggled shape or a reordered/re-numbered rung is a change — and a
  /// single-set draft against the stored pair.
  bool get _dirty {
    final goal = _goal;
    final weight = double.tryParse(_draft.weightCtrl.text.trim());
    final reps = int.tryParse(_draft.repsCtrl.text.trim());
    final targetsDiffer = _draft.multiSet != goal.isMultiSet
        ? true
        : _draft.multiSet
        ? !_sameTargets(_draft.statedTargets, goal.requirements)
        : weight != goal.targetWeight || reps != goal.targetReps;
    return _draft.exerciseId != goal.exerciseId ||
        _draft.variationId != goal.variationId ||
        targetsDiffer ||
        _draft.notesCtrl.text.trim() != (goal.description ?? '') ||
        !_sameDay(_draft.targetDate, goal.targetDate);
  }

  /// SAVE: the picker composed the whole form, the host writes it. A success
  /// adopts the row as stored — re-seeding the boxes from it is what makes
  /// SAVE go quiet again (the stored notes are trimmed, the date is a day) —
  /// and returns the sheet to its reading.
  Future<void> _save(ExerciseTarget target) async {
    final onSave = widget.onSave;
    if (onSave == null) return;
    try {
      final updated = await onSave(target);
      if (!mounted || updated == null) return;
      setState(() {
        _goal = updated;
        _seedFrom(updated);
        // A saved target can change the verdict — the completion row under
        // the deadline must agree with the card the list will draw
        // (2026-10-20).
        _completedSet = _deriveCompletedSet();
        _editing = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not save the goal.')),
      );
    }
  }

  /// A goal day as the app writes it — "19 Oct 2026".
  String _dayLabel(DateTime date) =>
      DateFormat('d MMM yyyy').format(date.toLocal());

  @override
  Widget build(BuildContext context) {
    final writable = widget.onSave != null;
    final hasNotes = (_goal.description ?? '').trim().isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Goal',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        // When the goal was said — the one date on this sheet
                        // nothing edits, so it reads as the title's subtext
                        // rather than as a field (2026-10-19).
                        if (_goal.createdDate != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Created ${_dayLabel(_goal.createdDate!)}',
                            style: AppFonts.mono(
                              fontSize: AppTextStyles.xs,
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (writable && !_editing)
                    GlassButton(
                      label: '',
                      icon: LucideIcons.pencil,
                      semanticsLabel: 'Edit goal',
                      compact: true,
                      onPressed: () => setState(() => _editing = true),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              ExerciseTargetPicker(
                detailMap: widget.detailMap,
                variations: widget.variations,
                // Read for two things: the order the selector opens on, and
                // the "already beat this" verdict the row answers with.
                lastUsed: lastUsedByEntity(_sets),
                pastSets: _sets,
                draft: _draft,
                enabled: _editing,
                actionLabel: 'SAVE',
                // Enabled only for a real change, computed on each rebuild so
                // the form's own keystrokes reach it.
                actionEnabled: () =>
                    _editing && _dirty && _draft.exerciseId != null,
                fallbackExerciseName: widget.exerciseName,
                // The clock beside the deadline, when there is a history to
                // read — null on a goal that never moved it (2026-10-19).
                onOpenTargetDateHistory: _goal.targetDateHistory.isEmpty
                    ? null
                    : () => showTargetDateHistorySheet(
                        context,
                        history: _goal.targetDateHistory,
                      ),
                // A record that left no notes gets no section: an empty box
                // would offer a place to write on a surface that cannot.
                showNotes: writable || hasNotes,
                // The creation caption answers a draft target being composed;
                // a stored goal states its completion under the deadline
                // instead (2026-10-20).
                showAchievedNote: false,
                completedSet: _completedSet,
                onOpenWorkout: widget.onOpenWorkout,
                onAdd: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The goal's deadline history as a vertical list (2026-10-19) — the sheet
/// behind the clock button beside the deadline.
///
/// Newest first: the row nearest the top is the move that produced the date
/// on screen. Each row names the day the deadline became and, under it, when
/// it changed and what it was before. A null side is "no deadline" and reads
/// as the history's own spelling, "no date".
Future<void> showTargetDateHistorySheet(
  BuildContext context, {
  required List<GoalTargetDateChange> history,
}) => showLambdaModal<void>(
  context,
  fitContent: true,
  child: _TargetDateHistorySheet(history: history),
);

class _TargetDateHistorySheet extends StatelessWidget {
  const _TargetDateHistorySheet({required this.history});

  final List<GoalTargetDateChange> history;

  String _day(DateTime? date) => date == null
      ? 'no date'
      : DateFormat('d MMM yyyy').format(date.toLocal());

  @override
  Widget build(BuildContext context) {
    // Stored oldest first; read newest first — a history is read from what
    // just happened.
    final changes = history.reversed.toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          key: const ValueKey('goal-target-date-history-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Target date changes',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < changes.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _row(changes[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(GoalTargetDateChange change) {
    final to = change.to;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // The field the clock sits in, worn by every row — one chrome for the
      // deadline and the moves it made.
      decoration: glassBox(AppColors.primary),
      child: Row(
        children: [
          Icon(
            LucideIcons.calendar,
            size: 16,
            color: to == null ? AppColors.muted : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  to == null ? 'No target date' : _day(to),
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: to == null ? FontWeight.w500 : FontWeight.w700,
                    color: to == null
                        ? AppColors.inkSecondary
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Changed ${_day(change.changedAt)} · was ${_day(change.from)}',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
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

/// Whether two goal dates name the same calendar day. Null is "no deadline",
/// and equals only itself.
bool _sameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Whether two requirement lists state the same rungs in the same order —
/// [GoalTargetSet] equals by its numbers, so the comparison is positional
/// (2026-10-26).
bool _sameTargets(List<GoalTargetSet> a, List<GoalTargetSet> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The New goal sheet — the target composer the focused goal sheet rests in,
/// live, and one sheet for a whole sitting with the goal list (2026-10-26).
///
/// It stays mounted after a write: goals are often written in a run, and
/// closing on the first one made every further target a dismissal and a trip
/// back to +. A success therefore clears the form for the next goal and says
/// what it wrote in the title's caption for three seconds — the sheet itself
/// does not move. **Done** in the header is the one way out that says it; a
/// tap outside or the back gesture still dismisses, and a dismissal keeps
/// whatever is typed, as it always has (2026-10-19). Only a written goal
/// clears the draft.
///
/// The write belongs to the host: [onAdd] returns whether the goal was
/// written, and a false keeps the form standing — values and all — with the
/// failure said. A host that reuses this sheet from another surface (a live
/// set opening its own target form, say) passes its own [draft] and its own
/// [onAdd]; nothing here knows the goal list.
///
/// A session surface opens it the other way (2026-10-26): it passes a
/// [seed] — the set under the user's thumb, exercise · variation · weight ·
/// reps — and no [draft]. The sheet then owns a one-shot draft filled from
/// the seed and takes it with it when it closes, because the door's meaning
/// is "from THIS set": every open starts on the row it was opened from, and
/// there is no form to resume. The goals screen keeps the long-lived [draft]
/// it has always passed, so a dismissal there still keeps what was typed.
Future<void> showAddGoalSheet(
  BuildContext context, {
  required Map<String, ExerciseDetail> detailMap,
  required List<CustomVariation> variations,
  required Map<String, DateTime> lastUsed,
  required List<PastSetRow> pastSets,
  ExerciseTargetDraft? draft,
  ExerciseTarget? seed,
  required Future<bool> Function(ExerciseTarget target) onAdd,
  void Function(PastSetRow set)? onOpenWorkout,
}) {
  assert(
    draft == null || seed == null,
    'A draft and a seed are two spellings of the same form: the host keeps '
    'the draft, or the sheet makes one from the seed.',
  );
  return showLambdaModal<void>(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _AddGoalSheet(
      detailMap: detailMap,
      variations: variations,
      lastUsed: lastUsed,
      pastSets: pastSets,
      draft: draft,
      seed: seed,
      onAdd: onAdd,
      onOpenWorkout: onOpenWorkout,
    ),
  );
}

class _AddGoalSheet extends StatefulWidget {
  const _AddGoalSheet({
    required this.detailMap,
    required this.variations,
    required this.lastUsed,
    required this.pastSets,
    required this.draft,
    required this.seed,
    required this.onAdd,
    this.onOpenWorkout,
  });

  final Map<String, ExerciseDetail> detailMap;
  final List<CustomVariation> variations;

  /// exercise-id/variation-id → the date last trained — the picker's ordering.
  final Map<String, DateTime> lastUsed;

  /// The user's logged sets — the "already beat this" check's history.
  final List<PastSetRow> pastSets;

  /// The form's contents, owned by the host so a dismissal keeps them. Null
  /// on a session door, which has nothing to resume: the sheet makes its own
  /// from [seed] and disposes of it when it closes.
  final ExerciseTargetDraft? draft;

  /// What a session door opens the form on — the set the user swiped. Read
  /// only when [draft] is null, and once: a dismissal ends the draft.
  final ExerciseTarget? seed;

  /// Opens the workout that beat the typed target. Null in a host with no
  /// route to the logs — the sentence still reads, it just does not move.
  final void Function(PastSetRow set)? onOpenWorkout;

  /// True when the goal was written. A failure keeps the sheet and the typed
  /// target standing.
  final Future<bool> Function(ExerciseTarget target) onAdd;

  @override
  State<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<_AddGoalSheet> {
  /// How long a written goal keeps the caption that says so.
  static const _confirmation = Duration(seconds: 3);

  /// The last goal this sheet wrote, named the way the list's card names it —
  /// the caption under "New goal" while it lasts. It explains the form
  /// clearing itself: a reset with no word would read as a loss.
  String? _addedLabel;
  Timer? _addedTimer;

  /// The form, wherever it came from: the host's long-lived draft (the goals
  /// screen) or one made here from [widget.seed].
  late final ExerciseTargetDraft _draft;

  /// Whether [_draft] is this sheet's to dispose — a session door's draft
  /// dies with the sheet, so the next set opens on its own values rather
  /// than on the last one's.
  late final bool _ownsDraft;

  @override
  void initState() {
    super.initState();
    final given = widget.draft;
    _ownsDraft = given == null;
    _draft = given ?? ExerciseTargetDraft();
    final seed = widget.seed;
    if (_ownsDraft && seed != null) {
      _draft.seed(
        exerciseId: seed.exerciseId,
        variationId: seed.variationId,
        weight: seed.weight,
        reps: seed.reps,
        notes: seed.notes,
      );
    }
  }

  @override
  void dispose() {
    _addedTimer?.cancel();
    if (_ownsDraft) _draft.dispose();
    super.dispose();
  }

  /// ADD: the host writes, and a written goal resets the form for the next
  /// one without closing the sheet. The draft clears AFTER the write, so a
  /// failure keeps everything typed.
  Future<void> _add(ExerciseTarget target) async {
    final added = await widget.onAdd(target);
    if (!mounted) return;
    if (!added) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not add the goal.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final label = target.targets.isEmpty
        ? goalTargetLabel(target.exerciseName, target.weight, target.reps)
        : goalTargetsLabel(target.exerciseName, target.targets);
    setState(() {
      _draft.reset();
      _addedLabel = label;
    });
    _addedTimer?.cancel();
    _addedTimer = Timer(_confirmation, () {
      if (mounted) setState(() => _addedLabel = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'New goal',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.lg,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // One caption, two readings: what a goal is while the
                      // form is empty, what was just written for a moment
                      // after it fills one (2026-10-26). Reusing the slot
                      // keeps the composer from shifting under the hand that
                      // is already reaching for the next target.
                      if (_addedLabel != null)
                        _addedNote(_addedLabel!)
                      else
                        Text(
                          'A set to beat — a weight × reps target on any '
                          'exercise.',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.xs,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // A word, because it is the sheet's exit verb and the scrim
                // gives the same act no name at all (convention 13).
                GlassButton(
                  label: 'Done',
                  compact: true,
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ExerciseTargetPicker(
              detailMap: widget.detailMap,
              variations: widget.variations,
              lastUsed: widget.lastUsed,
              pastSets: widget.pastSets,
              draft: _draft,
              onOpenWorkout: widget.onOpenWorkout,
              onAdd: _add,
            ),
          ],
        ),
      ),
    );
  }

  /// The written goal as a success chip in the caption's slot — the same
  /// icon-and-ink recipe as the "already beat this" caption, so a
  /// confirmation never invents a second green (frontend-design §2).
  Widget _addedNote(String label) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('goal-added-confirmation'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleCheck, size: 14, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Added $label',
              style: AppFonts.ui(
                fontSize: AppTextStyles.xs,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
