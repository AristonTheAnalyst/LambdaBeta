import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/goals/view/goal_sheet.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';

/// The focused goal sheet — the notes box and the two history axes.
///
/// The sheet is the only surface that edits a description, and it rests in
/// view mode: looking at a goal must not be able to change it. Writes fire
/// per keystroke through a guard seeded from the stored value, so opening and
/// closing write nothing and A → B → A writes every step.
///
/// The axes are the PR lenses applied to the goal's own pair: every set that
/// raised the best reps at exactly the target weight, and every set that
/// raised the best weight at the target reps or better. The tests below pin
/// the two things that could go wrong quietly — the scoping (a set on another
/// weight, reps count or variation must not appear) and the read (a failed or
/// in-flight read must never render as "no sets").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces: the test font gives every glyph the same square
  // advance, so the sheet's rows measure wider than a device draws them.
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

  /// A logged set on the goal's own pair unless told otherwise.
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

  Goal goal({
    String? description,
    String? exerciseId = 'e1',
    String? variationId,
    num? targetWeight = 100,
    int? targetReps = 5,
  }) => Goal(
    goalId: 'g1',
    userId: 'u1',
    text: 'Bench',
    description: description,
    exerciseId: exerciseId,
    variationId: variationId,
    targetWeight: targetWeight,
    targetReps: targetReps,
  );

  /// Opens the sheet over a stubbed read and a recording writer, and hands
  /// back the descriptions that were written, in order.
  ///
  /// [writable] false opens it the way a **record** does — a null writer, the
  /// state a completed review's goal is read in. The list stays empty there
  /// for the same reason it exists: nothing can be written to it.
  Future<List<String>> openSheet(
    WidgetTester tester, {
    required Goal goal,
    Future<List<PastSetRow>> Function()? load,
    bool failWrite = false,
    bool writable = true,
  }) async {
    final writes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGoalSheet(
                  context,
                  goal: goal,
                  exerciseName: 'Bench',
                  onDescriptionChanged: writable
                      ? (text) async {
                          writes.add(text);
                          if (failWrite) {
                            throw StateError('description write failed');
                          }
                        }
                      : null,
                  loadPastSets: load ?? () async => const <PastSetRow>[],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return writes;
  }

  testWidgets('rests in view mode, seeded from the stored notes', (
    tester,
  ) async {
    final writes = await openSheet(
      tester,
      goal: goal(description: 'Beltless, pause on the chest'),
    );

    expect(find.byType(LambdaReadout), findsOneWidget);
    expect(find.text('Beltless, pause on the chest'), findsOneWidget);
    expect(find.byType(LambdaInput), findsNothing);
    // The summary row is the name and the target as the two things they are,
    // never the dash-joined string (2026-10-10).
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('100 kg × 5 reps'), findsOneWidget);
    expect(find.text('Bench — 100 kg × 5 reps'), findsNothing);
    expect(writes, isEmpty, reason: 'opening a goal must not be able to change it');
  });

  testWidgets('a goal with no notes offers to add one', (tester) async {
    await openSheet(tester, goal: goal());

    expect(find.text('Add a note…'), findsOneWidget);
    expect(find.byType(LambdaReadout), findsNothing);
  });

  // ── The record ────────────────────────────────────────────────────────────
  //
  // A completed review's goal opens the same sheet with no writer wired: the
  // report it would take is already made. The two states differ in what can be
  // *reached*, never in what is shown — the notes still read back, the axes
  // still stand on the history, and every way into edit mode is gone.
  testWidgets('a record reads the goal back whole, with no way into edit '
      'mode', (tester) async {
    await openSheet(
      tester,
      goal: goal(description: 'Beltless, pause on the chest'),
      writable: false,
      load: () async => [
        setRow(id: 'a', date: '2026-01-05', weight: 100, reps: [3]),
        setRow(id: 'b', date: '2026-03-05', weight: 100, reps: [6]),
      ],
    );

    // What the goal is, and what was said about it — all still here.
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('100 kg × 5 reps'), findsOneWidget);
    expect(find.text('Beltless, pause on the chest'), findsOneWidget);
    expect(find.byType(LambdaReadout), findsOneWidget);
    // The axes are the live history, and a record did not freeze them.
    expect(find.text('6 reps'), findsOneWidget);
    expect(find.text('100 kg × 6'), findsOneWidget);

    // Every door into writing is gone, not merely locked.
    expect(find.byType(LambdaInput), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Add a note…'), findsNothing);

    await tester.tap(find.byType(LambdaReadout));
    await tester.pumpAndSettle();
    expect(
      find.byType(LambdaInput),
      findsNothing,
      reason: 'the readout is inert — a record\'s tap opens nothing',
    );
  });

  testWidgets('a record that left nothing about the goal draws no notes '
      'section at all', (tester) async {
    await openSheet(tester, goal: goal(), writable: false);

    expect(
      find.text('NOTES'),
      findsNothing,
      reason: 'an empty header would only promise a note there is none of',
    );
    expect(find.text('Add a note…'), findsNothing);
    expect(find.byType(LambdaInput), findsNothing);
  });

  testWidgets('edit mode seeds the box and writes the whole text per keystroke', (
    tester,
  ) async {
    final writes = await openSheet(tester, goal: goal(description: 'Beltless'));
    await tester.tap(find.text('Beltless'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, 'Beltless');
    expect(writes, isEmpty, reason: 'entering edit mode is not an edit');

    await tester.enterText(field, 'Beltless, paus');
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Beltless, paused');
    await tester.pumpAndSettle();

    expect(writes, ['Beltless, paus', 'Beltless, paused']);
  });

  testWidgets('a keystroke that changes nothing writes nothing', (tester) async {
    final writes = await openSheet(tester, goal: goal(description: 'A'));
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    // The same text again — a real keystroke that left the value alone.
    tester.widget<LambdaInput>(find.byType(LambdaInput)).onChanged!('A');
    await tester.pumpAndSettle();

    expect(writes, isEmpty);
  });

  testWidgets('A → B → A writes every step', (tester) async {
    final writes = await openSheet(tester, goal: goal(description: 'A'));
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'AB');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pumpAndSettle();

    expect(
      writes,
      ['AB', 'A'],
      reason: 'going back to a value already written is still an edit',
    );
  });

  testWidgets('a failed write keeps the text and says so', (tester) async {
    final writes = await openSheet(tester, goal: goal(), failWrite: true);
    await tester.tap(find.text('Add a note…'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Slow off the chest');
    await tester.pumpAndSettle();

    expect(writes, ['Slow off the chest']);
    expect(find.text('Could not save the description.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Slow off the chest',
      reason: 'the box keeps what was typed',
    );

    // The guard did not advance, so the next keystroke carries the whole text
    // again — one failure cannot strand a half-written value.
    tester
        .widget<LambdaInput>(find.byType(LambdaInput))
        .onChanged!('Slow off the chest, hips too');
    await tester.pumpAndSettle();
    expect(writes, ['Slow off the chest', 'Slow off the chest, hips too']);

    // Let the SnackBar's own dismiss timer run out — a timer still pending
    // when the tree comes down fails the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('both axes run newest-first, newest emphasized, pair-scoped', (
    tester,
  ) async {
    await openSheet(
      tester,
      goal: goal(),
      load: () async => [
        setRow(id: 'a', date: '2026-01-05', weight: 100, reps: [3]),
        setRow(id: 'b', date: '2026-02-05', weight: 100, reps: [4]),
        setRow(id: 'c', date: '2026-03-05', weight: 100, reps: [6]),
        // A heavier set at the target reps — a rung on the reps axis only.
        setRow(id: 'd', date: '2026-04-05', weight: 105, reps: [5]),
        // Wrong variation, better reps at the target weight: the newest rung
        // on the weight axis if the pair were not scoped.
        setRow(
          id: 'x',
          date: '2026-05-05',
          weight: 100,
          reps: [9],
          variationId: 'v2',
        ),
        // Wrong exercise, same weight and better reps again.
        setRow(
          id: 'y',
          date: '2026-06-05',
          weight: 100,
          reps: [10],
          exerciseId: 'e2',
        ),
      ],
    );

    // The weight axis: 3 → 4 → 6 reps at 100 kg, newest on top.
    expect(
      tester.getTopLeft(find.text('6 reps')).dy,
      lessThan(tester.getTopLeft(find.text('4 reps')).dy),
    );
    expect(
      tester.getTopLeft(find.text('4 reps')).dy,
      lessThan(tester.getTopLeft(find.text('3 reps')).dy),
    );
    expect(
      tester.widget<Text>(find.text('6 reps')).style!.color,
      AppColors.accent,
      reason: 'the newest rung is the current best',
    );
    expect(
      tester.widget<Text>(find.text('4 reps')).style!.color,
      AppColors.muted,
    );

    // The reps axis: 100 kg then 105 kg at 5+ reps, newest on top.
    expect(
      tester.getTopLeft(find.text('105 kg × 5')).dy,
      lessThan(tester.getTopLeft(find.text('100 kg × 6')).dy),
    );
    expect(
      tester.widget<Text>(find.text('105 kg × 5')).style!.color,
      AppColors.accent,
    );
    expect(
      tester.widget<Text>(find.text('100 kg × 6')).style!.color,
      AppColors.muted,
    );

    // The one set both axes share, dated on each.
    expect(find.text('5 Mar'), findsNWidgets(2));

    expect(
      find.text('9 reps'),
      findsNothing,
      reason: 'a set on another variation is another scope',
    );
    expect(
      find.text('10 reps'),
      findsNothing,
      reason: 'a set on another exercise is another goal entirely',
    );
  });

  testWidgets('a weight-only goal shows only its weight axis', (tester) async {
    await openSheet(tester, goal: goal(targetReps: null));

    expect(find.text('AT 100 KG'), findsOneWidget);
    expect(find.textContaining('REPS'), findsNothing);
  });

  testWidgets('a text-only goal has no axes and never reads the timeline', (
    tester,
  ) async {
    var reads = 0;
    await openSheet(
      tester,
      goal: goal(
        exerciseId: null,
        targetWeight: null,
        targetReps: null,
        description: 'Read more',
      ),
      load: () async {
        reads++;
        return const <PastSetRow>[];
      },
    );

    expect(find.textContaining('AT '), findsNothing);
    expect(reads, 0, reason: 'there is no target to measure history against');
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('a failed read says so — never "no sets"', (tester) async {
    await openSheet(
      tester,
      goal: goal(),
      load: () async => throw StateError('timeline read failed'),
    );

    // One line per axis, because the sheet claims nothing per axis either.
    expect(find.text("Couldn't read your history."), findsNWidgets(2));
    expect(find.textContaining('No sets'), findsNothing);
  });

  testWidgets('a read still in flight reads as loading', (tester) async {
    final completer = Completer<List<PastSetRow>>();
    await openSheet(tester, goal: goal(), load: () => completer.future);
    expect(find.text('Loading…'), findsNWidgets(2));
    expect(find.textContaining('No sets'), findsNothing);

    completer.complete(const <PastSetRow>[]);
    await tester.pumpAndSettle();

    expect(find.text('No sets at 100 kg yet.'), findsOneWidget);
    expect(find.text('No sets of 5+ reps yet.'), findsOneWidget);
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
