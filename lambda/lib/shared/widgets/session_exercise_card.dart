import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import './container_styles.dart';
import '../../data/models/session_exercise_set.dart';
import '../../features/session/model/session_local_state.dart';
import 'card_pill_button.dart';
import 'exercise_selector.dart';
import 'slide_up_modal.dart';

/// Minimal, VM-free pinned-lesson data for the card's lesson bar.
class PinnedLessonData {
  const PinnedLessonData({required this.text, required this.date});

  final String text;
  final DateTime date;
}

/// The ONE exercise card for all three workout surfaces — the live session,
/// the session planner, and the past-session viewer. Screens adapt their VM
/// state into plain inputs and nullable callbacks; a null callback renders
/// the corresponding control greyed (or hides it, where noted), so the three
/// screens share one implementation and per-context differences are
/// capability, never styling.
class SessionExerciseCard extends StatefulWidget {
  const SessionExerciseCard({
    super.key,
    // ── Exercise selector ──
    required this.exerciseNames,
    required this.activeIndex,
    required this.onSelect,
    this.onMove,
    this.onAdd,
    // ── Pinned lesson (sits between the selector and the pills) ──
    this.pinnedLesson,
    this.onPinnedLessonTap,
    // ── Pills — a null onTap greys the pill ──
    this.lessonsCount = 0,
    this.onLessonsTap,
    this.prCount = 0,
    this.onPrTap,
    // ── Card chrome ──
    this.planned = false,
    // ── Sets grid ──
    required this.rows,
    this.onAddSet,
    // ── History view — a null list means no history: pill greyed, no
    // picker/banner ──
    this.history,
    this.historyRowBuilder,
    this.onHistorySessionSelected,
    this.isPrSet,
  });

  /// Display names, in slot order.
  final List<String> exerciseNames;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// Reorder: null greys the popover's arrows.
  final void Function(int index, int direction)? onMove;

  /// Null greys the popover's Add Exercise row.
  final VoidCallback? onAdd;

  final PinnedLessonData? pinnedLesson;

  /// Null renders the lesson bar inert (no tap).
  final VoidCallback? onPinnedLessonTap;

  final int lessonsCount;
  final VoidCallback? onLessonsTap;

  final int prCount;

  /// Null greys the PRs pill (the live session's placeholder state).
  final VoidCallback? onPrTap;

  /// Planned outline on the outer card (live slot.planned / logs
  /// parentSessionId).
  final bool planned;

  /// The screen-built list of [SessionSetRow]s (keys live inside).
  final List<Widget> rows;

  /// Null hides the "+ ADD SET" button (logs view mode).
  final VoidCallback? onAddSet;

  final List<ExerciseHistorySession>? history;

  /// Builds one history-detail row for [PastSetRow] (per-screen wiring —
  /// the live screen's edit-gated row vs the logs' read-only row).
  final Widget Function(PastSetRow set)? historyRowBuilder;

  /// Fired when the picker selects a session — the live screen resets its
  /// history-edit confirm gate here.
  final void Function(ExerciseHistorySession session)? onHistorySessionSelected;

  /// PR membership per set id — the picker tiles show each past session's
  /// PR count. Null hides the PR line.
  final bool Function(String setId)? isPrSet;

  @override
  State<SessionExerciseCard> createState() => _SessionExerciseCardState();
}

class _SessionExerciseCardState extends State<SessionExerciseCard> {
  ExerciseHistorySession? _viewingSession;

  void _exitHistory() => setState(() {
    _viewingSession = null;
  });

  @override
  Widget build(BuildContext context) {
    final viewingHistory = _viewingSession != null;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: widget.planned
              ? AppColors.planned.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top card: the exercise selector + pinned lesson + pills, inset
          // with space around it.
          Container(
            margin: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExerciseSelector(
                    exercises: widget.exerciseNames,
                    activeIndex: widget.activeIndex,
                    onSelect: widget.onSelect,
                    onMove: widget.onMove,
                    onAdd: widget.onAdd,
                  ),
                  const SizedBox(height: 6),
                  // The pinned lesson sits right under the exercise, just
                  // before the buttons — stays visible while viewing
                  // history too.
                  if (widget.pinnedLesson != null) ...[
                    _pinnedLessonBar(widget.pinnedLesson!),
                    const SizedBox(height: 6),
                  ],
                  // Lessons / History / PRs row — each button expands to
                  // share the available width. Null callbacks grey them.
                  Row(
                    children: [
                      Expanded(
                        child: CardPillButton(
                          icon: Icons.menu_book_outlined,
                          label: widget.lessonsCount > 0
                              ? '${widget.lessonsCount} Lessons'
                              : 'Lessons',
                          active: widget.lessonsCount > 0,
                          enabled: widget.onLessonsTap != null,
                          onTap: widget.onLessonsTap,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: CardPillButton(
                          icon: Icons.history,
                          label: 'History',
                          active: viewingHistory,
                          enabled: widget.history != null &&
                              widget.history!.isNotEmpty,
                          onTap: widget.history == null ||
                                  widget.history!.isEmpty
                              ? null
                              : () {
                                  if (viewingHistory) {
                                    _exitHistory();
                                  } else {
                                    _openHistorySheet(
                                      widget.history ?? const [],
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 6),
                      // PR = accent everywhere; null onPrTap renders the
                      // greyed placeholder state.
                      Expanded(
                        child: CardPillButton(
                          icon: Icons.emoji_events_outlined,
                          label: widget.prCount > 0
                              ? '${widget.prCount} PRs'
                              : 'PRs',
                          active: widget.prCount > 0,
                          color: AppColors.accent,
                          enabled: widget.onPrTap != null,
                          onTap: widget.onPrTap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Bottom card: the sets grid — a separate card with a gap above it.
          Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            decoration: lambdaBox(ContainerTone.surface, radius: AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  // Top spacing above the column headers (the history picker
                  // sits above when open).
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  child: viewingHistory
                      ? _historyDetail(_viewingSession!)
                      : _setsGrid(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The pinned lesson bar, right under the exercise — recessed (bg fill)
  /// against the header's surfaceHigh container.
  Widget _pinnedLessonBar(PinnedLessonData lesson) {
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: lambdaBox(
        ContainerTone.bg,
        radius: AppRadius.md,
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin, size: 10, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            'LESSON',
            style: AppFonts.mono(
              fontSize: 13,
              letterSpacing: 0.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lesson.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Text(
            DateFormat('MMM d').format(lesson.date),
            style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
    final onTap = widget.onPinnedLessonTap;
    if (onTap == null) return bar;
    return GestureDetector(onTap: onTap, child: bar);
  }

  /// Opens the past-sessions bottom sheet — sessions listed top to bottom,
  /// like the all-sessions sheet on the prep page. Selecting one closes the
  /// sheet and shows that session in the card's history detail.
  void _openHistorySheet(List<ExerciseHistorySession> history) {
    showLambdaModal<void>(
      context,
      fitContent: true,
      backgroundColor: AppColors.bg,
      child: _HistorySheet(
        history: history,
        selected: _viewingSession,
        isPrSet: widget.isPrSet,
        onSelect: (session) {
          setState(() => _viewingSession = session);
          widget.onHistorySessionSelected?.call(session);
        },
      ),
    );
  }

  /// The history viewer is the regular sets grid — the same column headers
  /// and the same [SessionSetRow] chrome — with the screen deciding whether
  /// the rows are read-only (logs) or edit-gated (live).
  Widget _historyDetail(ExerciseHistorySession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _gridHeaders(),
        const SizedBox(height: 6),
        ...session.sets.map(
          (s) => widget.historyRowBuilder?.call(s) ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _setsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _gridHeaders(),
        const SizedBox(height: 6),
        ...widget.rows,
        if (widget.onAddSet != null) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: widget.onAddSet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: glassBox(AppColors.primary),
              child: Center(
                child: Text(
                  '+ ADD SET',
                  style: AppFonts.ui(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The REPS/KG/VARIATION column labels shared by the sets grid and the
  /// history viewer — the history rows are [SessionSetRow]s too, so the
  /// columns must line up exactly. The note button carries no header — the
  /// sticky-note icon is self-explanatory.
  Widget _gridHeaders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const SizedBox(width: 26),
          const SizedBox(width: 6),
          Expanded(child: _colLabel('REPS')),
          const SizedBox(width: 6),
          Expanded(child: _colLabel('KG')),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _colLabel('VARIATION')),
        ],
      ),
    );
  }

  Widget _colLabel(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppFonts.mono(
      fontSize: 14,
      letterSpacing: 0.6,
      color: AppColors.muted,
    ),
  );
}

/// The past-sessions bottom sheet — sessions top to bottom, newest first,
/// in the all-sessions sheet's row style (recessed surface cards). Each row
/// shows the date, its set count, and the session's PR count in accent.
class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.history,
    required this.selected,
    required this.isPrSet,
    required this.onSelect,
  });

  final List<ExerciseHistorySession> history;
  final ExerciseHistorySession? selected;
  final bool Function(String setId)? isPrSet;
  final void Function(ExerciseHistorySession) onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                'PAST SESSIONS',
                style: AppFonts.mono(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: AppColors.muted,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                itemCount: history.length,
                itemBuilder: (context, i) => _row(context, history[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ExerciseHistorySession session) {
    final isSelected = identical(session, selected);
    final prCount = isPrSet == null
        ? 0
        : session.sets
              .where((s) => isPrSet!(s.sessionExerciseSetId))
              .length;
    return GestureDetector(
      onTap: () {
        Navigator.of(context, rootNavigator: true).pop();
        onSelect(session);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          // The all-sessions sheet's row recipe: recessed surface, hairline,
          // soft-highlight border on the viewed session.
          color: AppColors.surfaceLow,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM d, yyyy').format(session.date),
                    style: AppFonts.mono(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${session.sets.length} sets',
                    style: AppFonts.mono(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            // The PR count — the only accent on the right, orange when the
            // session has PR sets.
            Text(
              '$prCount ${prCount == 1 ? 'PR' : 'PRs'}',
              style: AppFonts.mono(
                fontSize: 14,
                fontWeight: prCount > 0 ? FontWeight.w700 : FontWeight.w500,
                color: prCount > 0 ? AppColors.accent : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
