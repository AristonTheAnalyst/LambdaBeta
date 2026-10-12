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
import 'lambda_input.dart';
import 'lambda_readout.dart';
import 'slide_up_modal.dart';

/// Minimal, VM-free pinned-lesson data for the card's lesson bar.
class PinnedLessonData {
  const PinnedLessonData({required this.text, required this.date});

  final String text;
  final DateTime date;
}

/// The review-note box's label inside a pass — the box IS the note, and the
/// header names it.
const String kReviewNoteLabel = 'Exercise Review Note';

/// The same box while the record is up: the note shown is the record's, not
/// the pass's, and the label has to say so — a note read under the pass's own
/// header would be taken for the one being written.
const String kPreviousReviewNoteLabel = 'Exercise Review Note (Previous)';

/// What the record's box reads when its review left no note for the exercise.
/// The box still holds its place — Compare flips values, never furniture, and
/// dropping a row under the eye that just tapped it would move the card — so
/// the absence is answered inside the box instead of by an empty rectangle.
const String kNoPreviousNoteText = 'No previous notes';

/// What a record's own note box reads when the review left the exercise no
/// note — [kNoPreviousNoteText]'s twin on the record's side of the eye, and
/// there for the same reason. The record asks for the pass's own UI, and the
/// pass draws this box under every exercise whether or not it holds anything;
/// a box that comes and goes with the note would make the card's furniture
/// depend on what was typed into it.
const String kNoNoteText = 'No note';

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
    this.exerciseMarks = const [],
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
    // ── Review note — the open review's note for the ACTIVE exercise ──
    this.reviewNote,
    this.onReviewNoteChanged,
    this.reviewNoteLabel = kReviewNoteLabel,
    this.reviewNoteEmptyText,
    // ── Card chrome ──
    this.planned = false,
    // ── Sets grid ──
    required this.rows,
    this.onAddSet,
    this.reserveAddSet = false,
    this.onReorderSets,
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

  /// One mark per name, parallel to [exerciseNames] — a review's green plus or
  /// red minus where its two sides disagree about an exercise (see
  /// [ExerciseMark]). Empty everywhere else.
  final List<ExerciseMark?> exerciseMarks;

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

  /// The review's note for the exercise on screen, when there is one.
  ///
  /// Shown as a footer box under the sets, never in the pinned lesson's slot:
  /// a note exists to be re-read WHILE the pass is being made, so hiding it
  /// behind a tap would defeat it, but a lesson says how to do the lift and a
  /// review note says how it went — two different things, two places. On the
  /// completed record [onReviewNoteChanged] is null and the box renders the
  /// note as plain text — and only when there is one, unless
  /// [reviewNoteEmptyText] keeps an empty record's box in place.
  final String? reviewNote;

  /// Writes the note as it is typed. Null renders the box read-only (the
  /// record) and hides it entirely when there is no note either — the rule
  /// every other review affordance follows: the control exists only where
  /// there is a review row to write to. Non-null, the box shows even with no
  /// note yet, because an empty box is the way in: it says a note goes here,
  /// and there is nothing to open to write one.
  final ValueChanged<String>? onReviewNoteChanged;

  /// What the note box's header says. [kReviewNoteLabel] while the pass is
  /// being made — the box is the pass's own note — and
  /// [kPreviousReviewNoteLabel] while the record is up, where the note read
  /// is the record's.
  final String reviewNoteLabel;

  /// What the read-only box says when there is no note to read. Null keeps
  /// the record's own rule — an empty box is not drawn, because it would
  /// only take up the space a note did not earn. Set ([kNoPreviousNoteText],
  /// while Compare is up), the box holds its place either way, reading this
  /// where the note would be: the flip must not drop a row the eye just
  /// landed on, and "the record said nothing" is itself the answer. Ignored
  /// by the editable box, which is already shown empty as the way in.
  final String? reviewNoteEmptyText;

  /// Planned outline on the outer card (live slot.planned / logs
  /// parentSessionId).
  final bool planned;

  /// The screen-built list of [SessionSetRow]s (keys live inside).
  final List<Widget> rows;

  /// Null hides the "+ ADD SET" button (logs view mode).
  final VoidCallback? onAddSet;

  /// Draws the "+ ADD SET" row even when [onAddSet] is null — present but
  /// greyed and dead. The compare view renders a workout through this same
  /// card with the record's rows in place of the plan's, and the grid must be
  /// exactly as tall either way; there is nothing on a record to add to, so
  /// the row holds the height without holding a press.
  final bool reserveAddSet;

  /// Makes the set grid reorderable — the rows' number cells are the handles
  /// (see [SessionSetRow.dragIndex]), and this is called with the move once a
  /// row is dropped onto a new slot. Null leaves the rows a plain column, the
  /// way every read-only surface draws them.
  ///
  /// Draft rows sit at the end of [rows] and are never draggable, so the
  /// caller has to clamp [newIndex] into its real-row range.
  final void Function(int oldIndex, int newIndex)? onReorderSets;

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
                    marks: widget.exerciseMarks,
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
          // The gap below tightens when the review note's footer follows, so
          // the card keeps one rhythm of 12 either way.
          Container(
            margin: EdgeInsets.fromLTRB(10, 6, 10, _showsReviewNote ? 6 : 12),
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
          // The review's note on this exercise — a FOOTER, not a header. The
          // slot under the selector belongs to the pinned lesson (how to do
          // the lift); a note about how it went is about the work, and reads
          // after the sets it is about.
          if (_showsReviewNote)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 12),
              child: _reviewNoteBox(),
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

  /// The review's note for this exercise.
  ///
  /// Inside a review the box shows even when empty — it is the way in, and a
  /// reviewer looking at an exercise with nothing said about it yet is exactly
  /// who needs it; an empty text box says a note goes here, so there is
  /// nothing to open. On the record (no change callback) an empty box would
  /// only take up the space a note did not earn, so it is not drawn at all —
  /// unless the caller says what the emptiness reads as
  /// ([reviewNoteEmptyText]): while Compare is up the box stays put and
  /// answers "No previous notes" in place of the note.
  bool get _showsReviewNote =>
      widget.onReviewNoteChanged != null ||
      (widget.reviewNote?.trim().isNotEmpty ?? false) ||
      widget.reviewNoteEmptyText != null;

  /// The review's note for this exercise — a text box, not a door.
  ///
  /// The header names it and the box IS the note, so there is nothing to
  /// open: inside a review it is [LambdaInput] — the app's one editable box —
  /// and on the record it is [LambdaReadout] — the past-session viewer's
  /// read-only box. The two states differ in chrome, never in where the header
  /// sits or how the note reads back.
  Widget _reviewNoteBox() {
    final onChanged = widget.onReviewNoteChanged;
    if (onChanged != null) {
      return _ReviewNoteField(
        value: widget.reviewNote ?? '',
        label: widget.reviewNoteLabel,
        onChanged: onChanged,
      );
    }
    return LambdaReadout(
      label: widget.reviewNoteLabel,
      value: widget.reviewNote?.trim() ?? '',
      placeholder: widget.reviewNoteEmptyText,
    );
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
        if (widget.onReorderSets == null)
          ...widget.rows
        else
          // Held sets only. The house pattern for a short list inside a
          // page-level scroll view: it shrink-wraps and never scrolls itself,
          // so the one scrollable under the finger stays the page.
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // `onReorderItem`, not the deprecated `onReorder`: its newIndex
            // already accounts for the row being lifted out, so a move is a
            // plain removeAt/insert and no `- 1`.
            onReorderItem: widget.onReorderSets!,
            proxyDecorator: _liftedSet,
            children: widget.rows,
          ),
        if (widget.onAddSet != null || widget.reserveAddSet) ...[
          const SizedBox(height: 2),
          // A dead row says so the way every other dead control on this card
          // does — greyed, and with no tap to answer one.
          Opacity(
            opacity: widget.onAddSet == null ? 0.5 : 1,
            child: GestureDetector(
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
          ),
        ],
      ],
    );
  }

  /// The row while it is being dragged.
  ///
  /// The proxy is rendered into the overlay, so it carries its own [Material]
  /// — the same reason the floating bar does: without one, any bare `Text` in
  /// the lifted row picks up MaterialApp's yellow-underlined error style. It
  /// also draws the shadow the default decorator has none of, which is what
  /// says the row has left the grid. The fill stays transparent so each row
  /// keeps its own tint (PR accent, planned tint) while it is up.
  ///
  /// The animation runs 0→1 as the row is picked up and back down as it
  /// settles, so the lift ramps in under the finger and out on the way home.
  Widget _liftedSet(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: Material(
            color: Colors.transparent,
            elevation: 8 * t,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: child,
          ),
        );
      },
      child: child,
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

/// The editable half of the note box — [LambdaInput], labelled for the note
/// it holds. The note reads as it was written: no ellipsis, no inner scroll,
/// the field growing with it.
///
/// Stateful for its controller only. The card re-renders with the stored note
/// after every keystroke's write, so an incoming value that did not change
/// (it is the echo of what was just typed) must not re-seat the field and
/// throw the caret to the end; a value that genuinely changed — another
/// exercise's note coming on screen with the tab — is adopted.
class _ReviewNoteField extends StatefulWidget {
  const _ReviewNoteField({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final String value;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  State<_ReviewNoteField> createState() => _ReviewNoteFieldState();
}

class _ReviewNoteFieldState extends State<_ReviewNoteField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.value,
  );
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _ReviewNoteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LambdaInput(
      controller: _ctrl,
      focusNode: _focus,
      label: widget.label,
      placeholder: 'Why you left it alone, or what you changed and why…',
      minLines: 1,
      maxLines: null,
      textCapitalization: TextCapitalization.sentences,
      // No `elevated` step: the session-prep notes box ("Why do you feel
      // that way") is this box's reference and it must match it exactly —
      // base fill + hairline. Asked for by name (2026-10-08): the step-up's
      // surfaceHigh read as a different box from the one being copied.
      onChanged: widget.onChanged,
    );
  }
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
