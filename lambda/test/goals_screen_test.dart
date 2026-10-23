import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/core/styles/app_radius.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/goals/view/goals_screen.dart';
import 'package:lambda/features/goals/viewmodel/goals_viewmodel.dart';
import 'package:lambda/shared/widgets/container_styles.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/segmented_control.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

import 'support/fake_program_repos.dart';
import 'support/fake_session_repository.dart';

/// The goals library — every target the user is chasing, and the picker.
///
/// Goals live by themselves (2026-10-08): unattached, in the Library beside
/// Reviews, in force everywhere the exercise is trained. This replaced the
/// program's Goals tab, so the retired tab's test came with it — the add still
/// writes the user's own goal, on no scope — and the row behaviours the list
/// added are new: a lifetime standing, a tap that opens the sheet, and a
/// delete that lives behind the swipe drawer alone — it asks first, and the
/// card carries no × (2026-10-19).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces: Flutter's test font gives every glyph the same
  // square advance, so rows and the target picker measure far wider than a
  // device draws them.
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

  late FakeProgramRepository programs;
  late FakeExercises exercises;
  late FakeSessionRepository sessions;
  late GoalsViewModel vm;

  final details = {
    'e1': const ExerciseDetail(
      exercise: CustomExercise(exerciseId: 'e1', userId: 'u1', name: 'Bench'),
    ),
    'e2': const ExerciseDetail(
      exercise: CustomExercise(exerciseId: 'e2', userId: 'u1', name: 'Squat'),
    ),
  };

  Goal bench({String? description, DateTime? targetDate}) => Goal(
    goalId: 'g1',
    userId: 'u1',
    // The label's fallback — a goal outlives the exercise it names.
    text: 'Bench',
    description: description,
    exerciseId: 'e1',
    targetWeight: 100,
    targetReps: 5,
    targetDate: targetDate,
  );

  Goal squat() => Goal(
    goalId: 'g2',
    userId: 'u1',
    text: 'Squat',
    exerciseId: 'e2',
    targetWeight: 140,
    targetReps: 3,
  );

  PastSetRow setRow({
    required String id,
    required String date,
    double? weight,
    List<num>? reps,
    String exerciseId = 'e1',
    String? variationId,
  }) => PastSetRow(
    sessionExerciseSetId: id,
    sessionExerciseId: 'se-$id',
    sessionId: 's-$id',
    userId: 'u1',
    exerciseId: exerciseId,
    variationId: variationId,
    setNumber: 1,
    weight: weight,
    reps: reps ?? const [5],
    sessionCreatedDate: DateTime.parse(date),
  );

  setUp(() {
    programs = FakeProgramRepository(goals: [bench()]);
    exercises = FakeExercises()..details = details;
    sessions = FakeSessionRepository();
    vm = GoalsViewModel(
      programRepository: programs,
      exerciseRepository: exercises,
      sessionRepository: sessions,
      userId: 'u1',
    );
  });

  tearDown(() => vm.dispose());

  Future<void> pumpGoals(
    WidgetTester tester, {
    void Function(String sessionId)? openWorkout,
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    // The injected view model is not loaded by the screen — a host test owns
    // the state it hands in.
    await vm.load();
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: GoalsScreen(viewModel: vm, openWorkout: openWorkout),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens one exercise section. The list opens collapsed (2026-10-20), so a
  /// test that reads a card — or swipes one — has to open its section first.
  Future<void> openSection(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  /// Opens the New Goal sheet and composes Bench at [reps] × [kg]. The list
  /// is expected to be empty of that name, so the popover's row is the only
  /// "Bench" on screen.
  Future<void> composeBench(
    WidgetTester tester, {
    required String reps,
    required String kg,
  }) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-exercise-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('goal-reps')), reps);
    await tester.enterText(find.byKey(const ValueKey('goal-kg')), kg);
    await tester.pumpAndSettle();
  }

  testWidgets('renders each goal with its lifetime standing', (tester) async {
    // A set that met the target, heavier than it — the interesting hit.
    sessions.timeline = [
      setRow(id: 's1', date: '2026-03-05', weight: 105, reps: [5]),
    ];
    await pumpGoals(tester);
    await openSection(tester, 'Bench');

    // The card's main details (2026-10-19): the exercise header, its
    // variation header and the target — never the dash-joined string. The
    // target reads reps first, the session grid's own order (2026-10-20).
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('No Variation'), findsOneWidget);
    expect(find.text('100 kg × 5'), findsOneWidget);
    expect(find.text('Bench — 100 kg × 5'), findsNothing);

    // ...and a met goal states its completion alone (2026-10-20): the date
    // sits on the target's own line behind a green tick, and the deadline it
    // answered is not drawn — the card states one date, never both. The words
    // the symbols replaced are gone from the card.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('5 Mar 2026'), findsOneWidget);
    expect(find.byIcon(Icons.track_changes), findsNothing);
    expect(find.text('None'), findsNothing);
    expect(find.text('Target date'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(find.textContaining('Hit with'), findsNothing);

    // The whole card is one line (2026-10-20): the target and its date share
    // the row it starts, so the card stands one row tall.
    final cardLine = find
        .ancestor(of: find.text('100 kg × 5'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: cardLine, matching: find.text('5 Mar 2026')),
      findsOneWidget,
      reason: 'the dates sit beside the target, not under it',
    );

    // The card itself says it is done (2026-10-20): the New goal form's
    // achieved chrome, and no tick in the corner — the tick said it twice.
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Container && w.decoration == successBox(),
      ),
      findsOneWidget,
      reason: 'a met goal wears the green fill and green outline',
    );

    // The swipe wrapper clips at the card's own radius (2026-10-20): a larger
    // clip radius cut the border's corner arcs away, leaving the green edge
    // open at every corner.
    final wrapper = tester.widget<SwipeActions>(find.byType(SwipeActions));
    expect(wrapper.borderRadius, AppRadius.md);
  });

  testWidgets('a goal nothing has met says so, rather than showing zeroes', (
    tester,
  ) async {
    await pumpGoals(tester);
    await openSection(tester, 'Bench');

    // Still standing, so the card states the open question — the deadline —
    // and nothing about a completion (2026-10-20). This goal never had a
    // deadline, and the slot says 'None' rather than going blank; no tick, no
    // open ring (the card states one date, not a pair of slots), and no green
    // chrome.
    expect(find.text('Not yet'), findsNothing);
    expect(find.byIcon(Icons.track_changes), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Container && w.decoration == successBox(),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'a met goal states its completion, not the deadline it answered',
    (tester) async {
      // Met on 5 March, parked on a deadline months later: the card answers
      // the question that is settled — the one date it shows — and never
      // states both (2026-10-20).
      programs.goals = [bench(targetDate: DateTime(2026, 11, 1))];
      sessions.timeline = [
        setRow(id: 's1', date: '2026-03-05', weight: 105, reps: [5]),
      ];
      await pumpGoals(tester);
      await openSection(tester, 'Bench');

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('5 Mar 2026'), findsOneWidget);
      expect(
        find.text('1 Nov 2026'),
        findsNothing,
        reason: 'the deadline was answered — it is not stated again',
      );
      expect(find.byIcon(Icons.track_changes), findsNothing);
    },
  );

  testWidgets('an empty library says what a goal is', (tester) async {
    programs.goals = [];
    await pumpGoals(tester);

    expect(find.text('No goals yet'), findsOneWidget);
    expect(find.text('Tap + to set a weight × reps target.'), findsOneWidget);
  });

  testWidgets('adding a target writes the user\'s own goal, on no scope', (
    tester,
  ) async {
    programs.goals = [];
    await pumpGoals(tester);

    // The + opens the add sheet on the session-style composer (2026-10-19):
    // the exercise dropdown, then one set row under the session's own column
    // labels, notes beneath it, and ADD at the floor.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('REPS'), findsOneWidget);
    expect(find.text('KG'), findsOneWidget);
    expect(find.text('VARIATION'), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);

    // The exercise is a dropdown over the screen: the field asks for a pick,
    // and the catalog arrives in its popover — not in the form.
    expect(find.text('Pick exercise'), findsOneWidget);
    expect(find.text('Bench'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('goal-exercise-selector')));
    await tester.pumpAndSettle();

    // Pick the exercise — the popover closes onto the field's name.
    await tester.tap(find.text('Bench'));
    await tester.pumpAndSettle();
    expect(find.text('Pick exercise'), findsNothing);
    expect(find.text('Bench'), findsOneWidget);

    // One target, typed into the set row's own cells; the notes are the
    // goal's description.
    await tester.enterText(find.byKey(const ValueKey('goal-reps')), '5');
    await tester.enterText(find.byKey(const ValueKey('goal-kg')), '100');
    await tester.enterText(
      find.byType(LambdaInput),
      'Beltless, pause on the chest',
    );
    await tester.tap(find.text('ADD'));
    await tester.pumpAndSettle();

    expect(programs.createdGoals, hasLength(1));
    final goal = programs.createdGoals.single;
    expect(
      goal.programId,
      isNull,
      reason:
          'a goal is a set to beat — filing it to a program would put it '
          'in force during runs it has nothing to do with',
    );
    expect(goal.blockId, isNull);
    expect(goal.text, 'Bench');
    expect(goal.targetWeight, 100);
    expect(goal.targetReps, 5);
    expect(
      goal.description,
      'Beltless, pause on the chest',
      reason:
          'the form\'s notes are the goal\'s notes from the moment it exists',
    );

    // ...and it shows up in the list it was added from, with no reload: the
    // reload after a create reads the same library the list displays, and the
    // section it landed in opened with it (2026-10-20) — the write's echo,
    // rather than a new goal behind a collapsed header.
    expect(find.text('100 kg × 5'), findsOneWidget);
  });

  testWidgets('the exercise picker opens on what was trained last', (
    tester,
  ) async {
    programs.goals = [];
    // Squat was trained after Bench, so it is the row the picker offers
    // first — the catalog is ordered by recency, not by name (2026-10-19).
    sessions.timeline = [
      setRow(id: 's1', date: '2026-03-05', exerciseId: 'e1'),
      setRow(id: 's2', date: '2026-06-01', exerciseId: 'e2'),
    ];
    await pumpGoals(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-exercise-selector')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Squat')).dy,
      lessThan(tester.getTopLeft(find.text('Bench')).dy),
    );
  });

  testWidgets('the variation picker opens on what was trained last', (
    tester,
  ) async {
    exercises.variations = const [
      CustomVariation(variationId: 'v1', userId: 'u1', name: 'Incline'),
      CustomVariation(variationId: 'v2', userId: 'u1', name: 'Paused'),
    ];
    // Paused was trained after Incline — recency outranks the alphabet.
    sessions.timeline = [
      setRow(id: 's1', date: '2026-03-05', variationId: 'v1'),
      setRow(id: 's2', date: '2026-06-01', variationId: 'v2'),
    ];
    await pumpGoals(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    // The variation cell's placeholder opens the picker in place — scoped to
    // the picker's own set row, since a card on the list behind the sheet
    // names its variation too (2026-10-19).
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('goal-set-row')),
        matching: find.text('No Variation'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Paused')).dy,
      lessThan(tester.getTopLeft(find.text('Incline')).dy),
    );
  });

  testWidgets('search narrows the list, and a miss says so', (tester) async {
    await pumpGoals(tester);

    await tester.enterText(find.byType(TextField), 'squat');
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsNothing);
    expect(find.text('No goals match'), findsOneWidget);
    expect(find.text('Nothing for "squat".'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bench');
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsOneWidget);
  });

  testWidgets('the filter narrows to complete and not complete, one control', (
    tester,
  ) async {
    programs.goals = [bench(), squat()];
    // Only the bench goal has been met.
    sessions.timeline = [
      setRow(id: 's1', date: '2026-03-05', weight: 105, reps: [5]),
    ];
    await pumpGoals(tester);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    expect(find.text('Filter goals'), findsOneWidget);

    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsNothing);
    expect(find.text('Squat'), findsOneWidget);

    // All goes back to the whole library, from the same control. Scoped to
    // the control: each date row also says "All" while it is not narrowing.
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedControl<GoalStatus>),
        matching: find.text('All'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
  });

  testWidgets('the two date filters narrow by their own clock', (tester) async {
    final today = dateOnly(DateTime.now());
    final longAgo = today.subtract(const Duration(days: 100));
    programs.goals = [
      // Bench: due today.
      Goal(
        goalId: 'g1',
        userId: 'u1',
        text: 'Bench',
        exerciseId: 'e1',
        targetWeight: 100,
        targetReps: 5,
        targetDate: today,
        createdDate: today,
      ),
      // Squat: due long ago, and never completed.
      Goal(
        goalId: 'g2',
        userId: 'u1',
        text: 'Squat',
        exerciseId: 'e2',
        targetWeight: 140,
        targetReps: 3,
        targetDate: longAgo,
        createdDate: longAgo,
      ),
    ];
    // The bench was met long ago, so a last-month completion window holds
    // neither goal.
    sessions.timeline = [
      setRow(id: 's1', date: '2026-03-05', weight: 105, reps: [5]),
    ];
    await pumpGoals(tester);

    Future<void> applyLastMonth(String rowKey) async {
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(rowKey)));
      await tester.pumpAndSettle();
      // The shared range sheet opens over the filter sheet.
      await tester.tap(find.text('1M'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }

    Future<void> clear() async {
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }

    // A deadline window: only the goal due inside it survives.
    await applyLastMonth('goal-filter-target-date');
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);

    await clear();
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);

    // A completion window: nothing was completed last month, so nothing
    // matches — a goal with no completion cannot be inside one.
    await applyLastMonth('goal-filter-completed-date');
    expect(find.text('No goals match'), findsOneWidget);

    await clear();
    expect(find.text('Bench'), findsOneWidget);

    // The written date stopped being a question (2026-10-20): the sheet
    // offers the lifts, status, the deadline and the completion, nothing
    // else.
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    expect(find.text('EXERCISES'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('TARGET DATE'), findsOneWidget);
    expect(find.text('COMPLETED DATE'), findsOneWidget);
    expect(find.text('CREATED DATE'), findsNothing);
    expect(
      find.byKey(const ValueKey('goal-filter-created-date')),
      findsNothing,
    );

    // The sheet asks in this order (2026-10-20): the lifts, then how a goal
    // stands, then its two dates.
    double top(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(top('EXERCISES'), lessThan(top('STATUS')));
    expect(top('STATUS'), lessThan(top('TARGET DATE')));
    expect(top('TARGET DATE'), lessThan(top('COMPLETED DATE')));
  });

  testWidgets('the exercise field narrows the list through the shared picker', (
    tester,
  ) async {
    programs.goals = [bench(), squat()];
    await pumpGoals(tester);

    Finder row(String name) =>
        find.descendant(of: find.byType(ListView), matching: find.text(name));

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();

    // The exercise half is a field, not a shelf of ticks (2026-10-20): it
    // states the unfiltered reading and opens the session's own add/remove
    // picker — searchable, tick-to-select, staying up across taps.
    expect(find.text('All exercises'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-filter-exercises')));
    await tester.pumpAndSettle();
    expect(find.text('Select Exercises'), findsOneWidget);

    // The picker opens on its list, not the keyboard (2026-10-20): this sheet
    // is opened to tick what is already there, so the keyboard would cover
    // the exercises it came to show. Focus waits for a tap on the field.
    final searchField = find.descendant(
      of: find.byKey(const ValueKey('add-exercise-search')),
      matching: find.byType(EditableText),
    );
    EditableText search() => tester.widget<EditableText>(searchField);
    expect(
      search().focusNode.hasFocus,
      isFalse,
      reason: 'opening the picker must not raise the keyboard',
    );
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(
      search().focusNode.hasFocus,
      isTrue,
      reason: 'a tap on the search field is what opens the keyboard',
    );

    // Search narrows the picker to the lift being looked for.
    await tester.enterText(
      find.byKey(const ValueKey('add-exercise-search')),
      'squ',
    );
    await tester.pumpAndSettle();
    expect(row('Squat'), findsOneWidget);
    expect(row('Bench'), findsNothing);

    await tester.tap(row('Squat'));
    await tester.pumpAndSettle();
    // Multi-select: clearing the query ticks the second lift too, and the
    // sheet has stayed up across both taps.
    await tester.enterText(
      find.byKey(const ValueKey('add-exercise-search')),
      '',
    );
    await tester.pumpAndSettle();
    await tester.tap(row('Bench'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(
      find.text('2 exercises'),
      findsOneWidget,
      reason: 'the field answers what is narrowed, not what was clicked last',
    );

    // One lift is a narrowing the list obeys.
    await tester.tap(find.byKey(const ValueKey('goal-filter-exercises')));
    await tester.pumpAndSettle();
    await tester.tap(row('Bench'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal-filter-exercises')),
        matching: find.text('Squat'),
      ),
      findsOneWidget,
      reason: 'the field names the one lift left ticked',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsNothing);
    expect(find.text('Squat'), findsOneWidget);

    // An untick is a removal, from the same picker.
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-filter-exercises')));
    await tester.pumpAndSettle();
    await tester.tap(row('Squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('All exercises'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
  });

  testWidgets('sort orders the list, and re-picking the criterion flips it', (
    tester,
  ) async {
    programs.goals = [bench(), squat()];
    await pumpGoals(tester);

    // The default order is by exercise (2026-10-20). Neither goal has a
    // deadline, so both sections are open and undated, and they read A–Z —
    // Bench first.
    expect(
      tester.getTopLeft(find.text('Bench')).dy,
      lessThan(tester.getTopLeft(find.text('Squat')).dy),
    );

    // Name reads the same way here...
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Bench')).dy,
      lessThan(tester.getTopLeft(find.text('Squat')).dy),
    );

    // The same criterion again answers the same question the other way.
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Squat')).dy,
      lessThan(tester.getTopLeft(find.text('Bench')).dy),
    );

    // Recently added reads newest first — squat was written after bench.
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently added'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Squat')).dy,
      lessThan(tester.getTopLeft(find.text('Bench')).dy),
    );
  });

  testWidgets('the default order reads by exercise: open deadlines first, '
      'completed work last', (tester) async {
    // Four goals on three lifts, chosen so every rule of the default order
    // (2026-10-20) has something to say:
    //   Squat    — open, due soonest.
    //   Bench    — open but due later, and holding a completed goal whose
    //              deadline is EARLIER than the squat's — history must not
    //              order the shelf.
    //   Deadlift — only a completed goal, so its section trails everything.
    programs.goals = [
      // Written first, so repository order alone would put squat anywhere.
      Goal(
        goalId: 'g2',
        userId: 'u1',
        text: 'Squat',
        exerciseId: 'e2',
        targetWeight: 140,
        targetReps: 3,
        targetDate: DateTime(2026, 11, 1),
      ),
      Goal(
        goalId: 'g1',
        userId: 'u1',
        text: 'Bench',
        exerciseId: 'e1',
        targetWeight: 100,
        targetReps: 5,
        targetDate: DateTime(2026, 12, 1),
      ),
      Goal(
        goalId: 'g3',
        userId: 'u1',
        text: 'Bench',
        exerciseId: 'e1',
        targetWeight: 60,
        targetReps: 8,
        targetDate: DateTime(2026, 1, 5),
      ),
      Goal(
        goalId: 'g4',
        userId: 'u1',
        text: 'Deadlift',
        exerciseId: 'e3',
        targetWeight: 180,
        targetReps: 1,
        targetDate: DateTime(2026, 1, 1),
      ),
    ];
    // The two completed goals are met; the open ones are not.
    sessions.timeline = [
      setRow(id: 's1', date: '2026-03-05', weight: 65, reps: [8]),
      setRow(
        id: 's2',
        date: '2026-03-05',
        weight: 185,
        reps: [1],
        exerciseId: 'e3',
      ),
    ];
    await pumpGoals(tester);

    // The shelf: the open, dated sections lead — soonest deadline first —
    // and the section whose goals are all done trails, however early its
    // deadline was.
    final squatY = tester.getTopLeft(find.text('Squat')).dy;
    final benchY = tester.getTopLeft(find.text('Bench')).dy;
    final deadliftY = tester.getTopLeft(find.text('Deadlift')).dy;
    expect(
      squatY,
      lessThan(benchY),
      reason: 'the squat\'s open deadline (1 Nov) is sooner than the bench\'s',
    );
    expect(
      benchY,
      lessThan(deadliftY),
      reason:
          'a completed goal\'s deadline is history — the all-done section '
          'trails, even due 1 Jan',
    );

    // Inside a section the open goal leads and the completed one follows,
    // though the completed goal's deadline is the earlier of the two.
    await openSection(tester, 'Bench');
    expect(
      tester.getTopLeft(find.text('100 kg × 5')).dy,
      lessThan(tester.getTopLeft(find.text('60 kg × 8')).dy),
      reason: 'unfinished work first; the completed goal is read after',
    );

    // Re-picking the criterion flips the deadline reading, and only that:
    // the bench's later deadline now leads the squat, while the done section
    // stays at the floor and the open goal stays above the done one.
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('By exercise'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Bench')).dy,
      lessThan(tester.getTopLeft(find.text('Squat')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Squat')).dy,
      lessThan(tester.getTopLeft(find.text('Deadlift')).dy),
    );
    expect(
      tester.getTopLeft(find.text('100 kg × 5')).dy,
      lessThan(tester.getTopLeft(find.text('60 kg × 8')).dy),
      reason: 'completion is not a direction — it never flips',
    );
  });

  testWidgets('the list is sectioned by exercise, and its headers stay pinned '
      'until the next section takes the top', (tester) async {
    // Both sections are open and undated, so the default order reads them A–Z
    // — Bench's section first — and inside Bench the undated goals keep the
    // repository's order (2026-10-20). Many goals in each is what gives the
    // headers room to pin, and the second section enough height to carry the
    // first away. The squat section is the long one because a card is a
    // single row tall since 2026-10-20: eight of them no longer reach past a
    // viewport, and a section can only pin while its own cards keep coming
    // under it.
    programs.goals = [
      squat(),
      for (var i = 0; i < 20; i++)
        Goal(
          goalId: 's$i',
          userId: 'u1',
          text: 'Squat',
          exerciseId: 'e2',
          targetWeight: 200 + i,
          targetReps: 3,
        ),
      for (var i = 0; i < 8; i++)
        Goal(
          goalId: 'b$i',
          userId: 'u1',
          text: 'Bench',
          exerciseId: 'e1',
          targetWeight: 100 + i,
          targetReps: 5,
        ),
    ];
    await pumpGoals(tester);

    // The shelf opens collapsed (2026-10-20); open the section under test.
    await openSection(tester, 'Bench');

    // The hierarchy reads exercise → variation → card, in that order.
    final benchHeader = find.text('Bench');
    final benchVariation = find.text('No Variation').first;
    expect(
      tester.getTopLeft(benchHeader).dy,
      lessThan(tester.getTopLeft(benchVariation).dy),
    );
    expect(
      tester.getTopLeft(benchVariation).dy,
      lessThan(tester.getTopLeft(find.text('100 kg × 5')).dy),
      reason:
          'the first-written goal is the section\'s first card — undated '
          'open goals keep repository order — under both headers',
    );

    // Mid-section both headers pin: the list scrolls a full 150 while the
    // exercise header holds the top and the variation keeps its place under
    // it, rather than scrolling away with the cards.
    final listTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    final benchBefore = tester.getTopLeft(benchHeader).dy;
    final variationGap = tester.getTopLeft(benchVariation).dy - benchBefore;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();
    final benchAfter = tester.getTopLeft(benchHeader).dy;
    expect(
      benchBefore - benchAfter,
      lessThan(40),
      reason: 'the exercise header holds the top while the list scrolls',
    );
    expect(
      tester.getTopLeft(benchVariation).dy - benchAfter,
      closeTo(variationGap, 0.5),
      reason: 'the variation pins under its exercise, not over it',
    );

    // The next exercise's section takes the top, carrying Bench's away. That
    // section is opened first — an expanded section is what gives its header
    // content to scroll under and hold at the top.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    await openSection(tester, 'Squat');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Squat')).dy - listTop,
      lessThan(40),
      reason: 'the next section\'s header now holds the top',
    );
    expect(
      benchHeader,
      findsNothing,
      reason: 'the section that ended is gone from the top of the list',
    );
  });

  testWidgets('a section opens on a tap, and the list opens collapsed', (
    tester,
  ) async {
    programs.goals = [bench(), squat()];
    await pumpGoals(tester);

    // The default reading is a shelf of exercises (2026-10-20): headers with
    // a downward arrow, and no cards until one is asked for.
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('100 kg × 5'), findsNothing);
    expect(find.text('140 kg × 3'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsNWidgets(2));
    expect(find.byIcon(Icons.expand_less), findsNothing);

    // A tap opens one section — its card arrives, its arrow turns up and the
    // other stays closed.
    await openSection(tester, 'Bench');
    expect(find.text('100 kg × 5'), findsOneWidget);
    expect(find.text('140 kg × 3'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // The same tap closes it again.
    await openSection(tester, 'Bench');
    expect(find.text('100 kg × 5'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('the card carries no ×, and the question names the goal', (
    tester,
  ) async {
    await pumpGoals(tester);
    await openSection(tester, 'Bench');

    // Deleting is the swipe drawer's alone (2026-10-19): the card offers no
    // one-tap control, so the gesture is the only way in.
    expect(find.byIcon(Icons.close), findsNothing);

    // The question itself still stands behind the drawer.
    await tester.drag(find.text('100 kg × 5'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete this goal?'), findsOneWidget);
    expect(
      find.text(
        '"Bench" is removed from your goals. Your logged sets stay in '
        'Training Logs. This can\'t be undone.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Keep goal'));
    await tester.pumpAndSettle();

    expect(
      programs.deletedGoals,
      isEmpty,
      reason:
          'the drawer only opens the question — a kept goal is never '
          'written away',
    );
    expect(find.text('100 kg × 5'), findsOneWidget);
  });

  testWidgets('swiping a goal asks first, and a confirmed delete removes it', (
    tester,
  ) async {
    await pumpGoals(tester);
    await openSection(tester, 'Bench');

    await tester.drag(find.text('100 kg × 5'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete this goal?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Keep goal'));
    await tester.pumpAndSettle();
    expect(
      programs.deletedGoals,
      isEmpty,
      reason: 'the swipe only reveals the verb — the dialog decides',
    );

    // Reopen and answer yes.
    await tester.drag(find.text('100 kg × 5'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete goal'));
    await tester.pumpAndSettle();

    expect(programs.deletedGoals, ['g1']);
    expect(find.text('100 kg × 5'), findsNothing);
  });

  testWidgets('tapping a goal opens its sheet resting; Edit unlocks it and '
      'SAVE writes the row', (tester) async {
    await pumpGoals(tester);
    await openSection(tester, 'Bench');

    await tester.tap(find.text('100 kg × 5'));
    await tester.pumpAndSettle();

    // The same form the New goal sheet composes, resting: the notes are one
    // of the goal's fields now, not an invite to start writing.
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('Add a note…'), findsNothing);
    expect(find.text('SAVE'), findsOneWidget);
    expect(
      programs.goalWrites,
      isEmpty,
      reason: 'opening a goal must not be able to change it',
    );

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      // The sheet's own input — the toolbar's search box is still in the tree
      // behind the modal, so "the only TextField" is no longer the note.
      find.byType(LambdaInput),
      'Beltless, pause on the chest',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(programs.goalWrites, hasLength(1));
    final write = programs.goalWrites.single;
    expect(write.goalId, 'g1');
    expect(write.exerciseId, 'e1');
    expect(write.exerciseName, 'Bench');
    expect(write.targetWeight, 100);
    expect(write.targetReps, 5);
    expect(write.description, 'Beltless, pause on the chest');
    expect(
      vm.state.value.goals.single.description,
      'Beltless, pause on the chest',
      reason: 'the row mirrors the write, so the next open shows the notes',
    );
  });

  testWidgets('a target the history already beats turns the row green and '
      'names the day', (tester) async {
    programs.goals = [];
    // 105 × 5 is at or above the 100 × 5 about to be typed — the interesting
    // hit, heavier than the target.
    sessions.timeline = [
      setRow(id: 's9', date: '2026-03-05', weight: 105, reps: [5]),
    ];
    await pumpGoals(tester);
    await composeBench(tester, reps: '5', kg: '100');

    expect(find.text("You've already beat this on 5 Mar 2026"), findsOneWidget);
    final row = tester.widget<Container>(
      find.byKey(const ValueKey('goal-set-row')),
    );
    expect(
      row.decoration,
      successBox(),
      reason:
          'the achieved chrome is the deleted box in success — the green '
          'fill and a full-strength edge, one recipe',
    );
  });

  testWidgets('a target the history has not reached stays bare', (
    tester,
  ) async {
    programs.goals = [];
    // 90 × 5 is short of the 100 × 5 about to be typed — no claim either way.
    sessions.timeline = [
      setRow(id: 's9', date: '2026-03-05', weight: 90, reps: [5]),
    ];
    await pumpGoals(tester);
    await composeBench(tester, reps: '5', kg: '100');

    expect(find.textContaining("You've already beat this"), findsNothing);
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('goal-set-row')))
          .decoration,
      isNot(successBox()),
    );
  });

  testWidgets('tapping the sentence opens the workout, and the form waits '
      'under it', (tester) async {
    programs.goals = [];
    sessions.timeline = [
      setRow(id: 's9', date: '2026-03-05', weight: 105, reps: [5]),
    ];
    final opened = <String>[];
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpGoals(
      tester,
      navigatorKey: navigatorKey,
      openWorkout: (id) {
        opened.add(id);
        // The real host pushes the logs route on the root navigator, which
        // covers the sheet without dismissing it — exactly what this pushes.
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('the workout'))),
          ),
        );
      },
    );
    await composeBench(tester, reps: '5', kg: '100');

    await tester.tap(find.byKey(const ValueKey('goal-already-achieved')));
    await tester.pumpAndSettle();

    expect(opened, [
      's-s9',
    ], reason: 'the sentence opens the session that logged the set');
    expect(find.text('the workout'), findsOneWidget);

    // Back lands on the form, not on the list: the sheet was covered, never
    // dismissed, and the draft filled it in again.
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('the workout'), findsNothing);
    expect(find.text('ADD'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('goal-kg')))
          .controller
          ?.text,
      '100',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('goal-reps')))
          .controller
          ?.text,
      '5',
    );
  });

  testWidgets('dismissing the add sheet keeps what was typed', (tester) async {
    programs.goals = [];
    await pumpGoals(tester);
    await composeBench(tester, reps: '5', kg: '100');
    await tester.enterText(find.byType(LambdaInput), 'Beltless');

    // A tap outside dismisses the sheet, and nothing was written.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('ADD'), findsNothing);
    expect(programs.createdGoals, isEmpty);

    // Reopening finds the form exactly as it was left.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal-exercise-selector')),
        matching: find.text('Bench'),
      ),
      findsOneWidget,
      reason: 'the exercise pick survived the dismissal',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('goal-kg')))
          .controller
          ?.text,
      '100',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('goal-reps')))
          .controller
          ?.text,
      '5',
    );
    expect(find.text('Beltless'), findsOneWidget);
  });

  testWidgets('the target date sits under the notes, and ADD writes the day', (
    tester,
  ) async {
    programs.goals = [];
    await pumpGoals(tester);
    await composeBench(tester, reps: '5', kg: '100');

    expect(
      tester.getTopLeft(find.text('TARGET DATE')).dy,
      greaterThan(tester.getTopLeft(find.text('NOTES')).dy),
      reason: 'the date comes after the notes (2026-10-19)',
    );

    // The field asks for a date; the app's own calendar opens over the sheet,
    // and Apply takes the day it opened on.
    expect(find.text('No target date'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-target-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final today = dateOnly(DateTime.now());
    expect(find.text(DateFormat('d MMM yyyy').format(today)), findsOneWidget);

    await tester.tap(find.text('ADD'));
    await tester.pumpAndSettle();

    expect(programs.createdGoals.single.targetDate, today);
    expect(
      find.byIcon(Icons.track_changes),
      findsOneWidget,
      reason: 'the card marks the deadline it was given',
    );
    expect(find.text(DateFormat('d MMM yyyy').format(today)), findsOneWidget);
  });

  testWidgets('a goal reads and moves its deadline, and the move is kept', (
    tester,
  ) async {
    programs.goals = [bench(targetDate: DateTime(2026, 11, 1))];
    await pumpGoals(tester);
    await openSection(tester, 'Bench');
    expect(find.byIcon(Icons.track_changes), findsOneWidget);
    expect(find.text('1 Nov 2026'), findsOneWidget);

    await tester.tap(find.text('100 kg × 5'));
    await tester.pumpAndSettle();
    // Scoped to the field: the card behind the sheet still states the same
    // day, so the bare text matches both.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal-target-date')),
        matching: find.text('1 Nov 2026'),
      ),
      findsOneWidget,
      reason: 'the sheet reads the stored deadline',
    );
    expect(find.text('TARGET DATE'), findsOneWidget);

    // The × is the way back to no deadline — but it edits the draft, not the
    // row: nothing is written until SAVE.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-date-clear')));
    await tester.pumpAndSettle();
    expect(find.text('No target date'), findsOneWidget);
    expect(
      programs.goalWrites,
      isEmpty,
      reason: 'a change that was never saved is not a fact',
    );

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(programs.goalWrites, hasLength(1));
    expect(programs.goalWrites.single.targetDate, isNull);
    expect(
      vm.state.value.goals.single.targetDate,
      isNull,
      reason: 'the row mirrors the cleared deadline',
    );
    // The read-back row remembers the move, and the VM mirrors it — the move
    // itself now reads behind the sheet's history button.
    final history = vm.state.value.goals.single.targetDateHistory;
    expect(history, hasLength(1));
    expect(history.single.from, DateTime(2026, 11, 1));
    expect(history.single.to, isNull);
  });
}

/// Registers a bundled typeface under the family name the app asks for.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}
