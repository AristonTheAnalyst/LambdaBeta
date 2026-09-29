import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_exercise.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/programs/view/plan_session_screen.dart';
import 'package:lambda/features/programs/viewmodel/workout_editor_viewmodel.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';

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
  late WorkoutEditorViewModel vm;

  setUp(() {
    planned = _FakePlanned(userId: userId, sessionId: sessionId)
      ..addExercise(cableRowId, name: 'Cable Row', order: 1)
      ..addExercise(benchPressId, name: 'Bench Press', order: 2);
    vm = WorkoutEditorViewModel(
      exerciseRepo: _FakeExercises(),
      lessonRepo: _FakeLessons(),
      workoutRepo: _FakeSessions(),
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
    expect(planned.created, isEmpty,
        reason: 'picking a variation must not materialize a row on its own — '
            'a draft materializes when it commits, and it commits on blur or '
            'on a flush');

    // Leave the card, exactly as the user does.
    await switchTo(tester, 'Bench Press');

    expect(planned.created, hasLength(1),
        reason: 'the switch destroyed the row; the registered commit is the '
            'only thing that could have carried the pick out first');
    final written = planned.created.single;
    expect(written.exerciseId, cableRowId,
        reason: 'the row belongs to the exercise it was added under, not to '
            'the one the user switched to');
    expect(written.variationId, pausedVariationId);
    expect(written.targetWeight, isNull);
    expect(written.targetReps, isNull,
        reason: 'nothing was typed — the variation alone is what the user '
            'entered, and it is enough to make the set real');

    // And back, which is where the user saw the loss.
    await switchTo(tester, 'Cable Row');

    expect(find.byKey(ValueKey(written.plannedSetId)), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget,
        reason: 'the cell reads the variation back out of the database');
  });

  testWidgets('three empty drafts, three variations, one switch',
      (tester) async {
    // The report, at its own width: three sets, all three varied, then away.
    await pumpEditor(tester);

    await addDraftWithVariation(tester, 1, 'Paused');
    await addDraftWithVariation(tester, 2, 'Paused');
    await addDraftWithVariation(tester, 3, 'Tempo');

    await switchTo(tester, 'Bench Press');

    expect(planned.created, hasLength(3));
    expect(planned.created.map((s) => s.variationId),
        [pausedVariationId, pausedVariationId, 'v-tempo']);
    expect(planned.created.map((s) => s.setNumber), [1, 2, 3],
        reason: 'the flushed rows are numbered in the order the user built '
            'them — three cards\' worth of set numbers, not three first sets');
  });

  testWidgets('Save flushes a draft the user varied but never typed in',
      (tester) async {
    await pumpEditor(tester);

    await addDraftWithVariation(tester, 1, 'Paused');

    // Save's own pass writes one (empty) row per remaining draft. Without the
    // flush in front of it, that pass is what the varied draft becomes: an
    // empty row, and the pick is dropped on the floor.
    await vm.saveWorkout();

    expect(planned.created, hasLength(1));
    expect(planned.created.single.variationId, pausedVariationId,
        reason: 'the row Save wrote for this draft is the row the user '
            'described, variation included — and there is exactly one of it');
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

  void addExercise(String exerciseId, {required String name, required int order}) {
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
      );

  @override
  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId,
  ) async =>
      List.of(exercises);

  @override
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId,
  ) async =>
      sets.map(_hydrate).toList();

  @override
  Future<List<PlannedSessionExerciseSet>> fetchNormalizedPlannedSets(
    String plannedSessionId,
  ) async =>
      sets.map(_hydrate).toList();

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

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeExercises implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async =>
      {
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
        CustomVariation(
          variationId: 'v-paused',
          userId: userId,
          name: 'Paused',
        ),
        CustomVariation(
          variationId: 'v-tempo',
          userId: userId,
          name: 'Tempo',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Only here because `LessonRepository`'s constructor evaluates the global
/// `ps.db` — the one repository that cannot be default-constructed off-device.
class _FakeLessons implements LessonRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// The editor's history read. Empty is the honest answer for a fake: the
/// planner shows history read-only and nothing here depends on it.
class _FakeSessions implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
