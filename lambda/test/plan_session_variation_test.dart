import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/core/styles/app_text_styles.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/exercise_note.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_exercise.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/programs/view/plan_session_screen.dart';
import 'package:lambda/features/programs/view/review_container.dart';
import 'package:lambda/features/programs/viewmodel/workout_editor_viewmodel.dart';
import 'package:lambda/features/session/view/session_stats_bar.dart';
import 'package:lambda/shared/widgets/bar_icon_button.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/session_chevron_button.dart';
import 'package:lambda/shared/widgets/session_exercise_card.dart';
import 'package:lambda/shared/widgets/undo_redo_buttons.dart';

/// A variation picked on an empty draft set, and the exercise switch that used
/// to eat it.
///
/// Add sets → give them a variation → switch exercise → come back: the
/// variations were gone. A draft row keeps its variation row-locally until it
/// commits, deliberately — blurring is what commits it, and a keystroke must
/// not materialize a draft mid-typing. But only the active exercise's card is
/// built, so switching exercises *disposes* the row, and a variation on an
/// otherwise empty row is exactly the case where nothing else would ever
/// commit it: there is no text to blur out of. The row's own contract was
/// never the problem (the live session has flushed this way since drafts
/// exist) — the planner simply never gave its rows a way to be flushed.
///
/// This is a screen-level test on purpose. Three links have to hold at once:
/// the screen registering the row's commit handle, `tapTab` running them
/// before the card is destroyed, and the draft's commit carrying the variation
/// out. Any narrower test passes with the bug still in place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces. Flutter's test font gives every glyph the same
  // square advance, which is enough to report overflows no device would draw.
  setUpAll(() async {
    await _loadFont(AppFonts.uiFamily, const [
      'assets/fonts/Manrope-400.ttf',
      'assets/fonts/Manrope-600.ttf',
      'assets/fonts/Manrope-800.ttf',
    ]);
    await _loadFont(AppFonts.monoFamily, const [
      'assets/fonts/JetBrainsMono-400.ttf',
      'assets/fonts/JetBrainsMono-700.ttf',
    ]);
  });

  const userId = 'u1';
  const sessionId = 'ws-psycho-1';
  const cableRowId = 'ex-cable-row';
  const benchPressId = 'ex-bench-press';
  const pausedVariationId = 'v-paused';

  late _FakePlanned planned;
  late _FakeNotes notes;
  late _FakeSessions sessions;
  late WorkoutEditorViewModel vm;

  setUp(() {
    planned = _FakePlanned(userId: userId, sessionId: sessionId)
      ..addExercise(cableRowId, name: 'Cable Row', order: 1)
      ..addExercise(benchPressId, name: 'Bench Press', order: 2);
    notes = _FakeNotes();
    sessions = _FakeSessions();
    vm = WorkoutEditorViewModel(
      exerciseRepo: _FakeExercises(),
      noteRepo: notes,
      workoutRepo: sessions,
      workoutPlanRepo: planned,
      // The identity `Supabase.instance` would otherwise supply. Without it a
      // host test cannot open the planner at all.
      userId: userId,
    );
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    // The iPhone 17's logical size — the width the set grid and the exercise
    // pills are laid out in.
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: PlanSessionScreen(
          viewModel: vm,
          workout: PlannedSession(
            sessionId: sessionId,
            userId: userId,
            name: 'Psycho 1',
          ),
        ),
      ),
    );
    // The open runs in a post-frame callback and is awaited; settle covers the
    // catalog load and the set read behind it.
    await tester.pumpAndSettle();
  }

  /// Switches the active exercise the way the user does: tap the selector
  /// field, then the exercise's row in the popover it opens. The field draws
  /// only the *active* exercise, so the target is reachable by name only once
  /// the popover is up — and when the popover is open the field is showing the
  /// other one, which is why the row is the last match.
  Future<void> switchTo(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  /// Adds one draft row to the active exercise and gives it [label], the way
  /// the user does: `+ ADD SET`, then the variation cell's picker.
  Future<void> addDraftWithVariation(
    WidgetTester tester,
    int draftId,
    String label,
  ) async {
    await tester.tap(find.text('+ ADD SET'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('draft-$draftId')),
        matching: find.byType(DropdownSelect<String?>),
      ),
    );
    await tester.pumpAndSettle();
    // The picker sheet's row for the option — the row's own cell still reads
    // "No Variation" at this point, so the sheet's label is the last one.
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a variation picked on an empty draft survives an exercise '
      'switch', (tester) async {
    await pumpEditor(tester);

    await addDraftWithVariation(tester, 1, 'Paused');

    // The draft is still a draft: the pick is row-local and has not been
    // written. That is the contract, and it is what makes the flush below the
    // only thing that can save it.
    expect(
      planned.created,
      isEmpty,
      reason:
          'picking a variation must not materialize a row on its own — '
          'a draft materializes when it commits, and it commits on blur or '
          'on a flush',
    );

    // Leave the card, exactly as the user does.
    await switchTo(tester, 'Bench Press');

    expect(
      planned.created,
      hasLength(1),
      reason:
          'the switch destroyed the row; the registered commit is the '
          'only thing that could have carried the pick out first',
    );
    final written = planned.created.single;
    expect(
      written.exerciseId,
      cableRowId,
      reason:
          'the row belongs to the exercise it was added under, not to '
          'the one the user switched to',
    );
    expect(written.variationId, pausedVariationId);
    expect(written.targetWeight, isNull);
    expect(
      written.targetReps,
      isNull,
      reason:
          'nothing was typed — the variation alone is what the user '
          'entered, and it is enough to make the set real',
    );

    // And back, which is where the user saw the loss.
    await switchTo(tester, 'Cable Row');

    expect(find.byKey(ValueKey(written.plannedSetId)), findsOneWidget);
    expect(
      find.text('Paused'),
      findsOneWidget,
      reason: 'the cell reads the variation back out of the database',
    );
  });

  testWidgets('three empty drafts, three variations, one switch', (
    tester,
  ) async {
    // The report, at its own width: three sets, all three varied, then away.
    await pumpEditor(tester);

    await addDraftWithVariation(tester, 1, 'Paused');
    await addDraftWithVariation(tester, 2, 'Paused');
    await addDraftWithVariation(tester, 3, 'Tempo');

    await switchTo(tester, 'Bench Press');

    expect(planned.created, hasLength(3));
    expect(planned.created.map((s) => s.variationId), [
      pausedVariationId,
      pausedVariationId,
      'v-tempo',
    ]);
    expect(
      planned.created.map((s) => s.setNumber),
      [1, 2, 3],
      reason:
          'the flushed rows are numbered in the order the user built '
          'them — three cards\' worth of set numbers, not three first sets',
    );
  });

  testWidgets('Save flushes a draft the user varied but never typed in', (
    tester,
  ) async {
    await pumpEditor(tester);

    await addDraftWithVariation(tester, 1, 'Paused');

    // Save's own pass writes one (empty) row per remaining draft. Without the
    // flush in front of it, that pass is what the varied draft becomes: an
    // empty row, and the pick is dropped on the floor.
    await vm.saveWorkout();

    expect(planned.created, hasLength(1));
    expect(
      planned.created.single.variationId,
      pausedVariationId,
      reason:
          'the row Save wrote for this draft is the row the user '
          'described, variation included — and there is exactly one of it',
    );
  });

  /// The same screen, with a review running and this workout open under it.
  Future<void> pumpEditorInReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    reviewSessionNotifier.value = ReviewSession(
      reviewId: 'rev1',
      programId: null,
      sessionIds: const [sessionId],
      activeSessionId: sessionId,
      activeWorkoutName: 'Psycho 1',
    );
    await tester.pumpWidget(
      ReviewScope(
        child: MaterialApp(
          home: PlanSessionScreen(
            viewModel: vm,
            workout: PlannedSession(
              sessionId: sessionId,
              userId: userId,
              name: 'Psycho 1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ── The workout's note ───────────────────────────────────────────────────
  //
  // A pass's three per-workout verbs are on its bar — the note among them,
  // beside Compare and Done, because all three are about the workout the pass
  // has open. The header keeps no Note, and no Delete at all since
  // 2026-10-28: a workout is deleted by the swipe in its library list, and
  // taking one OUT of a review is the landing's swipe — the bar's second
  // trailing box crowded the name it centres. It rides the same harness as
  // the tests above because the planner screen IS the review's editor; only
  // the ambient session differs.
  group('the workout\'s note', () {
    /// The bar's note glyph. Since the one-note-glyph sweep (2026-10-23) the
    /// card's Notes pill, its pinned-note bar and the set rows' swipe drawers
    /// all wear the same icon — they are the *exercise's* notes. The bar's is
    /// the *workout's*, so it has to be asked for by where it sits.
    Finder barNoteGlyph() => find.descendant(
      of: find.byType(ReviewBar),
      matching: find.byIcon(Icons.sticky_note_2_outlined),
    );

    // The session and its notes are process-global, matching the bar's — a
    // test that left one running would hand it to the next one.
    setUp(() {
      reviewSessionNotifier.value = null;
      reviewWorkoutNotesNotifier.value = const {};
    });
    tearDown(() {
      reviewSessionNotifier.value = null;
      reviewWorkoutNotesNotifier.value = const {};
    });

    testWidgets('outside a review the header carries no Delete, and the '
        'workout\'s note has no door', (tester) async {
      await pumpEditor(tester);

      expect(
        find.byIcon(Icons.delete_outline),
        findsNothing,
        reason:
            'the library\'s swipe deletes a workout; a second door in the '
            'header crowded the title (2026-10-28)',
      );
      // The workout's note door lives on the review bar, and there is no bar
      // to hold one. Since the planner wears the session floor (2026-10-26)
      // the floor's note tile also wears the glyph — that one opens the
      // EXERCISE's notes shelf, the session floors' own door, not the
      // workout's note. So the sweep counts the card's glyphs and the tile's,
      // and nothing else.
      expect(
        barNoteGlyph(),
        findsNothing,
        reason:
            'there is no pass to hold a note, so there is no door to one — '
            'not in the header',
      );
      expect(find.byType(ReviewBar), findsNothing);
      final cardGlyphs = find.descendant(
        of: find.byType(SessionExerciseCard),
        matching: find.byIcon(Icons.sticky_note_2_outlined),
      );
      final floorNoteTile = find.descendant(
        of: find.byKey(const ValueKey('plan-session-bar')),
        matching: find.byIcon(Icons.sticky_note_2_outlined),
      );
      expect(
        floorNoteTile,
        findsOneWidget,
        reason:
            'the floor\'s note tile is the planner\'s door to the exercise\'s '
            'whole notes shelf — the live session\'s own tile',
      );
      expect(
        find.byIcon(Icons.sticky_note_2_outlined).evaluate().length,
        cardGlyphs.evaluate().length + floorNoteTile.evaluate().length,
        reason:
            'every other note glyph belongs to the card or the floor tile — '
            'the nav bar and the header hold none',
      );
    });

    testWidgets('inside a review the header drops Delete, and the bar\'s '
        'glyph opens the workout\'s own sheet', (tester) async {
      await pumpEditorInReview(tester);

      expect(
        find.byIcon(Icons.delete_outline),
        findsNothing,
        reason:
            'deleting the planned workout is not a verb of the pass — '
            'removing it from the review is a swipe on the landing',
      );
      expect(
        barNoteGlyph(),
        findsOneWidget,
        reason:
            'the note is the pass\'s verb for this workout, so it stands '
            'with Compare and Done on the bar',
      );
      expect(
        tester.widget<Icon>(barNoteGlyph()).color,
        AppColors.muted,
        reason: 'nothing is noted yet, so the glyph sits back — not absent',
      );

      await tester.tap(barNoteGlyph());
      await tester.pumpAndSettle();

      // The sheet the bar opened is the WORKOUT's: the review-note title, and
      // the workout the pass has open named as its subject.
      expect(find.text('Review note'), findsOneWidget);
      expect(find.text('PSYCHO 1'), findsOneWidget);
    });

    testWidgets('the glyph goes green once the pass holds a note', (
      tester,
    ) async {
      reviewWorkoutNotesNotifier.value = const {sessionId: 'Felt heavy'};
      await pumpEditorInReview(tester);

      expect(
        tester.widget<Icon>(barNoteGlyph()).color,
        AppColors.success,
        reason:
            'the glyph says what has been recorded, not just what can be — '
            'in the review bar\'s own green, the colour it lights controls in',
      );
    });
  });

  // ── The planner's floor ──────────────────────────────────────────────────
  //
  // The planner wears the session floor (2026-10-26): the date bar, the row of
  // 48pt squares, the tiles — the three session surfaces stand on one recipe.
  // What a plan cannot do it draws spent rather than omitting, the session
  // floors' own rule for a null callback: a template has no place in time (the
  // bar reads a lone PLAN, both chevrons spent) and no session ratings (the
  // star spent). Outside a pass the trash is spent too — archived groups are
  // hidden and undo is the way back; inside one it lists the pass's removals
  // and supports a Restore (2026-10-28). The tiles are the floor's one live
  // door — the active exercise's whole PR feed and notes shelf. The custom
  // SETS · EXERCISES pill is gone with the custom floor it belonged to, and
  // the card is the session's flat one.
  group('the planner\'s floor', () {
    setUp(() => reviewSessionNotifier.value = null);
    tearDown(() => reviewSessionNotifier.value = null);

    Finder floor() => find.byKey(const ValueKey('plan-session-bar'));

    testWidgets('stands on the session floor, its date bar reading PLAN', (
      tester,
    ) async {
      await pumpEditor(tester);

      expect(floor(), findsOneWidget);
      expect(
        find.descendant(of: floor(), matching: find.text('PLAN')),
        findsOneWidget,
        reason:
            'a template is planned for sessions, not recorded by one — the '
            'bar has no date to read, and says so rather than inventing one',
      );
      expect(
        tester
            .widget<SessionChevronButton>(
              find.byKey(const ValueKey('session-date-bar-older')),
            )
            .enabled,
        isFalse,
        reason: 'a plan stands in no stack, so there is nothing older',
      );
      expect(
        tester
            .widget<SessionChevronButton>(
              find.byKey(const ValueKey('session-date-bar-newer')),
            )
            .enabled,
        isFalse,
        reason: 'and nothing newer',
      );
      expect(
        find.byKey(const ValueKey('session-date-bar-mode')),
        findsNothing,
        reason: 'a plan walks no stack, so there are no stacks to name',
      );
      expect(
        find.text('SETS'),
        findsNothing,
        reason:
            'the custom floor and its counts pill are gone — the planner '
            'draws the session bar, not a stats strip of its own',
      );
      expect(find.text('EXERCISES'), findsNothing);
    });

    testWidgets('the star and the trash stand spent, the tiles stay doors', (
      tester,
    ) async {
      await pumpEditor(tester);

      expect(
        tester
            .widget<BarIconButton>(
              find.byKey(const ValueKey('plan-ratings-button')),
            )
            .enabled,
        isFalse,
        reason:
            'ratings are a session\'s five feelings, and a plan has no '
            'session — the star keeps its slot and offers nothing',
      );
      expect(
        tester
            .widget<BarIconButton>(
              find.descendant(
                of: find.byType(DeletedExercisesButton),
                matching: find.byType(BarIconButton),
              ),
            )
            .enabled,
        isFalse,
        reason:
            'a planner deletes a group outright and undo is its way back — '
            'there are no deleted sets for the trash to restore',
      );
      final tiles = tester.widget<SessionStatsTiles>(
        find.byType(SessionStatsTiles),
      );
      expect(
        tiles.gain,
        isFalse,
        reason:
            'a plan gained nothing: the counts are the whole shelves behind '
            'the doors, not a session\'s additions',
      );
      expect(
        tiles.onPrTap,
        isNotNull,
        reason:
            'a 0 still hides the exercise\'s whole PR feed behind the trophy '
            '— the session floors\' rule',
      );
      expect(
        tiles.onNoteTap,
        isNotNull,
        reason: 'and the exercise\'s whole notes shelf behind the note',
      );
      expect(
        tiles.onGoalTap,
        isNotNull,
        reason:
            'and the exercise\'s goals behind the bullseye — a plan reads the '
            'same three shelves the sessions do (2026-10-27)',
      );
    });

    testWidgets('the card is the session card — flat, with no pills', (
      tester,
    ) async {
      await pumpEditor(tester);

      final card = tester.widget<SessionExerciseCard>(
        find.byType(SessionExerciseCard),
      );
      expect(
        card.flat,
        isTrue,
        reason:
            'the planner draws the Training page\'s card now — no fill, no '
            'border, the same 22pt gutter',
      );
      expect(
        card.onPrTap,
        isNull,
        reason: 'the flat card draws no PRs pill to wire — the floor owns it',
      );
      expect(card.onExerciseNotesTap, isNull);
      expect(
        find.text('Notes'),
        findsNothing,
        reason: 'and a flat card draws no Notes/History/PRs pills at all',
      );
    });

    testWidgets('a review keeps the floor, and the review bar is still the '
        'chrome', (tester) async {
      await pumpEditorInReview(tester);

      expect(
        floor(),
        findsOneWidget,
        reason:
            'planning inside a pass is still planning — the floor does not '
            'stand down for the review bar, it stands under it',
      );
      expect(find.byType(ReviewBar), findsOneWidget);
    });
  });

  // ── The floor's counts ───────────────────────────────────────────────────
  //
  // A tile's number has to name the feed behind it (2026-10-23), so the
  // planner's counts are read off the same shelves the doors open: every PR
  // the exercise ever landed — derived once, off the same timeline read that
  // fills the history — and every note it carries (2026-10-26).
  group('the floor\'s counts', () {
    PastSetRow pastSet({
      required String id,
      required String exerciseId,
      required num weight,
      required num reps,
      required DateTime when,
    }) => PastSetRow(
      sessionExerciseSetId: id,
      sessionExerciseId: 'se-$id',
      sessionId: 'sess-$id',
      userId: userId,
      setNumber: 1,
      reps: [reps],
      weight: weight.toDouble(),
      exerciseId: exerciseId,
      sessionCreatedDate: when,
    );

    test(
      'the trophy opens the exercise\'s own PRs, not the whole feed',
      () async {
        sessions.pastSets.addAll([
          pastSet(
            id: 'row-1',
            exerciseId: cableRowId,
            weight: 100,
            reps: 5,
            when: DateTime(2026, 10, 1),
          ),
          pastSet(
            id: 'row-2',
            exerciseId: benchPressId,
            weight: 80,
            reps: 5,
            when: DateTime(2026, 10, 3),
          ),
          // A later, heavier triple: a second PR for the cable row.
          pastSet(
            id: 'row-3',
            exerciseId: cableRowId,
            weight: 102.5,
            reps: 3,
            when: DateTime(2026, 10, 8),
          ),
        ]);

        await vm.loadHistoryIfNeeded();

        expect(vm.prCountFor(cableRowId), 2);
        expect(vm.prCountFor(benchPressId), 1);
        expect(
          vm.prHistoryFor(cableRowId).every((e) => e.exerciseId == cableRowId),
          isTrue,
          reason:
              'the trophy opens one exercise\'s shelf — a PR from another '
              'exercise has no place in it',
        );
        expect(
          vm.state.value.allPrEvents,
          hasLength(3),
          reason:
              'the engine ran once at load, over the same read that fills the '
              'history — the tiles never walk the timeline themselves',
        );
      },
    );

    test('the note tile counts the exercise\'s whole shelf', () async {
      notes.notes.addAll([
        ExerciseNote(
          exerciseNoteId: 'l-1',
          userId: userId,
          exerciseId: cableRowId,
          text: 'Elbows in',
          pinned: false,
          createdDate: DateTime(2026, 10, 1),
        ),
        ExerciseNote(
          exerciseNoteId: 'l-2',
          userId: userId,
          exerciseId: benchPressId,
          text: 'Pause at the chest',
          pinned: false,
          createdDate: DateTime(2026, 10, 2),
        ),
      ]);

      await vm.loadNotesFor(cableRowId);
      await vm.loadNotesFor(benchPressId);

      expect(vm.noteCountFor(cableRowId), 1);
      expect(vm.noteCountFor(benchPressId), 1);
      expect(
        vm.noteCountFor('ex-unknown'),
        0,
        reason:
            'an exercise with nothing written has an empty shelf, not an '
            'error',
      );
    });
  });

  // ── A removed exercise stays on the card ─────────────────────────────────
  //
  // Removing a group archives it (`dim_planned_session_exercise.is_archived`),
  // and the planner's reads drop archived groups — so a removal made during a
  // pass left nothing on screen to explain it, and explaining changes is what
  // a pass is for. Inside a review the editor reads the archived groups too
  // and draws them with the deleted chrome: the selector's red name, red
  // inert rows, and the note box still open under them (2026-10-26). Outside
  // a review the planner keeps hiding them, exactly as before.
  group('a removed exercise stays on the card', () {
    setUp(() {
      reviewSessionNotifier.value = null;
      reviewNotesNotifier.value = const {};
    });
    tearDown(() {
      reviewSessionNotifier.value = null;
      reviewNotesNotifier.value = const {};
    });

    const benchGroupId = 'pe-$benchPressId';

    /// One target row on Bench Press, then the group removed the way the
    /// picker removes one: the group and every row under it archived.
    Future<void> addBenchSetThenRemove() async {
      planned.sets.add(
        PlannedSessionExerciseSet(
          plannedSetId: 'pset-bench-1',
          plannedExerciseId: benchGroupId,
          plannedSessionId: sessionId,
          userId: userId,
          setNumber: 1,
          exerciseId: benchPressId,
          targetWeight: '60',
          targetReps: '10',
        ),
      );
      await planned.deletePlannedExercise(benchGroupId);
    }

    testWidgets('outside a review the removal leaves no card', (tester) async {
      await addBenchSetThenRemove();
      await pumpEditor(tester);

      final card = tester.widget<SessionExerciseCard>(
        find.byType(SessionExerciseCard),
      );
      expect(
        card.exerciseNames,
        ['Cable Row'],
        reason:
            'the planner keeps hiding archived groups — a review is the only '
            'reader that needs them back',
      );
      expect(card.deletedExercises, [false]);
    });

    testWidgets('a removal that predates the pass draws no card at all', (
      tester,
    ) async {
      // The user's report (2026-10-26): a Back Squat removed long ago came
      // back red on a workout that no longer contained it, because the
      // review's read brings back EVERY archived group. Only what the pass
      // itself removed is this pass's story.
      await addBenchSetThenRemove();
      await pumpEditorInReview(tester);

      final card = tester.widget<SessionExerciseCard>(
        find.byType(SessionExerciseCard),
      );
      expect(
        card.exerciseNames,
        ['Cable Row'],
        reason:
            'the review card shows the removals the pass made, never an old '
            'one the workout had already dropped',
      );
      expect(card.deletedExercises, [false]);
    });

    testWidgets('inside a review the removal stays — red inert rows and the '
        'note box still open', (tester) async {
      planned.sets.add(
        PlannedSessionExerciseSet(
          plannedSetId: 'pset-bench-1',
          plannedExerciseId: benchGroupId,
          plannedSessionId: sessionId,
          userId: userId,
          setNumber: 1,
          exerciseId: benchPressId,
          targetWeight: '60',
          targetReps: '10',
        ),
      );
      await pumpEditorInReview(tester);

      await vm.removePlannedExerciseGroup(1);
      await tester.pumpAndSettle();

      final card = tester.widget<SessionExerciseCard>(
        find.byType(SessionExerciseCard),
      );
      expect(
        card.exerciseNames,
        ['Cable Row', 'Bench Press'],
        reason:
            'the removed exercise stays where the reason for its removal is '
            'written; disappearing is what left the pass with nothing to say',
      );
      expect(card.deletedExercises, [
        false,
        true,
      ], reason: 'the selector draws the removed name in the deleted chrome');
      expect(
        vm.state.value.activeSlotIndex,
        0,
        reason: 'removing an exercise never yanks the card to another one',
      );

      await switchTo(tester, 'Bench Press');

      final row = tester.widget<Container>(
        find.byKey(const ValueKey('session-set-row-planned-set-1')),
      );
      expect(
        (row.decoration! as BoxDecoration).border!.top.color,
        AppColors.danger,
        reason: 'the rows under a removed exercise keep the deleted chrome',
      );
      final kg = tester.widget<TextField>(
        find.byKey(const ValueKey('planned-set-1-kg')),
      );
      expect(
        kg.readOnly,
        isTrue,
        reason: 'a removed target is read, never rewritten',
      );
      final note = tester.widget<LambdaInput>(
        find.widgetWithText(LambdaInput, 'Review Note'),
      );
      expect(
        note.onChanged,
        isNotNull,
        reason:
            'the note beside the removed exercise is the screen\'s whole '
            'reason for keeping it — the box has to take the words',
      );
    });

    testWidgets('the floor\'s trash lists the pass\'s removal, and Restore '
        'puts it back with its sets', (tester) async {
      planned.sets.add(
        PlannedSessionExerciseSet(
          plannedSetId: 'pset-bench-1',
          plannedExerciseId: benchGroupId,
          plannedSessionId: sessionId,
          userId: userId,
          setNumber: 1,
          exerciseId: benchPressId,
          targetWeight: '60',
          targetReps: '10',
        ),
      );
      await pumpEditorInReview(tester);
      await vm.removePlannedExerciseGroup(1);
      await tester.pumpAndSettle();

      // The trash is a door inside a pass now (2026-10-28), and its menu
      // names the group the pass removed.
      await tester.tap(find.byIcon(Icons.restore_from_trash));
      await tester.pumpAndSettle();
      final row = tester.widget<DeletedExerciseRow>(
        find.byType(DeletedExerciseRow),
      );
      expect(row.name, 'Bench Press');

      // A row opens it for reading: the card's tab follows, red as it is.
      await tester.tap(find.byType(DeletedExerciseRow));
      await tester.pumpAndSettle();
      expect(vm.state.value.activeSlotIndex, 1);
      expect(vm.state.value.activeSlot?.deleted, isTrue);

      // The menu is a list to work down, not a question — it stays open
      // after a pick, and its barrier takes the tap that leaves it.
      await tester.tapAt(const Offset(220, 300));
      await tester.pumpAndSettle();

      // The way back sits under the card: the live session's own Restore.
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SessionExerciseCard>(find.byType(SessionExerciseCard))
            .deletedExercises,
        [false, false],
        reason: 'the card stops drawing the group as removed',
      );
      expect(
        planned.exercises
            .firstWhere((e) => e.plannedExerciseId == benchGroupId)
            .isArchived,
        isFalse,
        reason: 'the group is un-archived in place, not copied back',
      );
      expect(
        planned.sets
            .firstWhere((s) => s.plannedSetId == 'pset-bench-1')
            .isArchived,
        isFalse,
        reason: 'every set under it comes back with it',
      );
      expect(
        find.text('Restore'),
        findsNothing,
        reason: 'the slot is no longer removed, so there is nothing to put '
            'back',
      );
      expect(
        find.byType(DeletedExerciseRow),
        findsNothing,
        reason: 'and the trash emptied itself',
      );
    });

    test('a discard puts back the removal the pass made, and leaves one the '
        'workout had already dropped', () async {
      // Bench Press was removed BEFORE the editor opened. Discard restores
      // the open-time state, so it must not resurrect that one — only the
      // group this editing session archived comes back.
      await addBenchSetThenRemove();
      await vm.openEditWorkout(
        PlannedSession(sessionId: sessionId, userId: userId, name: 'Psycho 1'),
        includeArchived: true,
      );
      List<String?> slotIds() => [
        for (final s in vm.state.value.workoutExerciseSlots)
          s.plannedExerciseId,
      ];
      expect(
        slotIds(),
        ['pe-$cableRowId'],
        reason:
            'a removal that predates the pass stays hidden — the card is '
            'the pass\'s own changes, not every old scar (2026-10-26)',
      );

      await vm.removePlannedExerciseGroup(0);
      expect(planned.exercises[0].isArchived, isTrue);
      expect(
        slotIds(),
        ['pe-$cableRowId'],
        reason:
            'the same slot list, for the opposite reason: the pass just '
            'removed this one, so it stays on the card, red',
      );

      await vm.discardWorkoutChanges();

      expect(
        planned.exercises[0].isArchived,
        isFalse,
        reason: 'the pass made that removal, so the rollback undoes it',
      );
      expect(
        planned.exercises[1].isArchived,
        isTrue,
        reason:
            'that removal was a fact when the editor opened — a discard '
            'restores the open-time state, it does not resurrect what the '
            'workout had already dropped',
      );
    });
  });

  // ── Undo/redo, moved to the floor ────────────────────────────────────────
  //
  // The pair lived in this screen's header. It cannot ride the review bar's
  // own row at 402pt: four workout glyphs leave the label slot exactly the
  // width 'Review Complete' needs (pinned by review_container_test's
  // geometry group), and two more controls would trade that line for an
  // ellipsis. Since the planner wears the session floor (2026-10-26) the pair
  // stands in that floor's own control row — undo/redo, the star, the tiles,
  // the live session's recipe — spent until an edit lands, and the header
  // keeps none.
  group('undo/redo inside a pass', () {
    setUp(() {
      reviewSessionNotifier.value = null;
      reviewWorkoutNotesNotifier.value = const {};
    });
    tearDown(() {
      reviewSessionNotifier.value = null;
      reviewWorkoutNotesNotifier.value = const {};
    });

    Finder pair() => find.byType(UndoRedoButtons);

    testWidgets('the header keeps none, and a fresh workout has the pair '
        'spent on the floor', (tester) async {
      await pumpEditorInReview(tester);

      expect(
        find.ancestor(
          of: pair(),
          matching: find.byKey(const ValueKey('plan-session-bar')),
        ),
        findsOneWidget,
        reason:
            'the pair is the floor\'s now (2026-10-26), the live session\'s '
            'recipe — the header keeps none',
      );
      final fresh = tester.widget<UndoRedoButtons>(pair());
      expect(
        fresh.canUndo,
        isFalse,
        reason: 'a fresh workout has nothing to step through',
      );
      expect(fresh.canRedo, isFalse);
      expect(
        find.descendant(of: find.byType(ReviewBar), matching: pair()),
        findsNothing,
        reason:
            'the bar\'s row is full: two more glyphs would ellipsize the '
            'line that says what state the pass is in',
      );
    });

    testWidgets('a structural edit lights the pair on the floor', (
      tester,
    ) async {
      await pumpEditorInReview(tester);

      await tester.tap(find.text('+ ADD SET'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<UndoRedoButtons>(pair()).canUndo,
        isTrue,
        reason: 'the edit is on the undo stack, and the pair is the way back',
      );
      expect(
        find.ancestor(
          of: pair(),
          matching: find.byKey(const ValueKey('plan-session-bar')),
        ),
        findsOneWidget,
        reason:
            'the pair stands in the floor\'s own row — undo/redo, the star '
            'and the tiles are one control row, the way the live session\'s '
            'floor draws them',
      );
      expect(
        find.descendant(of: find.byType(ReviewBar), matching: pair()),
        findsNothing,
        reason:
            'never into the review bar\'s row, which is full: two more '
            'glyphs would ellipsize the line that says what state the pass '
            'is in',
      );

      await tester.tap(
        find.descendant(of: pair(), matching: find.byIcon(Icons.undo)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('draft-1')),
        findsNothing,
        reason: 'undo stepped the set back off the card',
      );
      expect(
        tester.widget<UndoRedoButtons>(pair()).canRedo,
        isTrue,
        reason:
            'and the redo side lights — an undo that is stepped back is '
            'still a step',
      );
    });

    testWidgets('the bar keeps its whole line, the pair standing clear of '
        'it', (tester) async {
      // The width that decides where the pair lives: the bar's label slot is
      // what the four glyphs leave of 402pt, and 'Review Complete' is the
      // longest line it can wear. If the pair were in the row, this is the
      // assertion that would fail.
      await pumpEditorInReview(tester);
      await tester.tap(find.text('+ ADD SET'));
      await tester.pumpAndSettle();

      expect(pair(), findsOneWidget);
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(ReviewBar),
                matching: find.byType(AnimatedSwitcher),
              ),
            )
            .width,
        greaterThanOrEqualTo(_labelLineWidth(kReviewCompleteLabel)),
        reason:
            'the page\'s floor is what buys this room — the pair costs the '
            'label nothing',
      );
    });
  });
  // ── Discard leaves the editor ────────────────────────────────────────────
  //
  // The rollback is a chain of awaits (a rename, a delete, a set re-read).
  // The guard re-reads `hasUnsavedChanges` the moment the warning closes, so
  // an un-awaited rollback reads as "still dirty": the guard refuses the pop
  // it just offered, and the rollback finishes anyway — leaving the editor
  // standing on its spinner with no workout under it (2026-10-26).
  group('Discard leaves the editor', () {
    /// The editor pushed over a list, so a pop has somewhere to land and the
    /// test can tell "landed" from "stranded".
    Future<void> pumpListThenEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlanSessionScreen(
                        viewModel: vm,
                        workout: PlannedSession(
                          sessionId: sessionId,
                          userId: userId,
                          name: 'Psycho 1',
                        ),
                      ),
                    ),
                  ),
                  child: const Text('the list'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('the list'));
      await tester.pumpAndSettle();
    }

    testWidgets('a discard lands back on the list, not on a spinner', (
      tester,
    ) async {
      await pumpListThenEditor(tester);

      // A structural edit is the cheapest thing that makes the editor dirty.
      await tester.tap(find.text('+ ADD SET'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(
        find.byType(PlanSessionScreen),
        findsNothing,
        reason:
            'the pop is decided only after the rollback it offered has '
            'finished, so it actually happens',
      );
      expect(find.text('the list'), findsOneWidget);
    });
  });
}

/// Registers a bundled typeface with the test's font collection under the
/// family name the app asks for.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}

/// A bar label's own line width, painted with the real font — the room the
/// label slot has to hold whole. Painted rather than remembered, so the
/// assertion moves with the words (the same helper review_container_test
/// uses, where the four-glyph budget is pinned).
double _labelLineWidth(String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// The planner's reads and writes, in memory. Set rows are numbered per group
/// and hydrating `variationName` on read is kept, because that is what the
/// cell displays after a switch back — the assertion the user's report is
/// really about.
class _FakePlanned implements PlannedSessionRepository {
  _FakePlanned({required this.userId, required this.sessionId});

  final String userId;
  final String sessionId;

  final List<PlannedSessionExercise> exercises = [];
  final List<PlannedSessionExerciseSet> sets = [];

  /// Every set the editor asked to create, in order — the record the
  /// regression is read from.
  final List<PlannedSessionExerciseSet> created = [];

  int _counter = 0;

  void addExercise(
    String exerciseId, {
    required String name,
    required int order,
  }) {
    exercises.add(
      PlannedSessionExercise(
        plannedExerciseId: 'pe-$exerciseId',
        plannedSessionId: sessionId,
        userId: userId,
        exerciseId: exerciseId,
        exerciseName: name,
        exerciseOrder: order,
      ),
    );
  }

  Map<String, String> get _variationNames => const {
    'v-paused': 'Paused',
    'v-tempo': 'Tempo',
  };

  PlannedSessionExerciseSet _hydrate(PlannedSessionExerciseSet s) =>
      PlannedSessionExerciseSet(
        plannedSetId: s.plannedSetId,
        plannedExerciseId: s.plannedExerciseId,
        plannedSessionId: s.plannedSessionId,
        userId: s.userId,
        setNumber: s.setNumber,
        exerciseId: s.exerciseId,
        variationId: s.variationId,
        targetWeight: s.targetWeight,
        targetReps: s.targetReps,
        targetNotes: s.targetNotes,
        exerciseName: s.exerciseName,
        variationName: _variationNames[s.variationId],
        // The removal flag travels with the read, or the review editor's
        // red rows would come back as ordinary ones (2026-10-26).
        isArchived: s.isArchived,
      );

  /// The same row, archived or put back — the fake's soft delete/restore.
  PlannedSessionExercise _archive(PlannedSessionExercise e, bool value) =>
      PlannedSessionExercise(
        plannedExerciseId: e.plannedExerciseId,
        plannedSessionId: e.plannedSessionId,
        userId: e.userId,
        exerciseId: e.exerciseId,
        exerciseOrder: e.exerciseOrder,
        exerciseName: e.exerciseName,
        isArchived: value,
      );

  PlannedSessionExerciseSet _archiveSet(
    PlannedSessionExerciseSet s,
    bool value,
  ) => PlannedSessionExerciseSet(
    plannedSetId: s.plannedSetId,
    plannedExerciseId: s.plannedExerciseId,
    plannedSessionId: s.plannedSessionId,
    userId: s.userId,
    setNumber: s.setNumber,
    exerciseId: s.exerciseId,
    variationId: s.variationId,
    targetWeight: s.targetWeight,
    targetReps: s.targetReps,
    targetNotes: s.targetNotes,
    exerciseName: s.exerciseName,
    isArchived: value,
  );

  @override
  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async => [
    for (final e in exercises)
      if (includeArchived || !e.isArchived) e,
  ];

  @override
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async => [
    for (final s in sets)
      if (includeArchived || !s.isArchived) _hydrate(s),
  ];

  @override
  Future<List<PlannedSessionExerciseSet>> fetchNormalizedPlannedSets(
    String plannedSessionId,
  ) async => sets.map(_hydrate).toList();

  @override
  Future<List<PlannedSessionExerciseSet>> readNormalizedPlannedSession(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async {
    // A removed group keeps its rows; a set removed on its own stays hidden —
    // the repository's rule, mirrored (2026-10-26).
    final archivedGroups = {
      for (final e in exercises)
        if (e.isArchived) e.plannedExerciseId,
    };
    return [
      for (final s in sets)
        if (!includeArchived
            ? !s.isArchived
            : (!s.isArchived || archivedGroups.contains(s.plannedExerciseId)))
          _hydrate(s),
    ];
  }

  @override
  Future<void> deletePlannedExercise(String plannedExerciseId) async {
    for (var i = 0; i < exercises.length; i++) {
      if (exercises[i].plannedExerciseId == plannedExerciseId) {
        exercises[i] = _archive(exercises[i], true);
      }
    }
    for (var i = 0; i < sets.length; i++) {
      if (sets[i].plannedExerciseId == plannedExerciseId) {
        sets[i] = _archiveSet(sets[i], true);
      }
    }
  }

  @override
  Future<void> restorePlannedExercise(
    String plannedExerciseId, {
    required int exerciseOrder,
  }) async {
    for (var i = 0; i < exercises.length; i++) {
      if (exercises[i].plannedExerciseId == plannedExerciseId) {
        exercises[i] = _archive(exercises[i], false);
      }
    }
  }

  @override
  Future<void> restorePlannedSet(
    String plannedSetId, {
    required int setNumber,
  }) async {
    for (var i = 0; i < sets.length; i++) {
      if (sets[i].plannedSetId == plannedSetId) {
        sets[i] = _archiveSet(sets[i], false);
      }
    }
  }

  @override
  Future<PlannedSessionExerciseSet> createPlannedSet(
    String userId,
    String plannedExerciseId, {
    required String plannedSessionId,
    String? exerciseId,
    String? variationId,
    required int setNumber,
    String? targetWeight,
    String? targetReps,
    String? targetNotes,
  }) async {
    final group = exercises.firstWhere(
      (e) => e.plannedExerciseId == plannedExerciseId,
    );
    final set = PlannedSessionExerciseSet(
      plannedSetId: 'ps-${++_counter}',
      plannedExerciseId: plannedExerciseId,
      plannedSessionId: plannedSessionId,
      userId: userId,
      setNumber: setNumber,
      exerciseId: exerciseId ?? group.exerciseId,
      variationId: variationId,
      targetWeight: targetWeight,
      targetReps: targetReps,
      targetNotes: targetNotes,
      exerciseName: group.exerciseName,
    );
    sets.add(set);
    created.add(set);
    return set;
  }

  /// The rollback's first write, and the one the discard test turns on.
  ///
  /// It answers after a hop of its own, because a repository write is I/O: a
  /// fake that settled inside the same microtask would let an un-awaited
  /// rollback finish before the guard re-read the dirtiness it decides the
  /// pop on, and the regression test would pass with the bug still in place.
  @override
  Future<void> updatePlannedSession(
    String plannedSessionId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    String userId = '',
  }) async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExercises implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {
    'ex-cable-row': ExerciseDetail(
      exercise: CustomExercise(
        exerciseId: 'ex-cable-row',
        userId: userId,
        name: 'Cable Row',
      ),
    ),
    'ex-bench-press': ExerciseDetail(
      exercise: CustomExercise(
        exerciseId: 'ex-bench-press',
        userId: userId,
        name: 'Bench Press',
      ),
    ),
  };

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [
    CustomVariation(variationId: 'v-paused', userId: userId, name: 'Paused'),
    CustomVariation(variationId: 'v-tempo', userId: userId, name: 'Tempo'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only here because `ExerciseNoteRepository`'s constructor evaluates the global
/// `ps.db` — the one repository that cannot be default-constructed off-device.
/// The editor's notes reads — an in-memory shelf, so the floor's note tile
/// can be handed a count and the modal its rows (2026-10-26). Everything else
/// is the editor never calling it.
class _FakeNotes implements ExerciseNoteRepository {
  final List<ExerciseNote> notes = [];

  @override
  Future<List<ExerciseNote>> fetchNotes(String userId, String exerciseId) async => [
    for (final note in notes)
      if (note.exerciseId == exerciseId) note,
  ];

  @override
  Future<Map<String, List<ExerciseNote>>> fetchNotesForExercises(
    String userId,
    List<String> exerciseIds,
  ) async => {
    for (final id in exerciseIds)
      id: [
        for (final note in notes)
          if (note.exerciseId == id) note,
      ],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The editor's history read. Empty by default — the planner shows history
/// read-only — with a shelf a test can fill to put PRs behind the floor's
/// trophy (2026-10-26).
class _FakeSessions implements SessionRepository {
  final List<PastSetRow> pastSets = [];

  @override
  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async =>
      [...pastSets]
        ..sort((a, b) => b.sessionCreatedDate.compareTo(a.sessionCreatedDate));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
