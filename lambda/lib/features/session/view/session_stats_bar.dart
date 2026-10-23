import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/container_styles.dart';
import '../viewmodel/session_viewmodel.dart';
import 'lessons_modal.dart';
import 'pr_history_sheet.dart';

/// The active workout's summary doors, in the Training page's sticky bottom
/// bar: a trophy and a book, each carrying the ACTIVE exercise's session
/// gains ([SessionStatsTiles], 2026-10-22). Both tiles are doors, like the PR
/// Lab's own bar — a `0` gain still hides an exercise's history behind the
/// trophy and its cues behind the book, so neither goes dead (2026-10-23).
/// The trophy opens that exercise's PR History sheet, the book its lessons
/// modal — scoped to the exercise on the card and the session on the desk.
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
        );
      },
    );
  }
}

/// The bar's two doors, drawn (2026-10-22): the trophy's session gain and the
/// note's, each a glass tile the height of the undo/redo boxes beside them.
/// Presentational only — the live bar binds a VM, the past-session viewer
/// binds its own state, and both draw the same tiles.
///
/// The count is a gain: "+2", or "0" when the session added none (a "+0"
/// would claim a change there wasn't). The count never decides whether the
/// tile is a door: both session surfaces always hand it a tap — the PR Lab's
/// bar does, and the sheets behind them hold more than this session's gains
/// (2026-10-23). A null callback remains the no-exercise fallback: quiet
/// surface fill, hairline, primary ink, no tap. The whole tile is one
/// semantics node, so the number never arrives without its meaning.
class SessionStatsTiles extends StatelessWidget {
  const SessionStatsTiles({
    super.key,
    required this.prCount,
    required this.lessonCount,
    this.onPrTap,
    this.onLessonTap,
  });

  final int prCount;
  final int lessonCount;
  final VoidCallback? onPrTap;
  final VoidCallback? onLessonTap;

  /// A gain reads "+2"; a session that added none reads "0".
  static String _gain(int n) => n > 0 ? '+$n' : '0';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tile(
            key: const ValueKey('session-prs-tile'),
            icon: Icons.emoji_events,
            value: _gain(prCount),
            semanticsLabel: '$prCount PRs this session',
            onTap: onPrTap,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _tile(
            key: const ValueKey('session-lessons-tile'),
            icon: Icons.sticky_note_2_outlined,
            value: _gain(lessonCount),
            semanticsLabel: '$lessonCount exercise notes this session',
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
