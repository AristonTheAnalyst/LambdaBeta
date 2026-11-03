import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/goals/view/goal_sheet.dart';
import 'package:lambda/shared/widgets/exercise_target_picker.dart';
import 'package:lambda/shared/widgets/glass_button.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/readable_text.dart';

/// The focused goal sheet — the same form the New goal sheet composes,
/// resting (2026-10-19).
///
/// Previewing a goal and creating one are the same act from two sides: the
/// sheet draws the shared [ExerciseTargetPicker] and starts it disabled, so
/// looking at a goal cannot change it. Edit unlocks the same form, SAVE
/// replaces ADD at the floor and writes the whole row, and the sheet rests
/// again on what the write read back. A record — a completed review's goal —
/// wires no writer at all, so there is no Edit and no way in.
///
/// The tests pin the things that could go wrong quietly: the resting state
/// letting a keystroke through, SAVE acting on a draft that says nothing new,
/// and a save leaving the boxes disagreeing with the row it just wrote.
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
    DateTime? targetDate,
    List<GoalTargetDateChange> targetDateHistory = const [],
    DateTime? createdDate,
  }) => Goal(
    goalId: 'g1',
    userId: 'u1',
    text: 'Bench',
    description: description,
    exerciseId: exerciseId,
    variationId: variationId,
    targetWeight: targetWeight,
    targetReps: targetReps,
    targetDate: targetDate,
    targetDateHistory: targetDateHistory,
    // Most goals in these tests were said on the 19th — the sheet's title
    // subtext is part of what a reading shows.
    createdDate: createdDate ?? DateTime(2026, 10, 19),
  );

  /// The row the repository would read back after saving [target] over
  /// [before]: the form's fields, blank notes normalized to none, and a moved
  /// deadline appended to the history — the real UPDATE's shape.
  Goal apply(Goal before, ExerciseTarget target) {
    final notes = target.notes?.trim();
    final next = target.targetDate == null
        ? null
        : dateOnly(target.targetDate!);
    return Goal(
      goalId: before.goalId,
      userId: before.userId,
      text: target.exerciseName.isEmpty ? before.text : target.exerciseName,
      description: notes == null || notes.isEmpty ? null : notes,
      exerciseId: target.exerciseId,
      variationId: target.variationId,
      targetWeight: target.weight,
      targetReps: target.reps,
      targetDate: next,
      targetDateHistory: _sameDay(before.targetDate, next)
          ? before.targetDateHistory
          : [
              ...before.targetDateHistory,
              GoalTargetDateChange(
                from: before.targetDate,
                to: next,
                changedAt: DateTime.now(),
              ),
            ],
      createdDate: before.createdDate,
    );
  }

  /// Opens the sheet over a stubbed read and a recording writer, and hands
  /// back the targets that were saved, in order.
  ///
  /// [writable] false opens it the way a **record** does — a null writer, the
  /// state a completed review's goal is read in. There is no Edit there, and
  /// the list stays empty for the same reason it exists: nothing can be
  /// written to it.
  Future<List<ExerciseTarget>> openSheet(
    WidgetTester tester, {
    required Goal goal,
    Future<List<PastSetRow>> Function()? load,
    bool failWrite = false,
    bool writable = true,
    void Function(PastSetRow set)? onOpenWorkout,
  }) async {
    final writes = <ExerciseTarget>[];
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
                  loadPastSets: load ?? () async => const <PastSetRow>[],
                  onOpenWorkout: onOpenWorkout,
                  onSave: writable
                      ? (target) async {
                          writes.add(target);
                          if (failWrite) {
                            throw StateError('goal write failed');
                          }
                          return apply(goal, target);
                        }
                      : null,
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

  TextField field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key)));

  final notesField = find.descendant(
    of: find.byType(LambdaInput),
    matching: find.byType(TextField),
  );
  final saveButton = find.widgetWithText(GlassButton, 'SAVE');
  final editButton = find.widgetWithIcon(GlassButton, LucideIcons.pencil);

  testWidgets(
    'rests on the stored goal — the whole form, none of it enterable',
    (tester) async {
      final writes = await openSheet(
        tester,
        goal: goal(description: 'Beltless, pause on the chest'),
      );

      expect(find.text('Goal'), findsOneWidget);
      // When the goal was said reads under the title — stamped at insert and
      // the one date here nothing edits.
      expect(find.text('Created 19 Oct 2026'), findsOneWidget);
      // The same form the add sheet composes: the selector, the session grid's
      // own column headers, the notes, the deadline.
      expect(find.text('Bench'), findsOneWidget);
      expect(find.text('REPS'), findsOneWidget);
      expect(find.text('KG'), findsOneWidget);
      expect(find.text('VARIATION'), findsOneWidget);
      expect(find.text('NOTES'), findsOneWidget);
      expect(find.text('TARGET DATE'), findsOneWidget);
      expect(find.text('No target date'), findsOneWidget);

      // The values read as the row stores them — 100, never 100.0.
      expect(field(tester, 'goal-reps').controller!.text, '5');
      expect(field(tester, 'goal-kg').controller!.text, '100');
      expect(find.text('Beltless, pause on the chest'), findsOneWidget);

      // Resting: every field shows its value and none can be entered.
      expect(field(tester, 'goal-reps').readOnly, isTrue);
      expect(field(tester, 'goal-kg').readOnly, isTrue);
      expect(
        tester.widget<LambdaInput>(find.byType(LambdaInput)).enabled,
        isFalse,
      );

      // SAVE is drawn where ADD sits when creating, and it cannot act: the form
      // has not been unlocked, let alone changed.
      expect(editButton, findsOneWidget);
      expect(saveButton, findsOneWidget);
      expect(tester.widget<GlassButton>(saveButton).disabled, isTrue);
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      // A reading has no catalog to pick from, and no note invite.
      await tester.tap(find.byKey(const ValueKey('goal-exercise-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Search exercises…'), findsNothing);
      expect(find.text('Add a note…'), findsNothing);

      // A goal whose deadline never moved has no history to open.
      expect(
        find.byKey(const ValueKey('goal-target-date-history')),
        findsNothing,
      );

      expect(
        writes,
        isEmpty,
        reason: 'opening a goal must not be able to change it',
      );
    },
  );

  testWidgets('a met goal states the day it was hit, under the target date', (
    tester,
  ) async {
    await openSheet(
      tester,
      goal: goal(),
      load: () async => [
        // A goal is achieved once: the sheet names the FIRST day the target
        // was met, not the best day since (2026-10-20).
        setRow(id: 's1', date: '2026-03-05', weight: 100, reps: [5]),
        setRow(id: 's2', date: '2026-06-05', weight: 115, reps: [5]),
      ],
    );

    // The completion belongs to the deadline half of the sheet (2026-10-20):
    // it reads beneath the TARGET DATE field — the goal's two dates, one
    // above the other — not under the created date in the header.
    expect(find.text('Created 19 Oct 2026'), findsOneWidget);
    expect(find.text('Completed 5 Mar 2026'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Completed 5 Mar 2026')).dy,
      greaterThan(tester.getTopLeft(find.text('TARGET DATE')).dy),
      reason: 'the completion sits under the deadline, not in the header',
    );
  });

  testWidgets('a goal still standing states no completion day', (tester) async {
    await openSheet(
      tester,
      goal: goal(),
      // Heavy, but short of the target: evidence of an attempt, not a hit.
      load: () async => [
        setRow(id: 's1', date: '2026-03-05', weight: 90, reps: [5]),
      ],
    );

    expect(find.text('Created 19 Oct 2026'), findsOneWidget);
    expect(find.textContaining('Completed'), findsNothing);
    expect(find.textContaining('already beat'), findsNothing);
  });

  testWidgets('Edit unlocks the form; SAVE waits for a real change', (
    tester,
  ) async {
    await openSheet(tester, goal: goal(description: 'Beltless'));

    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();

    // The mode changed, not the form: the same cells, now enterable — and
    // SAVE is still quiet, because nothing has been said yet.
    expect(find.byIcon(LucideIcons.pencil), findsNothing);
    expect(field(tester, 'goal-reps').readOnly, isFalse);
    expect(field(tester, 'goal-kg').readOnly, isFalse);
    expect(
      tester.widget<LambdaInput>(find.byType(LambdaInput)).enabled,
      isTrue,
    );
    expect(tester.widget<GlassButton>(saveButton).disabled, isTrue);

    await tester.enterText(notesField, 'Beltless, pause on the chest');
    await tester.pumpAndSettle();
    expect(tester.widget<GlassButton>(saveButton).disabled, isFalse);

    // Back to the stored text: the draft says nothing new again.
    await tester.enterText(notesField, 'Beltless');
    await tester.pumpAndSettle();
    expect(tester.widget<GlassButton>(saveButton).disabled, isTrue);

    // A number typed and typed back is no change either.
    await tester.enterText(find.byKey(const ValueKey('goal-kg')), '105');
    await tester.pumpAndSettle();
    expect(tester.widget<GlassButton>(saveButton).disabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('goal-kg')), '100');
    await tester.pumpAndSettle();
    expect(tester.widget<GlassButton>(saveButton).disabled, isTrue);

    // Whitespace around the stored notes is not a change — the row stores
    // trimmed text, and the draft is compared trimmed.
    await tester.enterText(notesField, '  Beltless  ');
    await tester.pumpAndSettle();
    expect(tester.widget<GlassButton>(saveButton).disabled, isTrue);
  });

  testWidgets('SAVE writes the whole form, and the sheet rests on what it read '
      'back', (tester) async {
    final writes = await openSheet(
      tester,
      goal: goal(description: 'Beltless', targetDate: DateTime(2026, 11, 1)),
    );

    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('goal-kg')), '105');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    final target = writes.single;
    expect(target.exerciseId, 'e1');
    expect(target.weight, 105);
    expect(target.reps, 5);
    expect(target.notes, 'Beltless');
    expect(target.targetDate, DateTime(2026, 11, 1));

    // Back to rest: Edit returns, SAVE goes quiet, and the boxes show the row
    // as stored — the save left a reading, not a form still standing.
    expect(find.byIcon(LucideIcons.pencil), findsOneWidget);
    expect(tester.widget<GlassButton>(saveButton).disabled, isTrue);
    expect(field(tester, 'goal-kg').controller!.text, '105');
    expect(field(tester, 'goal-kg').readOnly, isTrue);
  });

  testWidgets('clearing the deadline saves "no date", and the history keeps '
      'the move', (tester) async {
    final moved = goal(
      targetDate: DateTime(2026, 11, 15),
      targetDateHistory: [
        GoalTargetDateChange(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 11, 15),
          changedAt: DateTime(2026, 10, 25),
        ),
      ],
    );
    final writes = await openSheet(tester, goal: moved);

    // The moves live behind the clock beside the deadline now: no caption
    // under the field, and the button opens without entering edit mode.
    expect(find.textContaining('Changed 25 Oct'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('goal-target-date-history')));
    await tester.pumpAndSettle();
    final historySheet = find.byKey(
      const ValueKey('goal-target-date-history-sheet'),
    );
    expect(find.text('Target date changes'), findsOneWidget);
    expect(
      find.descendant(of: historySheet, matching: find.text('15 Nov 2026')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: historySheet,
        matching: find.text('Changed 25 Oct 2026 · was 1 Nov 2026'),
      ),
      findsOneWidget,
    );

    // Dismiss the list; the form underneath is still at rest.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Target date changes'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-date-clear')));
    await tester.pumpAndSettle();
    expect(find.text('No target date'), findsOneWidget);
    expect(tester.widget<GlassButton>(saveButton).disabled, isFalse);

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(writes.single.targetDate, isNull);

    // The read-back row carries the new adjustment — clearing a deadline is a
    // move, not a forgetting — and the history now leads with it.
    await tester.tap(find.byKey(const ValueKey('goal-target-date-history')));
    await tester.pumpAndSettle();
    final today = DateFormat('d MMM yyyy').format(DateTime.now());
    expect(
      find.descendant(of: historySheet, matching: find.text('No target date')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: historySheet,
        matching: find.text('Changed $today · was 15 Nov 2026'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the history lists the moves newest first, a null side as '
      '"no date"', (tester) async {
    await openSheet(
      tester,
      goal: goal(
        targetDate: DateTime(2026, 12, 1),
        targetDateHistory: [
          GoalTargetDateChange(
            from: null,
            to: DateTime(2026, 11, 1),
            changedAt: DateTime(2026, 10, 20),
          ),
          GoalTargetDateChange(
            from: DateTime(2026, 11, 1),
            to: null,
            changedAt: DateTime(2026, 10, 24),
          ),
          GoalTargetDateChange(
            from: null,
            to: DateTime(2026, 12, 1),
            changedAt: DateTime(2026, 10, 26),
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('goal-target-date-history')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('goal-target-date-history-sheet'));

    const newest = 'Changed 26 Oct 2026 · was no date';
    const middle = 'Changed 24 Oct 2026 · was 1 Nov 2026';
    const oldest = 'Changed 20 Oct 2026 · was no date';
    for (final line in [newest, middle, oldest]) {
      expect(
        find.descendant(of: sheet, matching: find.text(line)),
        findsOneWidget,
      );
    }

    // Newest first: the move that produced the date on screen leads the list.
    double y(String text) => tester
        .getTopLeft(find.descendant(of: sheet, matching: find.text(text)))
        .dy;
    expect(y(newest), lessThan(y(middle)));
    expect(y(middle), lessThan(y(oldest)));
  });

  // ── The record ────────────────────────────────────────────────────────────
  //
  // A completed review's goal opens the same sheet with no writer wired: the
  // report it would take is already made. The two states differ in what can be
  // *reached*, never in what is shown — the notes still read back, the form
  // still stands complete, and every way into edit mode is gone.
  testWidgets('a record has no Edit and no way into the form', (tester) async {
    await openSheet(
      tester,
      goal: goal(description: 'Beltless, pause on the chest'),
      writable: false,
    );

    // What the goal is, and what was said about it — all still here.
    expect(find.text('Goal'), findsOneWidget);
    expect(find.text('Created 19 Oct 2026'), findsOneWidget);
    expect(find.text('Bench'), findsOneWidget);
    expect(field(tester, 'goal-reps').controller!.text, '5');
    expect(field(tester, 'goal-kg').controller!.text, '100');
    expect(find.text('Beltless, pause on the chest'), findsOneWidget);

    // Every door into writing is gone, not merely locked.
    expect(editButton, findsNothing);
    expect(saveButton, findsOneWidget);
    expect(tester.widget<GlassButton>(saveButton).disabled, isTrue);
    expect(field(tester, 'goal-reps').readOnly, isTrue);
    expect(field(tester, 'goal-kg').readOnly, isTrue);
    expect(
      tester.widget<LambdaInput>(find.byType(LambdaInput)).enabled,
      isFalse,
    );

    // Neither the catalog nor the calendar opens: the tap is gone with the
    // edit it would start.
    await tester.tap(find.byKey(const ValueKey('goal-exercise-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Search exercises…'), findsNothing);
    expect(
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('goal-target-date')),
          )
          .onTap,
      isNull,
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
    expect(find.byType(LambdaInput), findsNothing);
    expect(find.text('Add a note…'), findsNothing);
  });

  testWidgets('a writable goal with no notes still offers the box', (
    tester,
  ) async {
    await openSheet(tester, goal: goal());

    expect(find.text('NOTES'), findsOneWidget);
    expect(find.byType(LambdaInput), findsOneWidget);
  });

  testWidgets('a failed save keeps the form standing and says so', (
    tester,
  ) async {
    final writes = await openSheet(tester, goal: goal(), failWrite: true);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();

    await tester.enterText(notesField, 'Slow off the chest');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    expect(find.text('Could not save the goal.'), findsOneWidget);
    expect(
      find.byIcon(LucideIcons.pencil),
      findsNothing,
      reason: 'a failure leaves the form unlocked — the edit is still in hand',
    );
    expect(tester.widget<GlassButton>(saveButton).disabled, isFalse);
    expect(
      tester.widget<TextField>(notesField).controller!.text,
      'Slow off the chest',
      reason: 'the box keeps what was typed',
    );

    // Let the SnackBar's own dismiss timer run out — a timer still pending
    // when the tree comes down fails the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('a met goal states its completion under the deadline, and the '
      'row opens that workout', (tester) async {
    String? opened;
    await openSheet(
      tester,
      goal: goal(),
      load: () async => [
        setRow(id: 'a', date: '2026-01-05', weight: 100, reps: [3]),
        setRow(id: 'b', date: '2026-03-05', weight: 100, reps: [6]),
      ],
      onOpenWorkout: (set) => opened = set.sessionId,
    );

    // The "you've already beat this" caption is the creation form's (the
    // draft's target, as it is typed); a stored goal states the day it was
    // hit, under the deadline it answered (2026-10-20).
    expect(find.textContaining('already beat'), findsNothing);
    expect(find.text('Completed 5 Mar 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-completed-on')));
    expect(opened, 's-b');
  });

  testWidgets('a failed history read claims nothing — never "no sets"', (
    tester,
  ) async {
    await openSheet(
      tester,
      goal: goal(),
      load: () async => throw StateError('timeline read failed'),
    );

    expect(find.textContaining("Couldn't read"), findsNothing);
    expect(find.textContaining('already beat'), findsNothing);
    expect(find.textContaining('Completed'), findsNothing);
    // The form itself is untouched by the miss.
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);
  });

  testWidgets('a goal with no exercise never reads the timeline', (
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

    expect(reads, 0, reason: 'there is no target to measure history against');
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('the sheet draws readable ink and type', (tester) async {
    await openSheet(tester, goal: goal());
    expectReadableText(tester, find.byType(MaterialApp));
  });
}

/// Whether two goal dates name the same calendar day. Null is "no deadline",
/// and equals only itself.
bool _sameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Registers a bundled typeface under the family name the app asks for.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}
