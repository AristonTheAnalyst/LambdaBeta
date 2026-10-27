import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/program_content.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/exercise_selector.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/keyboard_floor_layout.dart';
import '../../../shared/widgets/lambda_readout.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_chevron_button.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/undo_redo_buttons.dart';
import '../../goals/view/exercise_goals_sheet.dart';
import '../../session/view/exercise_notes_modal.dart';
import '../../session/view/pr_history_sheet.dart';
import '../../session/view/session_stats_bar.dart';
import '../viewmodel/record_workout_viewmodel.dart';
import 'review_container.dart';

/// One workout of a completed review, read the way the pass read it: the same
/// header, the same flat exercise card, the same floor — the date bar's
/// furniture, the row of 48pt squares and the three doors — with every verb
/// that writes locked (2026-10-27, matching the open pass's editor).
///
/// A workout's story is every frozen version of it (2026-10-26), walked on
/// the floor's own bar — the session date bar's furniture, its phrase naming
/// the version: the current plan, then each completed review's end
/// (`snapshot_content`, what the pass left) and start (`baseline_content`,
/// what it found). Older is left, newer is right — the session floor's
/// grammar — and a step swaps the page in place, never a route and never a
/// spinner. The opener hands the versions in, already read and already
/// newest-first; the page owns which one is on screen through
/// [RecordWorkoutViewModel].
///
/// The actions row is the planner's, spent where a record cannot act: undo,
/// redo and the trash have no edit behind them, and the star opens session
/// ratings a workout version never had. The doors beside them are live, like
/// the planner's (2026-10-27): the active exercise's PR shelf behind the
/// trophy, its goals behind the bullseye and its exercise notes behind the
/// note glyph — reads over the user's own library, scoped to the exercise on
/// the card. The shelves are read after the page opens
/// ([RecordWorkoutViewModel.loadContext]); until they land the doors are
/// quiet, never absent.
///
/// The eye keeps its old job — the other SIDE of the review on screen — but
/// it is now a jump between two versions of the same stack: pressed on an
/// end it steps to that review's start, pressed again it steps back. It is
/// offered only where both sides hold the workout; a flip onto a page saying
/// "the workout was not there" would read as data gone missing. The current
/// plan belongs to no review, so it has no eye.
///
/// The marks read the pair too: on a review version, an exercise the other
/// side does not hold is what the pass added (green plus, read off the start)
/// or dropped (red minus, read off the end); on the current plan the
/// reference is the newest end, so the marks say what has changed since the
/// last record. The review's notes belong to the versions it produced — only
/// an end carries them — and the workout's note reads above the card as
/// before.
///
/// Read only, and structurally so: the tick is drawn wearing the answer the
/// record carries and disabled, the note glyph is greyed, every callback the
/// shared card and row take is either null (the control greys or is not
/// drawn) or inert. Switching exercises stays — looking is not writing — and
/// so do the floor's doors, which read shelves rather than write the record.
///
/// A review that kept no record of the workout (a dismissed completion, a row
/// written before snapshots existed) resolves to no version at all and the
/// page says so rather than drawing an empty grid that would read as "no
/// sets". A version the review's document does not hold the workout in —
/// added after the baseline was taken, or gone before the snapshot was — is a
/// version whose page says exactly that.
class RecordWorkoutScreen extends StatefulWidget {
  const RecordWorkoutScreen({
    super.key,
    required this.session,
    required this.name,
    this.versions = const [],
    this.initialIndex = 0,
    this.exerciseNames = const {},
    this.variationNames = const {},
    this.userId,
  });

  /// The pass this record belongs to, as the bar reads it: the ticks are the
  /// ones the review recorded, and this workout is open under it. Handed in
  /// rather than published — a record is not a pass being taken, and the scope
  /// stays clear for one.
  final ReviewSession session;

  /// The workout's display name — read live, like every name in the app, so a
  /// rename shows through even on a record.
  final String name;

  /// The workout's versions, newest first, already read — the current plan
  /// first when the workout still exists, then each completed review's end
  /// and start. Empty when this review kept no record of the workout.
  final List<WorkoutVersion> versions;

  /// Which version opens: the review's own end — the workout as this pass
  /// left it. Negative when the review recorded nothing of it, which the page
  /// says instead of drawing a version.
  final int initialIndex;

  /// Exercise names, live from the library (`exercise_id` → name).
  final Map<String, String> exerciseNames;

  /// Variation names, live from the library (`variation_id` → name).
  final Map<String, String> variationNames;

  /// Whose shelves the floor's doors read — the record is the signed-in
  /// user's own, so this is the user the review belongs to. Null (a host test
  /// with no account) leaves the doors quiet.
  final String? userId;

  @override
  State<RecordWorkoutScreen> createState() => _RecordWorkoutScreenState();
}

class _RecordWorkoutScreenState extends State<RecordWorkoutScreen> {
  late final RecordWorkoutViewModel _vm = RecordWorkoutViewModel(
    versions: widget.versions,
    initialIndex: widget.initialIndex,
    userId: widget.userId,
  );

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChanged);
    // The floor's shelves are extras on the record: the page draws from its
    // versions alone the moment it opens, and the doors fill in behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vm.loadContext();
    });
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _vm.value;
    return Scaffold(
      backgroundColor: AppColors.bg,
      // The floor keeps its place under the keyboard, the session surfaces'
      // rule (2026-10-25).
      resizeToAvoidBottomInset: false,
      body: reviewChrome(
        context,
        session: widget.session,
        readOnly: true,
        // Nothing underneath to settle: the record is not an editor, and no
        // page here holds a value that could be lost.
        settle: null,
        // The eye, where the version on screen has its pair. It needs no
        // load of its own to flip — both sides are in hand — so the bar's
        // settle is a formality, and its comparison is the review's own
        // delta, which Compare and Changes both read.
        settleForCompare: state.canFlip ? () async => true : null,
        comparing: state.isStart,
        onComparison: state.canFlip ? (_) => _vm.flip() : null,
        loadComparison: () async => _comparison(),
        // A card in the changes sheet names an exercise this page is holding:
        // tapping it lands on that exercise, the same promise the pass's bar
        // makes.
        onExerciseTap: state.shown == null ? null : _openExercise,
        // The floor names what a record's bar is reading: the walker says the
        // version and its date, so the bar's words say which KIND of version —
        // the plan itself, or a review's side (the default).
        recordLabel: state.isCurrent ? 'Current Plan' : null,
        child: Column(
          children: [
            PageHeader(
              title: widget.name,
              left: HeaderIconButton(
                icon: Icons.arrow_back_ios_new,
                semanticsLabel: 'Back',
                glyphSize: 18,
                color: AppColors.primary,
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
            Expanded(
              // The Builder is load-bearing: the floor measures the floating
              // bar it stands under through
              // `ScrollShrinkNavBar.contentInset`, which only answers from a
              // context INSIDE `reviewChrome`'s wrapper.
              child: Builder(
                builder: (context) =>
                    KeyboardFloorLayout(page: _body(), floor: _floor(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The record's floor (2026-10-27): the pass editor's own, so viewing a
  /// completed review reads as taking one.
  ///
  /// The version walker wears the session date bar's furniture — the same
  /// ghost box, the same arrows, the same caption rung — because it is the
  /// same question asked of a workout's story instead of a session's stack.
  /// The action row is the planner's, spent where a record cannot act: undo,
  /// redo and the trash have no edit behind them, and the star opens ratings a
  /// version never had. The tiles are live doors, `gain: false` like the
  /// planner's — a record gained nothing; the counts are the whole shelves.
  Widget _floor(BuildContext context) {
    final state = _vm.value;
    final exerciseId = state.activeExercise?.exerciseId;
    return Container(
      key: const ValueKey('record-workout-bar'),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        ScrollShrinkNavBar.contentInset(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReviewVersionBar(
            version: state.version,
            onOlder: state.canStepOlder ? _vm.stepOlder : null,
            onNewer: state.canStepNewer ? _vm.stepNewer : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              UndoRedoButtons(
                canUndo: false,
                canRedo: false,
                onUndo: () {},
                onRedo: () {},
                // A record has no edit behind it and no deleted sets to
                // restore: the trash keeps its slot and stays spent.
                deletedExercises: const [],
                onPickDeletedExercise: (_) {},
              ),
              const SizedBox(width: AppSpacing.sm),
              BarIconButton(
                key: const ValueKey('record-ratings-button'),
                icon: Icons.star_rounded,
                semanticsLabel: 'Session ratings',
                onPressed: () {},
                enabled: false,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SessionStatsTiles(
                  prCount: exerciseId == null ? 0 : _vm.prCountFor(exerciseId),
                  exerciseNoteCount: exerciseId == null
                      ? 0
                      : _vm.noteCountFor(exerciseId),
                  goalCount: exerciseId == null
                      ? 0
                      : _vm.openGoalsFor(exerciseId),
                  // A record gains nothing: the counts are the whole shelves
                  // behind the doors, exactly the planner's reading.
                  gain: false,
                  onPrTap: exerciseId == null
                      ? null
                      : () => _openPrHistory(exerciseId),
                  onNoteTap: exerciseId == null
                      ? null
                      : () => _openNotes(exerciseId),
                  onGoalTap: exerciseId == null
                      ? null
                      : () => _openGoals(exerciseId),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openExercise(String plannedExerciseId) {
    final shown = _vm.value.shown;
    if (shown == null) return;
    final index = _vm.value.exercises.indexWhere(
      (e) => e.plannedExerciseId == plannedExerciseId,
    );
    if (index >= 0) _vm.selectExercise(index);
  }

  /// The trophy: the exercise's whole PR feed, the same sheet the planner and
  /// the session floors open. A version is not a session, so no set ids and no
  /// start — every PR is history — and the pass this record belongs to is the
  /// checkpoint, so what landed since it leads the feed (2026-10-26). A PR on
  /// a set that met a goal draws green, the session floors' rule.
  void _openPrHistory(String exerciseId) {
    showPrHistorySheet(
      context,
      exerciseName: _exerciseName(exerciseId),
      prs: _vm.prHistoryFor(exerciseId),
      sessionSetIds: const <String>{},
      sinceLastReviewAt: widget.session.sinceDate,
      goalSetIds: _vm.value.goalSetIds,
    );
  }

  /// The bullseye: the exercise's goals on the PR History sheet's furniture.
  /// The record does not write, so the sheet is drawn without its New goal
  /// door — the read-only surface the sheet already supports (2026-10-26).
  void _openGoals(String exerciseId) {
    showExerciseGoalsSheet(
      context,
      exerciseName: _exerciseName(exerciseId),
      listenable: _vm,
      goalsFor: () => _vm.goalsForExercise(exerciseId),
      setsFor: () => _vm.value.goalTimeline,
      variationNames: widget.variationNames,
      onNewGoal: null,
    );
  }

  /// The note glyph: the exercise's notes, read through the session's own
  /// modal with its composer, pin, edit and delete gone — the notes are the
  /// user's, but this page is a record of what was, not a shelf to write on
  /// (the friend record's rule, 2026-10-23).
  void _openNotes(String exerciseId) {
    showExerciseNotesModal(
      context,
      listenable: _vm,
      notesFor: _vm.notesFor,
      loadNotesFor: _vm.loadNotesFor,
      addNote: (id, text) async {},
      toggleNotePin: (id, exerciseNoteId) async {},
      deleteNote: (id, exerciseNoteId) async {},
      updateNote: (id, exerciseNoteId, text) async {},
      exerciseId: exerciseId,
      exerciseName: _exerciseName(exerciseId),
      readOnly: true,
      sinceLastReviewAt: widget.session.sinceDate,
    );
  }

  String _exerciseName(String exerciseId) =>
      toProperCase(widget.exerciseNames[exerciseId] ?? exerciseId);

  Widget _body() {
    final state = _vm.value;
    final version = state.version;
    if (version == null) {
      return _empty('This review kept no record of this workout.');
    }
    final shown = state.shown;
    if (shown == null) {
      return _empty(switch (version.side) {
        // The document exists but does not hold this workout: it was added
        // after the pass began, or gone before it completed. The version is
        // still part of the story — saying what it says is the point.
        WorkoutVersionSide.start =>
          'This workout was not in the plan when this review began.',
        WorkoutVersionSide.end => 'This review kept no record of this workout.',
        WorkoutVersionSide.current => 'This workout is no longer in the plan.',
      });
    }
    final exercises = state.exercises;
    if (exercises.isEmpty) {
      return _empty(switch (version.side) {
        // The review found the workout empty and may well have filled it:
        // its own record of that is the other side.
        WorkoutVersionSide.start =>
          'The workout held no exercises when this review began.',
        WorkoutVersionSide.end =>
          'This review recorded no exercises for this workout.',
        WorkoutVersionSide.current => 'This workout holds no exercises yet.',
      });
    }
    final active = state.active.clamp(0, exercises.length - 1);
    final workoutNote = state.workoutNote?.trim() ?? '';

    return ListView(
      // The viewer's own insets — the card opens on the same 22pt gutter,
      // from the same 16 of air under the header (2026-10-26). The floor
      // below already answers for the floating bar it stands under, so the
      // page needs no inset of its own.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        // What was said about the workout as a whole, above the exercises it
        // is about — the same note the pass took through the bar's Note verb.
        // The review's, so it reads on the versions that review produced.
        if (workoutNote.isNotEmpty) ...[
          LambdaReadout(label: 'Review note', value: workoutNote),
          const SizedBox(height: AppSpacing.md),
        ],
        _card(exercises, active),
      ],
    );
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.inkSecondary,
        ),
      ),
    ),
  );

  /// The mark one exercise of the version on screen wears, read off
  /// [RecordWorkoutState.markReference] — the other side of its review, or
  /// on the current plan the newest end. A removed group wears the red minus
  /// on the end, where it is drawn from the start's copy because the snapshot
  /// dropped it (2026-10-27). An exercise missing from an end (or a current)
  /// version is one the pass ADDED — green plus. The start is the baseline:
  /// it is what was found, so it wears no marks at all — the pair's marks
  /// both live on the end, where the change happened. The mark is the whole
  /// difference: a removed group draws as the ordinary card its start held,
  /// wearing only the red glyph the added one wears green.
  ///
  /// One membership test with one extra reading, so the marks can never
  /// disagree across the eye: an exercise the end gained wears the plus
  /// there and is simply absent from the start, and one the pass removed
  /// wears the minus on the end's card. No reference at all (a review that
  /// kept one document, a plan no review has recorded) means nothing to read
  /// against, and every name stays bare.
  ExerciseMark? _mark(ContentExercise exercise, Set<String> removedIds) {
    final state = _vm.value;
    final version = state.version;
    if (version == null) return null;
    if (removedIds.contains(exercise.plannedExerciseId)) {
      return ExerciseMark.removed;
    }
    if (version.isStart) return null;
    final reference = state.markReference?.session;
    if (reference == null) return null;
    final known = reference.exercises.any(
      (e) => e.plannedExerciseId == exercise.plannedExerciseId,
    );
    return known ? null : ExerciseMark.added;
  }

  /// The two sides the bar's Compare and Changes both read.
  ///
  /// On a review version the pair is the review's own delta — start to end,
  /// whichever side is on screen — because the changes sheet answers "what
  /// did this pass do", and the eye reads the same two documents. On the
  /// current plan, the before side is the newest end: what changed since the
  /// last record. Everything downstream is the pass's own machinery, fed the
  /// record; nothing is loaded from the stores.
  ReviewComparison _comparison() {
    final state = _vm.value;
    final version = state.version;
    ProgramContent? wrap(ContentSession? session) =>
        session == null ? null : ProgramContent(sessions: [session]);
    ProgramContent? before;
    ProgramContent? after;
    if (version != null) {
      if (version.isCurrent) {
        before = wrap(state.newestEnd?.session);
        after = wrap(version.session);
      } else {
        final pair = state.sibling;
        final start = version.isStart ? version : pair;
        final end = version.isStart ? pair : version;
        before = wrap(start?.session);
        after = wrap(end?.session);
      }
    }
    return ReviewComparison(
      before: before,
      // Nothing on this page at all (the review recorded no version): the
      // sheet has nothing to say, which an empty document says without
      // needing the type to carry null.
      after: after ?? const ProgramContent(),
      exerciseNames: widget.exerciseNames,
      variationNames: widget.variationNames,
    );
  }

  /// The one exercise card, drawn through the shared card like every other
  /// workout surface — a second layout here would be a second thing to keep in
  /// step with the other three. The session look is the pass editor's own
  /// (2026-10-27): flat, no box, no pill row — the record's doors are on the
  /// floor, where the pass keeps its own.
  ///
  /// A group the pass removed keeps a card of its own here (2026-10-27): the
  /// end's snapshot dropped it, so it is drawn from the start's frozen copy —
  /// an ordinary card, its sets as they were, wearing only the red minus the
  /// added group wears green (the removal is the mark, not a repaint).
  Widget _card(List<ContentExercise> exercises, int active) {
    final exercise = exercises[active];
    final removedIds = _vm.value.removedIds;
    final sets = [...exercise.sets]
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    final notes = _vm.value.exerciseNotes;

    return SessionExerciseCard(
      flat: true,
      exerciseNames: [
        for (final e in exercises)
          toProperCase(
            widget.exerciseNames[e.exerciseId] ?? e.exerciseId ?? '',
          ),
      ],
      // What the two sides disagree about, on the name it is about: the eye
      // flips the values AND the marks, because the marks are the sides'
      // difference read from whichever one is on screen.
      exerciseMarks: [for (final e in exercises) _mark(e, removedIds)],
      activeIndex: active,
      onSelect: _vm.selectExercise,
      // Reordering and adding are writing; the record is neither. Reorder
      // greys the popover's arrows, add greys its row.
      onMove: null,
      onAdd: null,
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

/// The walker on a record's floor: which version of the workout is on screen,
/// and the two steps either side of it (2026-10-26).
///
/// The session date bar's own furniture — the ghost box around a
/// `SessionChevronButton` at each end (older left, newer right, a spent end
/// greyed and never absent) and the phrase between them at the date bar's
/// caption rung — so a record walks its story the way a session walks its
/// stack, and the record's floor reads as the pass editor's (2026-10-27). The
/// phrase names the version in the vocabulary the two documents have: `START
/// OF REVIEW - 12 Oct 2026` for what a pass found, `END OF REVIEW - …` for
/// what it left, and the lone `CURRENT PLAN` for the plan itself, which stands
/// outside any review. A review that kept no version at all says `NO RECORD`:
/// the bar still holds its place on the floor, honestly empty.
class _ReviewVersionBar extends StatelessWidget {
  const _ReviewVersionBar({required this.version, this.onOlder, this.onNewer});

  /// The version on screen; null when the review recorded none.
  final WorkoutVersion? version;

  /// Walk to the older version; null greys the left arrow.
  final VoidCallback? onOlder;

  /// Walk to the newer version; null greys the right arrow.
  final VoidCallback? onNewer;

  @override
  Widget build(BuildContext context) {
    final version = this.version;
    final date = version?.date;
    // The state word carries the "-" only when a date follows it: `CURRENT
    // PLAN` is the whole phrase on its own, the way the planner's `PLAN` is.
    final stateLabel = switch (version?.side) {
      WorkoutVersionSide.start => 'START OF REVIEW -',
      WorkoutVersionSide.end => 'END OF REVIEW -',
      WorkoutVersionSide.current => 'CURRENT PLAN',
      null => 'NO RECORD',
    };

    final phrase = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        key: const ValueKey('record-version-bar-phrase'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stateLabel,
            key: const ValueKey('record-version-bar-state'),
            style: AppFonts.mono(
              // The date bar's own caption rung: the two floors' phrases are
              // the same species of readout (2026-10-23).
              fontSize: AppTextStyles.caption,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.inkSecondary,
            ),
          ),
          if (date != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              DateFormat('d MMM yyyy').format(date.toLocal()),
              key: const ValueKey('record-version-bar-date'),
              style: AppFonts.mono(
                fontSize: AppTextStyles.caption,
                letterSpacing: 0.6,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
      key: const ValueKey('record-version-bar'),
      // The date bar's own box and inset: the same ghost container, the same
      // 5pt around an arrow at each edge, the phrase between them rather than
      // in whatever room they leave.
      padding: const EdgeInsets.all(5),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Row(
        children: [
          SessionChevronButton(
            key: const ValueKey('record-version-bar-older'),
            icon: Icons.chevron_left,
            semanticsLabel: 'Older version',
            enabled: onOlder != null,
            onPressed: onOlder ?? () {},
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: phrase),
          const SizedBox(width: AppSpacing.xs),
          SessionChevronButton(
            key: const ValueKey('record-version-bar-newer'),
            icon: Icons.chevron_right,
            semanticsLabel: 'Newer version',
            enabled: onNewer != null,
            onPressed: onNewer ?? () {},
          ),
        ],
      ),
    );
  }
}
