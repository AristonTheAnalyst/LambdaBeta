import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/program_content.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/exercise_selector.dart';
import '../../../shared/widgets/lambda_readout.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import 'review_container.dart';

/// One workout of a completed review, read the way the pass read it: the same
/// header, the same exercise card, the review's own bar at the floor — with
/// every verb that writes locked.
///
/// The eye flips this workout between the two states the review left behind,
/// both frozen when the pass closed and never the live plan (which keeps being
/// edited and would otherwise rewrite history under the reader):
///
/// - **before** — the workout as the review found it, `baseline_content`,
///   captured when the pass began;
/// - **after** — the workout as the review completed it, `snapshot_content`.
///
/// Nothing else moves between the sides but the values and the marks the eye
/// puts on the names: the review's notes are the review's, about the exercise,
/// and read the same over either state.
///
/// Read only, and structurally so: the tick is drawn wearing the answer the
/// record carries and disabled, the note glyph is greyed, every callback the
/// shared card and row take is either null (the control greys or is not drawn)
/// or inert. Switching exercises stays — looking is not writing.
///
/// The screen takes plain data and loads nothing: the caller is the review
/// route, which already holds the repository seams and the user, and reads the
/// row once before pushing. That also keeps the loading and no-record states in
/// one place — a record whose review left no snapshot (a dismissed completion,
/// a row written before snapshots existed) arrives here as a null [after] and
/// says so rather than drawing an empty grid that would read as "no sets".
class RecordWorkoutScreen extends StatefulWidget {
  const RecordWorkoutScreen({
    super.key,
    required this.session,
    required this.name,
    required this.before,
    required this.after,
    this.beforeDate,
    this.afterDate,
    this.exerciseNotes = const {},
    this.workoutNote,
    this.exerciseNames = const {},
    this.variationNames = const {},
  });

  /// The pass this record belongs to, as the bar reads it: the ticks are the
  /// ones the review recorded, and this workout is open under it. Handed in
  /// rather than published — a record is not a pass being taken, and the scope
  /// stays clear for one.
  final ReviewSession session;

  /// The workout's display name — read live, like every name in the app, so a
  /// rename shows through even on a record.
  final String name;

  /// The workout as the review found it, or null when no baseline was
  /// captured (a row written before baselines existed). Null means there is
  /// nothing to flip to, and the bar offers no eye.
  final ContentSession? before;

  /// The workout as the review completed it, or null when the review kept no
  /// record of it at all.
  final ContentSession? after;

  /// When the pass began — the "before" side's own date. Null on a row that
  /// somehow has none; the side is still named.
  final DateTime? beforeDate;

  /// When the review completed — the "after" side's own date.
  final DateTime? afterDate;

  /// The review's exercise notes, keyed by `planned_exercise_id`.
  final Map<String, String> exerciseNotes;

  /// The review's note for this workout as a whole, when it left one.
  final String? workoutNote;

  /// Exercise names, live from the library (`exercise_id` → name).
  final Map<String, String> exerciseNames;

  /// Variation names, live from the library (`variation_id` → name).
  final Map<String, String> variationNames;

  @override
  State<RecordWorkoutScreen> createState() => _RecordWorkoutScreenState();
}

class _RecordWorkoutScreenState extends State<RecordWorkoutScreen> {
  /// The exercise on screen. Switching is looking, and stays. The index is
  /// kept across a flip: the sides hold the same exercises in the same order
  /// (one is the other, edited), and where they don't it clamps to the last
  /// one rather than landing nowhere.
  int _active = 0;

  /// Which side of the record is on screen. False — the workout as the review
  /// completed it — is where this screen opens: it is the record's own state,
  /// and "before" is the one being asked for.
  bool _showingBefore = false;

  /// Whether there is a second side to flip to. Both sides, or the eye is not
  /// offered: a flip into nothing would read as data that went missing.
  bool get _canFlip => widget.before != null && widget.after != null;

  /// The side on screen.
  ContentSession? get _shown => _showingBefore ? widget.before : widget.after;

  /// The two sides, gathered into the comparison the bar's Compare and
  /// Changes both read.
  ///
  /// The pass's loaders go to the stores — a predecessor's snapshot, or the
  /// plan as it stands. On a record there is nowhere to go: both documents
  /// came off the row, frozen, which is the whole of what this screen shows.
  /// Everything downstream is the pass's own machinery, fed the record.
  ReviewComparison get _comparison => ReviewComparison(
    before: widget.before == null
        ? null
        : ProgramContent(sessions: [widget.before!]),
    after: ProgramContent(sessions: [widget.after!]),
    exerciseNames: widget.exerciseNames,
    variationNames: widget.variationNames,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: reviewChrome(
        context,
        session: widget.session,
        readOnly: true,
        // Nothing underneath to settle: the record is not an editor, and no
        // page here holds a value that could be lost.
        settle: null,
        // The eye, where there is a second side to show. It takes the same
        // comparison the pass's Compare would have loaded — here already in
        // hand — so both verbs answer off one pair of documents.
        settleForCompare: _canFlip ? () async => true : null,
        comparing: _showingBefore,
        onComparison: _canFlip
            ? (comparison) =>
                  setState(() => _showingBefore = comparison != null)
            : null,
        loadComparison: () async => _comparison,
        // A card in the changes sheet names an exercise this page is holding:
        // tapping it lands on that exercise, the same promise the pass's bar
        // makes.
        onExerciseTap: _openExercise,
        child: Column(
          children: [
            PageHeader(
              title: widget.name,
              left: IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.primary),
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  void _openExercise(String plannedExerciseId) {
    final shown = _shown;
    if (shown == null) return;
    final index = shown.exercises.indexWhere(
      (e) => e.plannedExerciseId == plannedExerciseId,
    );
    if (index >= 0) setState(() => _active = index);
  }

  Widget _body() {
    if (widget.after == null) {
      return _empty('This review kept no record of this workout.');
    }
    final shown = _shown;
    if (shown == null || shown.exercises.isEmpty) {
      return _empty(
        _showingBefore
            // The review found the workout empty and may well have filled it:
            // its own record of that is the other side.
            ? 'The workout held no exercises when this review began.'
            : 'This review recorded no exercises for this workout.',
      );
    }
    final exercises = [...shown.exercises]
      ..sort((a, b) => a.exerciseOrder.compareTo(b.exerciseOrder));
    final active = _active.clamp(0, exercises.length - 1);
    final workoutNote = widget.workoutNote?.trim() ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        // Which side this is, named on the page: the bar names it too, in
        // fewer words (kReviewAfterLabel / kReviewBeforeLabel), so the words
        // read a second before the date does — and here there is room for the
        // date as well.
        Text(
          _caption(),
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // What was said about the workout as a whole, above the exercises it
        // is about — the same note the pass took through the bar's Note verb.
        // The review's, so it reads over either side: the note is about the
        // exercise, not about the state it was in when it was written.
        if (workoutNote.isNotEmpty) ...[
          LambdaReadout(label: 'Review note', value: workoutNote),
          const SizedBox(height: AppSpacing.md),
        ],
        _card(exercises, active),
      ],
    );
  }

  /// The side's name and date — `AFTER · 9 Oct 2026`. The date is the side's
  /// own moment: the pass began for "before", the review completed for
  /// "after". A row with no date still names its side.
  String _caption() {
    final side = _showingBefore ? 'BEFORE' : 'AFTER';
    final date = _showingBefore ? widget.beforeDate : widget.afterDate;
    if (date == null) return side;
    return '$side · ${DateFormat('d MMM yyyy').format(date)}';
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted),
      ),
    ),
  );

  /// The mark one exercise of the side on screen wears, read off the OTHER
  /// side: on the record's own side (after) an exercise the baseline did not
  /// hold is one the review ADDED — green plus; on the baseline (before) one
  /// the record does not hold is one it REMOVED — red minus.
  ///
  /// One membership test with two readings, so the marks can never disagree
  /// across the eye: the same exercise wears the plus from one side and the
  /// minus from the other, and an exercise both sides hold stays bare. No
  /// second side at all (a row written before baselines existed, so there is
  /// no eye) means nothing to read against, and every name stays bare.
  ExerciseMark? _mark(ContentExercise exercise) {
    final other = _showingBefore ? widget.after : widget.before;
    if (other == null) return null;
    final known = other.exercises.any(
      (e) => e.plannedExerciseId == exercise.plannedExerciseId,
    );
    if (known) return null;
    return _showingBefore ? ExerciseMark.removed : ExerciseMark.added;
  }

  /// The one exercise card, drawn through the shared card like every other
  /// workout surface — a second layout here would be a second thing to keep in
  /// step with the other three.
  Widget _card(List<ContentExercise> exercises, int active) {
    final exercise = exercises[active];
    final sets = [...exercise.sets]
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    final notes = widget.exerciseNotes;

    return SessionExerciseCard(
      exerciseNames: [
        for (final e in exercises)
          toProperCase(
            widget.exerciseNames[e.exerciseId] ?? e.exerciseId ?? '',
          ),
      ],
      // What the two sides disagree about, on the name it is about: the eye
      // flips the values AND the marks, because the marks are the sides'
      // difference read from whichever one is on screen.
      exerciseMarks: [for (final e in exercises) _mark(e)],
      activeIndex: active,
      onSelect: (i) => setState(() => _active = i),
      // Reordering and adding are writing; the record is neither. Reorder
      // greys the popover's arrows, add greys its row.
      onMove: null,
      onAdd: null,
      // Lessons and PRs read live history, which is not what this screen is:
      // the record is the workout as it stood, and both pills rest greyed the
      // way the planner's do.
      lessonsCount: 0,
      onLessonsTap: null,
      prCount: 0,
      onPrTap: null,
      rows: [
        for (var i = 0; i < sets.length; i++) _recordRow(exercise, sets[i], i),
      ],
      // Nothing to add to on a record, and no height to hold for a flip:
      // the button is simply not drawn.
      onAddSet: null,
      onReorderSets: null,
      history: null,
      // The review's note for this exercise, read as plain text — no change
      // callback, so the box is a [LambdaReadout]. It holds its place either
      // way (2026-10-12): the pass draws this box under every exercise, and a
      // record wearing the pass's UI draws it too, answering the emptiness
      // inside the box rather than by dropping it.
      reviewNote: notes[exercise.plannedExerciseId],
      reviewNoteEmptyText: kNoNoteText,
      onReviewNoteChanged: null,
    );
  }

  /// One recorded set. The variation lists are the library's, built from the
  /// resolved names: a read-only row never opens the picker, but it does read
  /// its own label off them, and a record naming a variation is exactly what
  /// they are for.
  Widget _recordRow(ContentExercise exercise, ContentSet set, int index) =>
      recordSetRow(
        set: set,
        index: index,
        exerciseId: exercise.exerciseId ?? '',
        variationNames: widget.variationNames,
        variationOptions: [
          const DropdownOption<String?>(label: 'No Variation', value: null),
          for (final entry in widget.variationNames.entries)
            DropdownOption<String?>(label: entry.value, value: entry.key),
        ],
        allVariations: [
          for (final entry in widget.variationNames.entries)
            (id: entry.key, name: entry.value),
        ],
      );
}
