import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import './container_styles.dart';
import '../../data/models/session_exercise_set.dart';
import '../../features/session/model/session_local_state.dart';
import 'card_pill_button.dart';
import 'exercise_selector.dart';

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
    this.onDeleteRequest,
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
  });

  /// Display names, in slot order.
  final List<String> exerciseNames;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// Reorder: null greys the popover's arrows.
  final void Function(int index, int direction)? onMove;

  /// Null greys the popover's Add Exercise row.
  final VoidCallback? onAdd;

  /// Null hides the hold-to-delete X.
  final VoidCallback? onDeleteRequest;

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

  @override
  State<SessionExerciseCard> createState() => _SessionExerciseCardState();
}

class _SessionExerciseCardState extends State<SessionExerciseCard> {
  bool _historyOpen = false;
  ExerciseHistorySession? _viewingSession;

  void _exitHistory() => setState(() {
    _historyOpen = false;
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
                    onDeleteRequest: widget.onDeleteRequest,
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
                          active: _historyOpen || viewingHistory,
                          enabled: widget.history != null &&
                              widget.history!.isNotEmpty,
                          onTap: widget.history == null ||
                                  widget.history!.isEmpty
                              ? null
                              : () {
                                  if (viewingHistory) {
                                    _exitHistory();
                                  } else {
                                    setState(
                                      () => _historyOpen = !_historyOpen,
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
                // The picker stays visible while viewing a session — the
                // user can hop between past sessions without going back.
                if (_historyOpen || viewingHistory)
                  _historyPicker(widget.history ?? const []),
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
              fontSize: 9,
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
              style: AppFonts.ui(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Text(
            DateFormat('MMM d').format(lesson.date),
            style: AppFonts.mono(fontSize: 9, color: AppColors.muted),
          ),
        ],
      ),
    );
    final onTap = widget.onPinnedLessonTap;
    if (onTap == null) return bar;
    return GestureDetector(onTap: onTap, child: bar);
  }

  Widget _historyPicker(List<ExerciseHistorySession> history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          Text(
            'PAST SESSIONS',
            style: AppFonts.mono(
              fontSize: 8,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final session = history[i];
                // The viewed chip gets the neutral glass highlight — the
                // same translucent tint + hairline as the active exercise
                // pill (a light lift, not the accent's colored fill).
                final selected = identical(session, _viewingSession);
                return GestureDetector(
                  onTap: () => setState(() {
                    _viewingSession = session;
                    _historyOpen = false;
                    widget.onHistorySessionSelected?.call(session);
                  }),
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.all(10),
                    decoration: glassBox(AppColors.primary),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMM d').format(session.date),
                          style: AppFonts.mono(
                            fontSize: 10,
                            color: selected
                                ? AppColors.primary
                                : AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${session.sets.length} sets',
                          style: AppFonts.mono(
                            fontSize: 10,
                            color: selected
                                ? AppColors.primary
                                : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
                    fontSize: 11,
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

  /// The REPS/KG/VARIATION/NOTE column labels shared by the sets grid and
  /// the history viewer — the history rows are [SessionSetRow]s too, so the
  /// columns must line up exactly.
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
          const SizedBox(width: 6),
          SizedBox(width: 32, child: _colLabel('NOTE')),
        ],
      ),
    );
  }

  Widget _colLabel(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppFonts.mono(
      fontSize: 8,
      letterSpacing: 0.6,
      color: AppColors.muted,
    ),
  );
}
