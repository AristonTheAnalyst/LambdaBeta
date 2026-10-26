import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../goals/view/exercise_goals_sheet.dart';
import '../../goals/view/goal_sheet.dart';
import '../viewmodel/session_viewmodel.dart';
import 'lessons_modal.dart';
import 'pr_history_sheet.dart';

/// The active workout's summary doors, in the Training page's sticky bottom
/// bar: a trophy, a bullseye and a book — the trophy and book carrying the
/// ACTIVE exercise's session gains ([SessionStatsTiles], 2026-10-22), the
/// bullseye opening its goals (2026-10-26). Every door opens at any count,
/// like the PR Lab's own bar — a `0` gain still hides an exercise's history
/// behind the trophy and its cues behind the book, so neither goes dead
/// (2026-10-23). The trophy opens that exercise's PR History sheet, the book
/// its lessons modal — scoped to the exercise on the card and the session on
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

  void _openLessons(BuildContext context, String exerciseId) {
    showLessonsModal(
      context,
      listenable: vm,
      lessonsFor: vm.lessonsFor,
      loadLessonsFor: vm.loadLessonsFor,
      addLesson: vm.addLesson,
      toggleLessonPin: vm.toggleLessonPin,
      deleteLesson: vm.deleteLesson,
      updateLesson: vm.updateLessonText,
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
        // The tiles speak for the exercise on screen: its own session gains,
        // and its own doors. The lab's rule, so the number over a tile always
        // names the feed behind it (2026-10-22).
        final exerciseId = vm.activeSlot?.activeExerciseId;
        final prs = exerciseId == null ? 0 : vm.sessionPrCountFor(exerciseId);
        final lessons = exerciseId == null
            ? 0
            : vm.lessonsThisSession(exerciseId).length;
        return SessionStatsTiles(
          prCount: prs,
          lessonCount: lessons,
          // Doors at any count: the sheets hold the exercise's whole story,
          // not only this session's additions (2026-10-23).
          onPrTap: exerciseId == null
              ? null
              : () => _openPrHistory(context, exerciseId),
          onLessonTap: exerciseId == null
              ? null
              : () => _openLessons(context, exerciseId),
          onGoalTap: exerciseId == null
              ? null
              : () => _openGoals(context, exerciseId),
        );
      },
    );
  }
}

/// The bar's doors, drawn (2026-10-22): the trophy's session gain and the
/// note's, each a glass tile the height of the undo/redo boxes beside them,
/// with the bullseye between them when the surface has goals to open
/// (2026-10-26). Presentational only — the live bar binds a VM, the
/// past-session viewer binds its own state, and both draw the same tiles.
///
/// The count is a gain: "+2", or "0" when the session added none (a "+0"
/// would claim a change there wasn't). The count never decides whether the
/// tile is a door: both session surfaces always hand it a tap — the PR Lab's
/// bar does, and the sheets behind them hold more than this session's gains
/// (2026-10-23). A null callback remains the no-exercise fallback: quiet
/// surface fill, hairline, primary ink, no tap. The whole tile is one
/// semantics node, so the number never arrives without its meaning.
///
/// The bullseye is drawn only when there is a door behind it ([onGoalTap]):
/// the planner has no goals to open and passes none, and a fourth control on
/// that floor would be a square that goes nowhere.
///
/// A plan has no session to have gained anything in, so the planner asks for
/// the same tiles with [gain] false (2026-10-26): the counts are the whole
/// shelves behind them — every PR the exercise ever landed, every note it
/// carries — drawn plain ("12", never "+12"), because the number over a tile
/// still has to name the feed it opens.
class SessionStatsTiles extends StatelessWidget {
  const SessionStatsTiles({
    super.key,
    required this.prCount,
    required this.lessonCount,
    this.onPrTap,
    this.onLessonTap,
    this.onGoalTap,
    this.gain = true,
  });

  final int prCount;
  final int lessonCount;
  final VoidCallback? onPrTap;
  final VoidCallback? onLessonTap;

  /// The exercise's goals — the bullseye drawn beside the PRs tile when this
  /// is set (2026-10-26).
  final VoidCallback? onGoalTap;

  /// Whether the counts are one session's gain (the two session surfaces) or
  /// the whole feed's size (the planner). See the class doc.
  final bool gain;

  /// A gain reads "+2"; a session that added none reads "0".
  String _count(int n) => gain && n > 0 ? '+$n' : '$n';

  /// What the tile says to a screen reader — the same distinction as the
  /// drawn count: a gain belongs to this session, a plan's total does not.
  String _semantics(int n, String noun) =>
      gain ? '$n $noun this session' : '$n $noun';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tile(
            key: const ValueKey('session-prs-tile'),
            icon: Icons.emoji_events,
            value: _count(prCount),
            semanticsLabel: _semantics(prCount, 'PRs'),
            onTap: onPrTap,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // The goals door beside the PRs tile (2026-10-26): a set that met a
        // target is said in green everywhere, so the door wears the success
        // glass the G badge wears.
        if (onGoalTap != null) ...[
          BarIconButton(
            key: const ValueKey('session-goals-button'),
            icon: Icons.track_changes,
            semanticsLabel: 'Exercise goals',
            color: AppColors.success,
            onPressed: onGoalTap!,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: _tile(
            key: const ValueKey('session-lessons-tile'),
            icon: Icons.sticky_note_2_outlined,
            value: _count(lessonCount),
            semanticsLabel: _semantics(lessonCount, 'exercise notes'),
            onTap: onLessonTap,
          ),
        ),
      ],
    );
  }

  /// The PR Lab's tile recipe (2026-10-22): [kSessionBarControlSize] tall so
  /// the tiles stand level with the undo/redo boxes and the pencil beside
  /// them, a 24px glyph and a mono 17 count — the doors read at the bar's
  /// scale rather than as a smaller species of control. `FittedBox` narrows
  /// the line rather than overflowing it on a small stage.
  Widget _tile({
    Key? key,
    required IconData icon,
    required String value,
    required String semanticsLabel,
    required VoidCallback? onTap,
  }) {
    final highlighted = onTap != null;
    final color = highlighted ? AppColors.accent : AppColors.primary;
    return Semantics(
      button: true,
      label: semanticsLabel,
      // The reading is the whole tile; the glyph and bare number must not
      // announce themselves separately.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: key,
          height: kSessionBarControlSize,
          // 8, not the old 12: the pencil shares this row, and the two tiles
          // each lost a third of their width to it (2026-10-22).
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: highlighted
              ? glassBox(AppColors.accent)
              : BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24, color: color),
                  const SizedBox(width: 8),
                  Text(
                    value,
                    style: AppFonts.mono(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
