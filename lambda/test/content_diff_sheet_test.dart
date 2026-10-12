import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/features/programs/view/content_diff_sheet.dart';

/// The comparison sheet: a card per exercise, and the note-change popup.
///
/// An exercise card is an answer, not a list — "Changes made" or "No changes",
/// no set rows — and where a screen holds the exercise, the card taps through
/// to it. A note edit still arrives with both texts on the change and a capped
/// preview on its line: what the line cannot show, a tap opens, the pair whole.
/// Everything that is not a note stays inert — the popup is for the one edit
/// whose content does not fit.
void main() {
  ContentSession session({String? notes, String name = 'Push Day'}) =>
      ContentSession(
        sessionId: 's1',
        userId: 'u1',
        name: name,
        notes: notes,
        exercises: const [],
      );

  ContentSet cset(String id, {String? variation, String weight = '60'}) =>
      ContentSet(
        plannedSetId: id,
        plannedExerciseId: 'pe1',
        plannedSessionId: 's1',
        userId: 'u1',
        setNumber: 1,
        variationId: variation,
        targetWeight: weight,
        targetReps: '5',
      );

  ContentExercise cexercise(
    String id, {
    String? exerciseId = 'ex1',
    List<ContentSet>? sets,
  }) =>
      ContentExercise(
        plannedExerciseId: id,
        plannedSessionId: 's1',
        userId: 'u1',
        exerciseId: exerciseId,
        exerciseOrder: 1,
        sets: sets ?? [cset('${id}s1')],
      );

  ContentSession cworkout(
    String id, {
    String name = 'Push Day',
    List<ContentExercise>? exercises,
  }) =>
      ContentSession(
        sessionId: id,
        userId: 'u1',
        name: name,
        exercises: exercises ?? const [],
      );

  Future<void> openContentSheet(
    WidgetTester tester, {
    required ProgramContent? before,
    required ProgramContent? after,
    Map<String, String> exerciseNames = const {},
    Map<String, String> variationNames = const {},
    String? subtitle,
    String? beforeMissingNote,
    String? emptyNote,
    ValueChanged<String>? onExerciseTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showContentDiffSheet(
                  context,
                  title: kReviewChangesTitle,
                  subtitle: subtitle,
                  before: before,
                  after: after,
                  exerciseNames: exerciseNames,
                  variationNames: variationNames,
                  beforeMissingNote: beforeMissingNote,
                  emptyNote: emptyNote,
                  onExerciseTap: onExerciseTap,
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
  }

  Future<void> openSheet(
    WidgetTester tester, {
    required ContentSession before,
    required ContentSession after,
    String? subtitle,
  }) async {
    await openContentSheet(
      tester,
      before: ProgramContent(sessions: [before]),
      after: ProgramContent(sessions: [after]),
      subtitle: subtitle,
    );
  }

  testWidgets('a note row previews the pair, and a tap opens both whole', (
    tester,
  ) async {
    // Longer than the row's cap, so the preview and the popup can be told
    // apart: the row flattens and cuts, the popup does neither.
    const was = 'Squat felt slow out of the hole, keep the pause honest';
    const now = 'Pause worked — everything moved faster today';

    await openSheet(tester, before: session(notes: was), after: session(notes: now));

    // The row: a preview that says both things changed...
    expect(find.textContaining('…'), findsOneWidget);
    // ...and the full texts are not on it.
    expect(find.text(was), findsNothing);

    await tester.tap(find.textContaining('→'));
    await tester.pumpAndSettle();

    expect(find.text('Note changed'), findsOneWidget);
    expect(find.text('BEFORE'), findsOneWidget);
    expect(find.text('AFTER'), findsOneWidget);
    expect(find.text(was), findsOneWidget);
    expect(find.text(now), findsOneWidget);
  });

  testWidgets('an ordinary edit has no popup behind it', (tester) async {
    await openSheet(
      tester,
      before: session(name: 'Push'),
      after: session(name: 'Push Day'),
    );

    expect(find.text('renamed: Push → Push Day'), findsOneWidget);
    // No rung, and a tap on the row does nothing — the detail already says
    // everything the row has.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await tester.tap(find.text('renamed: Push → Push Day'));
    await tester.pumpAndSettle();
    expect(find.text('Note changed'), findsNothing);
  });

  testWidgets('counts and their deltas lead the rows', (tester) async {
    // One workout, one exercise, one set becomes three sets: the pair of
    // counts the pass is about, answered before the rows get specific.
    await openContentSheet(
      tester,
      before: ProgramContent(sessions: [
        cworkout('s1', exercises: [cexercise('pe1')]),
      ]),
      after: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a'), cset('b'), cset('c')]),
        ]),
      ]),
    );

    expect(find.text('SETS'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('EXERCISES'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('±0'), findsOneWidget);

    // Above the list: the summary is the short answer, the rows the long one.
    expect(
      tester.getTopLeft(find.text('SETS')).dy,
      lessThan(tester.getTopLeft(find.text('PUSH DAY')).dy),
    );
  });

  testWidgets('an edit that moves no counts reads ±0, not a change', (
    tester,
  ) async {
    await openContentSheet(
      tester,
      before: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', weight: '60')]),
        ]),
      ]),
      after: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', weight: '65')]),
        ]),
      ]),
    );

    // The target edit is a real row below; the counts it did not move stay
    // grey zeroes.
    expect(find.text('±0'), findsNWidgets(2));
    expect(find.text('+2'), findsNothing);
  });

  testWidgets('every exercise of a changed workout gets a card', (
    tester,
  ) async {
    // One lift edited, one untouched: the untouched one is the answer the
    // card exists to give, so it renders too — "No changes" is not silence.
    await openContentSheet(
      tester,
      before: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', weight: '60')]),
          cexercise('pe2', exerciseId: 'ex2', sets: [cset('pe2s1')]),
        ]),
      ]),
      after: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', weight: '65')]),
          cexercise('pe2', exerciseId: 'ex2', sets: [cset('pe2s1')]),
        ]),
      ]),
      exerciseNames: const {'ex1': 'Bench Press', 'ex2': 'Incline Press'},
    );

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Incline Press'), findsOneWidget);
    expect(find.text('Changes made'), findsOneWidget);
    expect(find.text('No changes'), findsOneWidget);
    // The set-level detail is what the card said goodbye to: the card answers
    // whether the exercise moved, and nothing below that.
    expect(find.text('Set 1 — 60 × 5 → 65 × 5'), findsNothing);
    expect(find.textContaining('Set 1'), findsNothing);
  });

  testWidgets('an exercise card opens the exercise where one is held', (
    tester,
  ) async {
    String? opened;

    await openContentSheet(
      tester,
      before: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', weight: '60')]),
          cexercise('pe2', exerciseId: 'ex2', sets: [cset('pe2s1')]),
        ]),
      ]),
      after: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', weight: '65')]),
          cexercise('pe2', exerciseId: 'ex2', sets: [cset('pe2s1')]),
        ]),
      ]),
      exerciseNames: const {'ex1': 'Bench Press', 'ex2': 'Incline Press'},
      onExerciseTap: (id) => opened = id,
    );

    // Both cards offer the rung — an untouched exercise is still somewhere
    // to go.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    expect(opened, 'pe1');
    expect(
      find.text(kReviewChangesTitle),
      findsNothing,
      reason:
          'the sheet closes itself, so the switch lands on the screen the '
          'exercise lives on rather than behind the sheet',
    );
  });

  testWidgets('a removed exercise is a card of its own — and goes nowhere', (
    tester,
  ) async {
    // The group is gone, so the card is titled from the group's own change.
    String? opened;
    await openContentSheet(
      tester,
      before: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a')]),
          cexercise('pe2', exerciseId: 'ex2', sets: [cset('pe2s1')]),
        ]),
      ]),
      after: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a')]),
        ]),
      ]),
      exerciseNames: const {'ex1': 'Bench Press', 'ex2': 'Incline Press'},
      onExerciseTap: (id) => opened = id,
    );

    expect(find.text('Incline Press'), findsOneWidget);
    // One line, and it is the whole answer: gone is not a set-level detail,
    // and a card that cannot open anywhere must say what it is.
    expect(find.text('removed'), findsOneWidget);
    // And the survivor is carded beside it, holding still.
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('No changes'), findsOneWidget);

    // One rung, on the survivor alone: the removed card has nowhere to go.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.text('Incline Press'));
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(find.text(kReviewChangesTitle), findsOneWidget);
  });

  testWidgets('a variation change is answered on its card, not spelled out', (
    tester,
  ) async {
    await openContentSheet(
      tester,
      before: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', variation: 'v1')]),
        ]),
      ]),
      after: ProgramContent(sessions: [
        cworkout('s1', exercises: [
          cexercise('pe1', sets: [cset('a', variation: 'v2')]),
        ]),
      ]),
      exerciseNames: const {'ex1': 'Bench Press'},
      variationNames: const {'v1': 'Paused', 'v2': 'Tempo'},
    );

    // The card carries the exercise and its verdict; the variation is a
    // detail the exercise itself shows, not a line here.
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Changes made'), findsOneWidget);
    expect(find.textContaining('variation'), findsNothing);
    // The glyph vocabulary the sheet used to speak is gone.
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('a subtitle renders when the caller has one to give', (
    tester,
  ) async {
    await openSheet(
      tester,
      before: session(name: 'Push'),
      after: session(name: 'Push Day'),
      subtitle: 'Jul 1  ·  Jul 15',
    );

    expect(find.text(kReviewChangesTitle), findsOneWidget);
    expect(find.text('Jul 1  ·  Jul 15'), findsOneWidget);
  });

  testWidgets('no earlier version shows its note, not empty numbers', (
    tester,
  ) async {
    await openContentSheet(
      tester,
      before: null,
      after: ProgramContent(sessions: [
        cworkout('s1', exercises: [cexercise('pe1')]),
      ]),
      beforeMissingNote: 'no earlier version to compare',
    );

    expect(find.text('no earlier version to compare'), findsOneWidget);
    expect(find.text('SETS'), findsNothing);
    expect(find.text('EXERCISES'), findsNothing);
  });

  testWidgets('identical contents show the note, not zeroed counts', (
    tester,
  ) async {
    final content = ProgramContent(sessions: [
      cworkout('s1', exercises: [cexercise('pe1')]),
    ]);
    await openContentSheet(
      tester,
      before: content,
      after: content,
      emptyNote: 'Nothing has changed.',
    );

    expect(find.text('Nothing has changed.'), findsOneWidget);
    expect(find.text('SETS'), findsNothing);
  });
}
