// LAB COPY — the /dev/pr-lab layout sandbox's own copy of a shared
// widget. Never import this from a production screen. Edit freely: nothing
// here can reach the real session, planner, logs or PR History demo
// (2026-10-21).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/container_styles.dart';
import 'pr_lab_exercise_selector.dart';
import 'pr_lab_set_row.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/lambda_readout.dart';

/// Minimal, VM-free pinned-lesson data for the card's lesson bar.
class PrLabPinnedLessonData {
  const PrLabPinnedLessonData({required this.text, required this.date});

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
class PrLabExerciseCard extends StatefulWidget {
  const PrLabExerciseCard({
    super.key,
    // ── Exercise selector ──
    required this.exerciseNames,
    required this.activeIndex,
    required this.onSelect,
    this.exerciseMarks = const [],
    this.deletedExercises = const [],
    this.onMove,
    this.onAdd,
    // ── Pinned lesson (sits between the selector and the pills) ──
    this.pinnedLesson,
    this.onPinnedLessonTap,
    // ── Review note — the open review's note for the ACTIVE exercise ──
    this.reviewNote,
    this.onReviewNoteChanged,
    this.reviewNoteLabel = kReviewNoteLabel,
    this.reviewNoteEmptyText,
    // ── Card chrome ──
    this.planned = false,
    this.deleted = false,
    // ── Sets grid ──
    required this.rows,
    this.onAddSet,
    this.reserveAddSet = false,
    this.onReorderSets,
  });

  /// Display names, in slot order.
  final List<String> exerciseNames;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// One mark per name, parallel to [exerciseNames] — a review's green plus or
  /// red minus where its two sides disagree about an exercise, or the live
  /// session's plan-diff (see [PrLabExerciseMark]). Empty everywhere else.
  final List<PrLabExerciseMark?> exerciseMarks;

  /// One flag per name, parallel to [exerciseNames]: the past-session
  /// viewer's deleted exercises, drawn red (2026-10-14). Empty everywhere
  /// else.
  final List<bool> deletedExercises;

  /// Reorder: null greys the popover's arrows.
  final void Function(int index, int direction)? onMove;

  /// Null greys the popover's Add Exercise row.
  final VoidCallback? onAdd;

  final PrLabPinnedLessonData? pinnedLesson;

  /// Null renders the lesson bar inert (no tap).
  final VoidCallback? onPinnedLessonTap;

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
  /// parentSessionId). The card is otherwise flat — this and [deleted] are
  /// the only two facts that draw a rim (2026-10-22).
  final bool planned;

  /// Deleted outline on the outer card — the same recipe as [planned] in
  /// [AppColors.danger], worn while the card reads a deleted exercise
  /// (2026-10-14). Outranks [planned].
  ///
  /// A past session draws neither: history is the Training view read-only,
  /// not a third card style (2026-10-22). The date bar under the card names
  /// the state ("- PREVIOUSLY"); the rows the caller passes are already
  /// read-only and the add row is simply not offered.
  final bool deleted;

  /// The screen-built list of [PrLabSetRow]s (keys live inside).
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
  /// (see [PrLabSetRow.dragIndex]), and this is called with the move once a
  /// row is dropped onto a new slot. Null leaves the rows a plain column, the
  /// way every read-only surface draws them.
  ///
  /// Draft rows sit at the end of [rows] and are never draggable, so the
  /// caller has to clamp [newIndex] into its real-row range.
  final void Function(int oldIndex, int newIndex)? onReorderSets;

  @override
  State<PrLabExerciseCard> createState() => _PrLabExerciseCardState();
}

class _PrLabExerciseCardState extends State<PrLabExerciseCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pr-lab-exercise-card'),
      // A flat card: the page ground shows straight through, so the selector
      // and the set rows stand at their own width instead of inside a box
      // drawn around them (2026-10-22). Only the two facts that must be read
      // off the furniture draw a rim — planned (blue) and deleted (red).
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: widget.deleted
            ? Border.all(color: AppColors.danger.withValues(alpha: 0.35))
            : widget.planned
            ? Border.all(color: AppColors.planned.withValues(alpha: 0.35))
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      // The card's one inset. The page already contributes its gutter, so
      // this 6 puts every child's edge — the selector's arrows, the set
      // rows, the add row — on the same 22pt line as the date bar's arrows
      // below it, and no inner box adds another.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrLabExerciseSelector(
              exercises: widget.exerciseNames,
              activeIndex: widget.activeIndex,
              onSelect: widget.onSelect,
              onMove: widget.onMove,
              onAdd: widget.onAdd,
              marks: widget.exerciseMarks,
              deleted: widget.deletedExercises,
            ),
            // The pinned lesson sits right under the exercise — stays
            // visible while viewing history too.
            if (widget.pinnedLesson != null) ...[
              const SizedBox(height: 6),
              _pinnedLessonBar(widget.pinnedLesson!),
            ],
            // The selector breathes: 16, not 12 — the top of the card read
            // crowded with the column labels starting a hair under the field
            // (2026-10-22).
            const SizedBox(height: AppSpacing.lg),
            _setsGrid(),
            const SizedBox(height: AppSpacing.md),
            // The review's note on this exercise — a FOOTER, not a header.
            // The slot under the selector belongs to the pinned lesson (how
            // to do the lift); a note about how it went is about the work,
            // and reads after the sets it is about.
            if (_showsReviewNote) ...[
              _reviewNoteBox(),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }

  /// The pinned lesson bar, right under the exercise. On the flat card its
  /// `bg` fill is the page itself, so the bar reads as the hairline alone —
  /// the chip that says "this line is the lesson", not a second ground
  /// under the selector (2026-10-22).
  Widget _pinnedLessonBar(PrLabPinnedLessonData lesson) {
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: lambdaBox(ContainerTone.bg, radius: AppRadius.md),
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

  /// The KG/REPS/VARIATION column labels shared by the sets grid and the
  /// history viewer — the history rows are [PrLabSetRow]s too, so the
  /// columns must line up exactly. The widths are the row's own constants,
  /// so the labels sit over their cells by construction: KG and REPS fixed,
  /// VARIATION taking the rest (2026-10-22). The note button carries no
  /// header — the sticky-note icon is self-explanatory.
  Widget _gridHeaders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        // The labels' own left edge — 8 in from the card's 22pt gutter, so
        // they sit over the rows' number cells (2026-10-22).
        key: const ValueKey('pr-lab-grid-headers'),
        children: [
          const SizedBox(width: kPrLabNumberCellWidth),
          const SizedBox(width: kPrLabCellGap),
          SizedBox(
            width: kPrLabNumCellWidth,
            child: _colLabel('KG'),
          ),
          const SizedBox(width: kPrLabCellGap),
          SizedBox(
            width: kPrLabNumCellWidth,
            child: _colLabel('REPS'),
          ),
          const SizedBox(width: kPrLabCellGap),
          Expanded(child: _colLabel('VARIATION')),
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
