import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../goals/view/exercise_goals_sheet.dart';
import '../../goals/view/goal_sheet.dart';
import '../viewmodel/session_viewmodel.dart';
import 'exercise_notes_modal.dart';
import 'pr_history_sheet.dart';

/// The active workout's summary doors, in the Training page's sticky bottom
/// bar: a trophy, a bullseye and a book — the trophy, bullseye and book
/// openings the ACTIVE exercise's PRs, goals and notes ([SessionStatsTiles],
/// 2026-10-22), all three glyphs alone (2026-10-27). Every
/// door opens at any count, like the PR Lab's own bar — an exercise with no
/// notes still has its cues behind the book, so nothing goes dead
/// (2026-10-23). The trophy opens that exercise's PR History sheet, the book
/// its notes modal — scoped to the exercise on the card and the session on
/// the desk — and the bullseye its goals sheet.
class SessionStatsBar extends StatelessWidget {
  const SessionStatsBar({super.key, required this.vm});

  final SessionViewModel vm;

  void _openPrHistory(BuildContext context, String exerciseId) {
    showPrHistorySheet(
      context,
      exerciseName: toProperCase(vm.exerciseDisplayName(exerciseId)),
      prs: vm.prHistoryFor(exerciseId),
      sessionSetIds: vm.sessionPrSetIdsFor(exerciseId),
      sessionStartedAt: vm.workoutStartedAt,
      sessionIsLive: true,
      // A PR that also met a goal draws green (2026-10-26).
      goalSetIds: vm.goalSetIds,
    );
  }

  /// The floor's bullseye (2026-10-26): the exercise's goals on the PR
  /// History sheet's furniture, open ones first by default. Its New goal door
  /// opens the goals screen's form seeded with just this exercise — the way
  /// to a target that used to be the set row's swipe drawer.
  void _openGoals(BuildContext context, String exerciseId) {
    final name = toProperCase(vm.exerciseDisplayName(exerciseId));
    showExerciseGoalsSheet(
      context,
      exerciseName: name,
      listenable: vm,
      goalsFor: () => vm.goalsForExercise(exerciseId),
      setsFor: () => vm.goalTimeline,
      variationNames: {for (final v in vm.allVariations) v.variationId: v.name},
      onNewGoal: () => showAddGoalSheet(
        context,
        detailMap: vm.exerciseDetailMap,
        variations: vm.allVariations,
        lastUsed: vm.lastUsedByExercise,
        pastSets: vm.pastSets,
        seed: ExerciseTarget(exerciseId: exerciseId, exerciseName: name),
        onAdd: vm.createGoalFromTarget,
      ),
    );
  }

  void _openNotes(BuildContext context, String exerciseId) {
    showExerciseNotesModal(
      context,
      listenable: vm,
      notesFor: vm.notesFor,
      loadNotesFor: vm.loadNotesFor,
      addNote: vm.addNote,
      toggleNotePin: vm.toggleNotePin,
      deleteNote: vm.deleteNote,
      updateNote: vm.updateNoteText,
      exerciseId: exerciseId,
      exerciseName: toProperCase(vm.exerciseDisplayName(exerciseId)),
      sessionId: vm.currentWorkoutId,
      sessionStartedAt: vm.workoutStartedAt,
      sessionIsLive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        // The doors speak for the exercise on screen: its own session gains,
        // its own ledger and its own doors. The lab's rule (2026-10-22), kept
        // one step on (2026-10-27): a control lights only when the feed
        // behind it has something to say.
        final exerciseId = vm.activeSlot?.activeExerciseId;
        final prs = exerciseId == null ? 0 : vm.sessionPrCountFor(exerciseId);
        final notes = exerciseId == null
            ? 0
            : vm.exerciseNotesThisSession(exerciseId).length;
        final goals = exerciseId == null ? 0 : vm.openGoalsFor(exerciseId);
        return SessionStatsTiles(
          prCount: prs,
          exerciseNoteCount: notes,
          goalCount: goals,
          // Doors at any count: the sheets hold the exercise's whole story,
          // not only this session's additions (2026-10-23).
          onPrTap: exerciseId == null
              ? null
              : () => _openPrHistory(context, exerciseId),
          onNoteTap: exerciseId == null
              ? null
              : () => _openNotes(context, exerciseId),
          onGoalTap: exerciseId == null
              ? null
              : () => _openGoals(context, exerciseId),
        );
      },
    );
  }
}

/// The bar's doors, drawn (2026-10-22): a trophy, a bullseye and a note glyph,
/// each a glyph alone on a glass control the height of the undo/redo boxes
/// beside them (2026-10-27 — the bullseye's open-goal count rides only the
/// semantics now). Presentational only — the live bar binds a VM, the
/// past-session viewer binds its own state, and the planner binds the workout
/// editor.
///
/// **A door is neutral until it has something to say** (2026-10-27): the
/// container is the app's primary glass by default and the accent glass only
/// when the feed behind it is non-empty — the trophy when the session gained
/// PRs (the whole shelf on the planner), the bullseye when open goals stand,
/// the note when exercise notes exist. The star beside the row never takes
/// the accent: it is a door to the session's feelings, not a score.
///
/// Every control remains a door at any count (2026-10-23): the sheets hold
/// the exercise's whole story, so a `0` still opens. A null callback is the
/// no-exercise fallback: quiet surface fill, hairline, primary ink, no tap.
/// The whole control is one semantics node, so the reading never arrives
/// without its meaning.
///
/// The bullseye is drawn only when there is a door behind it ([onGoalTap]) —
/// a surface handing it no goal data (a friend's or athlete's record) draws
/// the two session doors without it.
///
/// A plan has no session to have gained anything in, so the planner asks for
/// the same controls with [gain] false (2026-10-26): the numbers behind them
/// are the whole shelves — every PR the exercise ever landed, every note it
/// carries — which is what decides their accent.
class SessionStatsTiles extends StatelessWidget {
  const SessionStatsTiles({
    super.key,
    required this.prCount,
    required this.exerciseNoteCount,
    this.goalCount = 0,
    this.onPrTap,
    this.onNoteTap,
    this.onGoalTap,
    this.gain = true,
  });

  final int prCount;
  final int exerciseNoteCount;

  /// How many of the exercise's goals still stand — what lights the bullseye
  /// and what it reads to a screen reader (2026-10-27). Read through
  /// `goalCompletionSet` over the same merged timeline the `G` badge uses.
  final int goalCount;

  final VoidCallback? onPrTap;
  final VoidCallback? onNoteTap;

  /// The exercise's goals — the bullseye drawn beside the PRs control when
  /// this is set (2026-10-26).
  final VoidCallback? onGoalTap;

  /// Whether the counts are one session's gain (the two session surfaces) or
  /// the whole feed's size (the planner). See the class doc.
  final bool gain;

  String _plural(int n, String noun) => n == 1 ? noun : '${noun}s';

  /// What a control says to a screen reader — the count rides the reading
  /// even where it is no longer drawn, and it names the feed the door opens.
  String _semantics(int n, String noun) =>
      gain ? '$n ${_plural(n, noun)} this session' : '$n ${_plural(n, noun)}';

  String _goalSemantics(int n) =>
      n == 0 ? 'Exercise goals' : '$n open ${_plural(n, 'goal')}';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _control(
            key: const ValueKey('session-prs-tile'),
            icon: Icons.emoji_events,
            semanticsLabel: _semantics(prCount, 'PR'),
            active: prCount > 0,
            onTap: onPrTap,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (onGoalTap != null) ...[
          Expanded(
            child: _control(
              key: const ValueKey('session-goals-button'),
              icon: Icons.track_changes,
              semanticsLabel: _goalSemantics(goalCount),
              active: goalCount > 0,
              onTap: onGoalTap,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: _control(
            key: const ValueKey('session-notes-tile'),
            icon: Icons.sticky_note_2_outlined,
            semanticsLabel: _semantics(exerciseNoteCount, 'exercise note'),
            active: exerciseNoteCount > 0,
            onTap: onNoteTap,
          ),
        ),
      ],
    );
  }

  /// The PR Lab's control recipe (2026-10-22): [kSessionBarControlSize] tall
  /// so the doors stand level with the undo/redo boxes and the star beside
  /// them, a 24px glyph and nothing else (2026-10-27 removed the last drawn
  /// count). Three equal thirds of the row at 402pt.
  Widget _control({
    Key? key,
    required IconData icon,
    required String semanticsLabel,
    required bool active,
    required VoidCallback? onTap,
  }) {
    final door = onTap != null;
    // Neutral until the feed behind it has something (2026-10-27): the
    // accent is the "there is something here" reading, never the chrome.
    final color = door && active ? AppColors.accent : AppColors.primary;
    return Semantics(
      button: true,
      label: semanticsLabel,
      // The reading is the whole control; the glyph must not announce itself
      // separately.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: key,
          height: kSessionBarControlSize,
          decoration: door
              ? glassBox(active ? AppColors.accent : AppColors.primary)
              : BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
          child: Center(child: Icon(icon, size: 24, color: color)),
        ),
      ),
    );
  }
}
