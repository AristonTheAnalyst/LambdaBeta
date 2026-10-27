// LAB COPY — the /dev/pr-lab layout sandbox's own copy of the session
// stage. Never import this from a production screen. Edit freely: nothing
// here can reach the real session, planner, logs or PR History demo
// (2026-10-21).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../session/model/session_local_state.dart';
import '../pr_history_fixture.dart';
import 'pr_lab_date_bar.dart';
import 'pr_lab_exercise_card.dart';
import 'pr_lab_exercise_selector.dart';
import 'pr_lab_header_icon_button.dart';
import 'pr_lab_notes.dart';
import 'pr_lab_exercise_notes_modal.dart';
import 'pr_lab_page_header.dart';
import 'pr_lab_planned_name_chip.dart';
import 'pr_lab_ratings_sheet.dart';
import 'pr_lab_set_row.dart';
import 'pr_lab_sheet.dart';
import 'pr_lab_undo_redo_buttons.dart';

/// The demo stage's session name: the header's title, and the eyebrow the
/// ratings sheet wears above its own title. A freestyle demo has no template
/// to name, so the stage names itself (2026-10-22).
const String kPrLabSessionTitle = 'Freestyle Session';

/// The lab's stand-in for `fact_session.planned_session_name`: the past
/// sessions that came from a template, keyed by session id. Today's live
/// demo is freestyle, so the header stands bare; walking the date bar onto
/// one of these dresses the title in the planned chip instead (2026-10-22).
const Map<String, String> _plannedSessionNames = {
  'demo-session-bench-p3': 'Push A',
};

/// The PR Lab — a self-contained copy of the PR History demo stage, built so
/// the screen can be rehauled without touching anything real (2026-10-21).
///
/// Every widget this screen draws is the lab's own copy: [PrLabPageHeader],
/// [PrLabExerciseCard], [PrLabExerciseSelector], [PrLabSetRow] and the
/// [showPrLabHistorySheet] feed. The data still comes from the shared fixture
/// ([demoPrsFor]) — layout experiments live here, the fake sets stay one
/// source of truth.
///
/// Nothing here touches the database or a viewmodel: the card is
/// [PrLabExerciseCard] over hard-coded sets, and the live controls are the
/// action bar's pencil — the session's pre/post ratings and notes as a sheet,
/// the other door to the wizard's bookend pages (2026-10-22) — its two metric
/// tiles (the trophy opens the lab's PR feed for the exercise on screen, the
/// book its notes modal, both split into what this session added and what
/// came before), and the date bar's arrows, which walk that exercise's past
/// sessions. The tiles' counts are the SESSION's gains ("+2" PRs, "+1"
/// note), not the all-time totals the doors open; they never move as the
/// date bar walks, because the session on the desk is always the one being
/// counted (2026-10-21). Walking off today puts the card in its read-only
/// historical reading, and the pencil's sheet read-only with it.
class PrLabScreen extends StatefulWidget {
  const PrLabScreen({super.key});

  @override
  State<PrLabScreen> createState() => _PrLabScreenState();
}

class _PrLabScreenState extends State<PrLabScreen> {
  int _activeIndex = 0;

  /// Which of [ExerciseHistorySession]s the date bar is showing: 0 is
  /// today's live session, 1 the previous workout that exercise was in, and
  /// so on — the bar's left arrow walks forward in the list (older), its
  /// right arrow back toward today.
  int _historyIndex = 0;

  /// The notes the book tile opens — in memory, seeded, and lab-owned. No
  /// database, no repository; the shared sheet just writes here.
  final PrLabNoteStore _notes = PrLabNoteStore();

  /// Pre/post ratings and notes, keyed by the date the date bar is naming.
  /// In memory like the note store: the pencil's sheet writes here and
  /// nothing else reads it — the wizard pages are not part of this stage.
  final Map<String, PrLabRatings> _ratings = {};

  /// Notes saved on the live rows, keyed by set id. The fixture's sets carry
  /// few notes, so without this map a save would never show: the row's Note
  /// circle fills only once the set has one (2026-10-22).
  final Map<String, String> _liveNotes = {};

  /// Whether the card on screen is being read as a deleted exercise — the
  /// lab's stand-in for the viewer's trash. The fixture carries no deleted
  /// rows, so picking the faux "Dumbbell Fly" slot dresses the ACTIVE card in
  /// the deleted rim instead; choosing another exercise clears it. It exists
  /// so the red outline is on the stage, not just in the code (2026-10-22).
  bool _deletedDemo = false;

  /// The fake user's whole history, grouped per exercise newest-first — the
  /// exact grouping the live session's history picker reads.
  late final Map<String, List<ExerciseHistorySession>> _historyByExercise =
      groupHistoryByExercise(kDemoPastSets);

  /// Every set that ever was a PR, all-time. The historical rows' accents
  /// read this; the live grid's own accents stay today's
  /// ([kDemoSessionPrSetIds]).
  static final Set<String> _allTimePrSetIds = {
    for (final prs in kDemoPrsByExercise.values)
      for (final event in prs)
        if (event.sessionExerciseSetId != null) event.sessionExerciseSetId!,
  };

  DemoExercise get _exercise => kDemoExercises[_activeIndex];

  /// The exercise on screen's sessions, newest first. Index 0 is today's
  /// live session; the rest are the workouts it was done in before.
  List<ExerciseHistorySession> get _sessions =>
      _historyByExercise[_exercise.id] ?? const [];

  /// Whether the date bar has walked off today onto a past session.
  bool get _viewingHistory =>
      _historyIndex > 0 && _historyIndex < _sessions.length;

  ExerciseHistorySession? get _viewedSession =>
      _viewingHistory ? _sessions[_historyIndex] : null;

  /// The plan the session on the desk followed, or null for freestyle — the
  /// header's one switch (2026-10-22).
  String? get _sessionPlanName {
    final session = _viewedSession;
    if (session == null || session.sets.isEmpty) return null;
    return _plannedSessionNames[session.sets.first.sessionId];
  }

  /// The session on the desk, named: its plan when it had one, the generic
  /// freestyle title otherwise.
  String get _sessionName => _sessionPlanName ?? kPrLabSessionTitle;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// The trophy tile — the lab's PR feed for the exercise on screen, split
  /// into this session's PRs and the ones before it.
  void _openHistory() {
    showPrLabHistorySheet(
      context,
      exerciseName: _exercise.name,
      prs: demoPrsFor(_exercise.id),
      sessionSetIds: kDemoSessionPrSetIds,
    );
  }

  /// The book tile — the lab's notes modal over the lab's own store, so
  /// add/pin/edit/delete all work and all stay in memory. The session id is
  /// what separates the notes typed into today's session from the earlier
  /// ones (2026-10-21).
  void _openNotes() {
    final exercise = _exercise;
    showPrLabNotesModal(
      context,
      listenable: _notes,
      notesFor: _notes.notesFor,
      loadNotesFor: _notes.loadNotesFor,
      addNote: _notes.addNote,
      toggleNotePin: _notes.togglePin,
      deleteNote: _notes.deleteNote,
      updateNote: _notes.updateText,
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      sessionId: kPrLabSessionId,
    );
  }

  /// The ratings the pencil opens for the session on the desk, seeded on
  /// first read: today is the session being filled in, so it comes with
  /// answers to read; a walked-to history keeps its own seeded set. Keyed by
  /// date — the lab carries no session ids, and the date bar is the
  /// navigator (2026-10-22).
  PrLabRatings _ratingsFor(DateTime date) => _ratings.putIfAbsent(
    _dateKey(date),
    () => _dateKey(date) == _dateKey(kDemoToday)
        ? const PrLabRatings(
            preFeeling: 4,
            preNotes: 'Slept well — feeling strong',
            postFeeling: 3,
            postNotes: 'Rushed the last set',
          )
        : const PrLabRatings(
            preFeeling: 3,
            preNotes: 'Woke up stiff — shoulders tight',
            postFeeling: 4,
            postNotes: 'Better than expected once warm',
          ),
  );

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// One ratings page per entry of the date bar's list: today leads, the rest
  /// are the workouts this exercise was done in before. Clamped, so a stale
  /// index can never read past the list.
  PrLabRatingsPage _ratingsPage(int index) {
    final sessions = _sessions;
    final i = sessions.isEmpty ? 0 : index.clamp(0, sessions.length - 1);
    final date = sessions.isEmpty ? kDemoToday : sessions[i].date;
    return PrLabRatingsPage(
      index: i,
      date: date,
      isToday: i == 0,
      ratings: _ratingsFor(date),
      canGoOlder: i + 1 < sessions.length,
      canGoNewer: i > 0,
    );
  }

  /// The page an arrow steps to, or null when the step would walk off the
  /// end — the sheet greys that arrow, and this is the guard behind it.
  PrLabRatingsPage? _ratingsPageAt(int index) {
    final count = _sessions.isEmpty ? 1 : _sessions.length;
    return index < 0 || index >= count ? null : _ratingsPage(index);
  }

  /// The pencil — the same four answers the pre/post wizard pages carry, in
  /// one sheet, with the stage's own date changer at its foot: stepping it
  /// walks the session on the desk, so the sheet and the card behind it
  /// never disagree (2026-10-22).
  void _openRatings() {
    showPrLabRatingsSheet(
      context,
      workoutName: _sessionName,
      page: _ratingsPage(_historyIndex),
      pageAt: _ratingsPageAt,
      onIndexChanged: (index) {
        if (index == _historyIndex) return;
        setState(() => _historyIndex = index);
      },
      onChanged: (index, next) =>
          _ratings[_dateKey(_ratingsPage(index).date)] = next,
    );
  }

  /// Steps the date bar: +1 is the previous workout (older), -1 the next one
  /// (newer). The ends are clamped here so a stale tap can never walk off the
  /// list; the arrows themselves are drawn inert there.
  void _stepHistory(int delta) {
    final next = _historyIndex + delta;
    if (next < 0 || next >= _sessions.length) return;
    setState(() => _historyIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final planName = _sessionPlanName;
    return Scaffold(
      backgroundColor: AppColors.bg,
      // The keyboard paints OVER the floor rather than lifting it: the date
      // changer and the action bar are chrome, and typing in a set cell must
      // not move them. The shell's own Scaffold opts out with this one, or
      // the nav bar underneath would still ride the inset (2026-10-21).
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          PrLabPageHeader(
            // The header names the session on the desk, and its chrome says
            // where that session came from: a session that followed a plan
            // draws the name in the planned chip — blue on blue — while a
            // freestyle session keeps the plain title with no container at
            // all (2026-10-22). The real Training header names a planned
            // session the same way.
            title: kPrLabSessionTitle,
            titleWidget: planName == null
                ? null
                : PrLabPlannedNameChip(name: planName),
            left: PrLabHeaderIconButton(
              icon: Icons.arrow_back_ios_new,
              semanticsLabel: 'Back',
              glyphSize: 18,
              color: AppColors.primary,
              onPressed: () => context.pop(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                // 16, not 12: the selector needs one more step of air under
                // the header's hairline — the card's top read cramped
                // (2026-10-22).
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: PrLabExerciseCard(
                key: ValueKey(exercise.id),
                exerciseNames: [for (final e in kDemoExercises) e.name],
                // A freestyle session's exercises are all beyond any
                // plan — the live card marks them with the green plus.
                exerciseMarks: [
                  for (final _ in kDemoExercises) PrLabExerciseMark.added,
                ],
                activeIndex: _activeIndex,
                // Switching exercise returns the date bar to today: the
                // index is an offset into THAT exercise's timeline. It also
                // leaves the deleted demo — the rim belongs to the slot the
                // trash was opened from, not to the next one (2026-10-22).
                onSelect: (index) => setState(() {
                  _activeIndex = index;
                  _historyIndex = 0;
                  _deletedDemo = false;
                }),
                onMove: null,
                onAdd: null,
                // The deleted rim, drawn by the demo flag. Planned is the
                // other rim; a freestyle demo has no plan to wear it.
                deleted: _deletedDemo,
                // Walking onto a past session swaps today's rows for that
                // session's recorded ones and drops the add row. The card's
                // chrome does not change: history is this same Training
                // view, read-only (2026-10-22).
                rows: _viewingHistory
                    ? [for (final set in _viewedSession!.sets) _historyRow(set)]
                    : _rowsFor(exercise),
                // Kept present (greyed would hide it) so the live grid
                // has its shape; a past session has nothing to add to.
                onAddSet: _viewingHistory ? null : () {},
              ),
            ),
          ),
          // The floor: the date changer pinned just above the action bar, so
          // walking the history never scrolls its own position out of sight
          // (2026-10-21).
          Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              ScrollShrinkNavBar.contentInset(context),
            ),
            decoration: BoxDecoration(
              color: AppColors.bg,
              border: Border(
                top: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sessionDateBar(),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    // The lab's own undo/redo pair at the nav bar's scale,
                    // with the trash slot the live bar carries — one fake
                    // deleted exercise so the slot's live state (accent,
                    // opens its menu) is on the stage, not just its empty
                    // greyed one (2026-10-21).
                    PrLabUndoRedoButtons(
                      canUndo: false,
                      canRedo: false,
                      onUndo: () {},
                      onRedo: () {},
                      deletedExercises: const ['Dumbbell Fly'],
                      // Picking the faux deleted exercise draws its reading
                      // on the active card (see [_deletedDemo]).
                      onPickDeletedExercise: (_) =>
                          setState(() => _deletedDemo = true),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // The pencil: the pre/post questionnaire as a sheet —
                    // another door to the same four answers the wizard's
                    // bookend pages carry (2026-10-22). A notes pencil, not
                    // the header's edit pencil: the viewer will draw both.
                    // It wears the tiles' orange glass — a door to session
                    // content, like the trophy and the book beside it, not
                    // neutral chrome like the undo/redo pair (2026-10-22).
                    PrLabHeaderIconButton(
                      key: const ValueKey('pr-lab-ratings-button'),
                      icon: Icons.edit_note,
                      semanticsLabel: 'Session ratings',
                      variant: PrLabHeaderIconVariant.boxed,
                      boxSize: kPrLabBarControlSize,
                      radius: AppRadius.md,
                      glyphSize: 24,
                      color: AppColors.accent,
                      onPressed: _openRatings,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      // Session-scoped metrics: both tiles quote what THIS
                      // session added for the exercise on screen — the same
                      // "+N" the session's pills carry — and they hold while
                      // the date bar walks the history. The notes tile
                      // rebuilds as the store changes so a note added in
                      // the modal shows up on the bar behind it.
                      child: ListenableBuilder(
                        listenable: _notes,
                        builder: (context, _) => _PrLabStatsBar(
                          prCount: demoSessionPrsFor(exercise.id),
                          exerciseNoteCount: _notes.sessionCountFor(exercise.id),
                          onTapPrs: _openHistory,
                          onTapNotes: _openNotes,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The date changer at the floor, just above the action bar: the session on
  /// screen, centred between the previous/next workout arrows for this
  /// exercise. The widget itself is shared with the ratings sheet, so the two
  /// read as one control (2026-10-22).
  ///
  /// Pinned rather than scrolling with the card — it names the card's
  /// position in the history, and a position that scrolls away cannot be
  /// read. Left walks back through the exercise's timeline (older), right
  /// returns toward today.
  Widget _sessionDateBar() => PrLabDateBar(
    keys: PrLabDateBarKeys.session,
    isToday: !_viewingHistory,
    date: _viewedSession?.date ?? kDemoToday,
    canGoOlder: _historyIndex + 1 < _sessions.length,
    canGoNewer: _historyIndex > 0,
    onOlder: () => _stepHistory(1),
    onNewer: () => _stepHistory(-1),
  );

  /// Today's sets as the shared live rows. The callbacks are inert — the row
  /// keeps its live chrome (which `readOnly` alone would not preserve), but
  /// nothing typed here is stored anywhere.
  List<Widget> _rowsFor(DemoExercise exercise) => [
    for (final set in demoSessionRows(exercise.id))
      PrLabSetRow(
        key: ValueKey(set.sessionExerciseSetId),
        mode: PrLabSetRowMode.live,
        exerciseId: exercise.id,
        displayIndex: set.setNumber,
        isDraft: false,
        initialWeightText: formatPrNumber(set.weight ?? 0),
        initialRepsText: _repsText(set),
        initialVariationId: set.variationId,
        initialVariationName: set.variationName,
        // A note typed through the swipe sheet fills the Note circle on the
        // spot — the lab keeps the note it just saved (2026-10-22).
        hasNotes: (_liveNotes[set.sessionExerciseSetId] ?? set.notes ?? '')
            .trim()
            .isNotEmpty,
        isPr: kDemoSessionPrSetIds.contains(set.sessionExerciseSetId),
        onCommit: (isDraft, values, {bool immediate = false}) async {},
        onVariationChanged: (_) {},
        onNotesSave: (text) => setState(
          () => _liveNotes[set.sessionExerciseSetId] = text,
        ),
        onDelete: () async {},
        onDuplicate: (_) {},
        variationOptions: _variationOptions,
        allVariations: _allVariations,
        findSimilarVariations: (_) => const [],
        submitNewVariation:
            (name, {required exerciseId, useExistingId}) async => null,
      ),
  ];

  String _repsText(PastSetRow set) =>
      set.reps.isEmpty ? '' : formatPrNumber(set.reps.first);

  /// One row of a past session's detail — the history viewer's read-only row,
  /// [PrLabSetRow]'s exact chrome in `history` mode. Values are the recorded
  /// ones; every callback below is inert because there is nothing on a past
  /// set to write from this lab.
  Widget _historyRow(PastSetRow set) => PrLabSetRow(
    key: ValueKey('pr-lab-history-${set.sessionExerciseSetId}'),
    mode: PrLabSetRowMode.history,
    exerciseId: set.exerciseId ?? '',
    displayIndex: set.setNumber,
    isDraft: false,
    initialWeightText: set.weight == null ? '' : formatPrNumber(set.weight!),
    initialRepsText: _repsText(set),
    initialVariationId: set.variationId,
    initialVariationName: set.variationName,
    initialNotes: set.notes,
    hasNotes: set.notes?.isNotEmpty ?? false,
    isPr: _allTimePrSetIds.contains(set.sessionExerciseSetId),
    readOnly: true,
    onCommit: (isDraft, values, {bool immediate = false}) async {},
    onVariationChanged: (_) {},
    onNotesSave: (_) {},
    onDelete: () async {},
    onDuplicate: (_) {},
    variationOptions: _variationOptions,
    allVariations: _allVariations,
    findSimilarVariations: (_) => const [],
    submitNewVariation: (name, {required exerciseId, useExistingId}) async =>
        null,
  );
}

const _variationOptions = <DropdownOption<String?>>[
  DropdownOption(label: 'No Variation', value: null),
  DropdownOption(
    label: kDemoPausedVariationName,
    value: kDemoPausedVariationId,
  ),
];

const _allVariations = <({String id, String name})>[
  (id: kDemoPausedVariationId, name: kDemoPausedVariationName),
];

/// The live `SessionStatsBar` is bound to a `SessionViewModel`, which the
/// demo deliberately has none of. This copies its tile recipe for the stage —
/// dev-only scenery, not a shared widget — at the bar's new scale (tiles as
/// tall as the undo/redo boxes beside them, the nav bar's 24px glyphs), and
/// reads SESSION-scoped: the trophy counts the PRs the session on the desk
/// added for the exercise, drawn as a gain ("+2"), the book the notes typed
/// into it ("+1"); a session that added none reads "0". Both doors still open
/// the full feed behind the number — the all-time PRs, every note the
/// exercise has — and both stay tappable at 0 (2026-10-21).
class _PrLabStatsBar extends StatelessWidget {
  const _PrLabStatsBar({
    required this.prCount,
    required this.exerciseNoteCount,
    required this.onTapPrs,
    required this.onTapNotes,
  });

  final int prCount;
  final int exerciseNoteCount;
  final VoidCallback onTapPrs;
  final VoidCallback onTapNotes;

  /// A gain reads "+2"; a session that added none reads "0" — a "+0" would
  /// claim a change where there was none.
  static String _gain(int n) => n > 0 ? '+$n' : '0';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tile(
            key: const ValueKey('pr-lab-prs-tile'),
            icon: Icons.emoji_events,
            value: _gain(prCount),
            semanticsLabel: '$prCount PRs this session',
            onTap: onTapPrs,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _tile(
            key: const ValueKey('pr-lab-notes-tile'),
            icon: Icons.menu_book_outlined,
            value: _gain(exerciseNoteCount),
            semanticsLabel: '$exerciseNoteCount notes this session',
            onTap: onTapNotes,
          ),
        ),
      ],
    );
  }

  /// The glass tile, reduced to what the bar asks now: a glyph and its
  /// count, both accent — these are doors, not statuses. Standing
  /// [kPrLabBarControlSize] tall so the bar is one row of equal controls. The
  /// label is the whole reading for a screen reader, so the glyph never
  /// announces an empty shape and the number never arrives alone.
  Widget _tile({
    Key? key,
    required IconData icon,
    required String value,
    required String semanticsLabel,
    required VoidCallback onTap,
  }) {
    final color = AppColors.accent;
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: key,
          height: kPrLabBarControlSize,
          // 8, not the old 12: the pencil now shares this row, and the two
          // tiles each lost a third of their width to it (2026-10-22).
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: glassBox(color),
          // Scale-to-fit so a narrow stage narrows the line rather than
          // overflowing it (the goal card's squeeze, 2026-10-20). A no-op at
          // the tile's natural size.
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
