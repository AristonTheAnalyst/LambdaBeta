import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';
import 'package:lambda/shared/widgets/session_exercise_card.dart';

/// The review note box on THE exercise card.
///
/// The box is the whole of a review note's life: on the editor it is where the
/// note is typed AND where it is read back, on the record it IS the record. So
/// its states have to come apart exactly — absent on a card with no review and
/// nothing noted; a live text box inside a review, shown even before there is
/// a note because the empty box is the way in; plain text on the record, and
/// only when there is something to read — and none of them may disturb the
/// rest of the card, which three other screens draw every day.
///
/// The states also have to wear the app's one text-box rule: editable is
/// [LambdaInput], read-only is [LambdaReadout].
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    String? reviewNote,
    ValueChanged<String>? onReviewNoteChanged,
    String reviewNoteLabel = kReviewNoteLabel,
    String? reviewNoteEmptyText,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionExerciseCard(
          exerciseNames: const ['Bench Press'],
          activeIndex: 0,
          onSelect: (_) {},
          rows: const [],
          reviewNote: reviewNote,
          onReviewNoteChanged: onReviewNoteChanged,
          reviewNoteLabel: reviewNoteLabel,
          reviewNoteEmptyText: reviewNoteEmptyText,
        ),
      ),
    ),
  );

  testWidgets('with nothing noted and no review, no box is drawn at all', (
    tester,
  ) async {
    // Every ordinary card — the live session, the planner at rest — lands
    // here, and a box they never asked for would be chrome on four screens.
    await pumpCard(tester);
    expect(find.text('Exercise Review Note'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('inside a review the box is a live field before there is a note', (
    tester,
  ) async {
    String? written;
    await pumpCard(tester, onReviewNoteChanged: (v) => written = v);

    // Empty, the box is still the way in: the header names it, and there is
    // a field to type into — nothing to open, no invitation copy to read.
    expect(find.text('Exercise Review Note'), findsOneWidget);
    expect(
      find.byType(LambdaInput),
      findsOneWidget,
      reason: 'an editable text box is LambdaInput, the app over',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.fillColor,
      AppColors.surface,
      reason: 'the box must copy the session-prep notes box ("Why do you '
          'feel that way") exactly — the reference field\'s base fill, no '
          'elevated step (2026-10-08: the surfaceHigh version read as a '
          'different box from the one being copied)',
    );
    await tester.enterText(find.byType(TextField), 'Felt heavy');
    expect(written, 'Felt heavy');
  });

  testWidgets('the box shows the note as typed, and edits it in place', (
    tester,
  ) async {
    String? written;
    await pumpCard(
      tester,
      reviewNote: 'Felt heavy — drop to 55 if it grinds',
      onReviewNoteChanged: (v) => written = v,
    );

    // As is: the field carries exactly what the row holds, no ellipsis, no
    // truncation — the note is read where it is written.
    expect(find.text('Felt heavy — drop to 55 if it grinds'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Dropped to 55');
    expect(written, 'Dropped to 55');
  });

  testWidgets('the field never re-seats itself from the echo of a write', (
    tester,
  ) async {
    // The card re-renders with the stored note after every keystroke's
    // write. A rebuild that feeds the same text back must leave the field
    // alone — re-seating the controller would throw the caret to the end.
    await pumpCard(
      tester,
      reviewNote: 'Felt heavy',
      onReviewNoteChanged: (_) {},
    );
    await tester.enterText(find.byType(TextField), 'x');
    // Same text arriving again under a new widget generation.
    await pumpCard(
      tester,
      reviewNote: 'x',
      onReviewNoteChanged: (_) {},
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'x');
  });

  testWidgets('on the record the note is shown read-only', (tester) async {
    // No change callback: the record is not a place notes are written. The
    // note still shows — that is the whole reason it was written.
    await pumpCard(tester, reviewNote: '  Swapped to paused reps  ');

    expect(find.text('Exercise Review Note'), findsOneWidget);
    // Trimmed: the box is a display here, and the whitespace a note was saved
    // with is not part of what it says.
    expect(find.text('Swapped to paused reps'), findsOneWidget);
    expect(
      find.byType(LambdaReadout),
      findsOneWidget,
      reason: 'a read-only text box is LambdaReadout, never a dead field',
    );
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'an editable field belongs to the pass, not the record',
    );
  });

  testWidgets('the record\'s note reads under its own header', (tester) async {
    // While Compare is up the box shows the RECORD's note — the editor hands
    // it the record's words — and the header has to say whose note it is: a
    // note read under the pass's own header would be taken for the one being
    // written (2026-10-10).
    await pumpCard(
      tester,
      reviewNote: 'Swapped to paused reps',
      reviewNoteLabel: kPreviousReviewNoteLabel,
    );

    expect(find.text(kPreviousReviewNoteLabel), findsOneWidget);
    expect(
      find.text(kReviewNoteLabel),
      findsNothing,
      reason: 'the pass\'s header on the record\'s note would claim the note '
          'is the one being written',
    );
    expect(find.text('Swapped to paused reps'), findsOneWidget);
    expect(
      find.byType(LambdaReadout),
      findsOneWidget,
      reason: 'the record\'s note is display, never a field — the pass\'s note '
          'is written after the eye flips back',
    );
  });

  testWidgets('with nothing noted, the record\'s box holds its place and says '
      'so', (tester) async {
    // The flip changes values, never furniture: an exercise the record left
    // nothing about keeps the box the eye just landed on, and the absence of
    // a note is answered inside it — muted, in the note's own place, so it
    // reads as "nothing was said" rather than as a note (2026-10-10).
    await pumpCard(
      tester,
      reviewNoteLabel: kPreviousReviewNoteLabel,
      reviewNoteEmptyText: kNoPreviousNoteText,
    );

    expect(find.text(kPreviousReviewNoteLabel), findsOneWidget);
    expect(find.text(kNoPreviousNoteText), findsOneWidget);
    expect(find.byType(LambdaReadout), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(kNoPreviousNoteText)).style!.color,
      AppColors.muted,
      reason: 'placeholder copy wears the input placeholder\'s own muted ink — '
          'a note\'s ink on an empty box would read as a note',
    );
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'still the record: nothing here is writable',
    );
  });

  testWidgets('the box reads after the sets, never in the lesson slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionExerciseCard(
            exerciseNames: const ['Bench Press'],
            activeIndex: 0,
            onSelect: (_) {},
            rows: const [],
            onAddSet: () {},
            pinnedLesson: PinnedLessonData(
              text: 'Keep the elbows tucked',
              date: DateTime(2026, 10, 1),
            ),
            reviewNote: 'Swapped to paused reps',
            onReviewNoteChanged: (_) {},
          ),
        ),
      ),
    );

    // How to do the lift stays where it was — under the selector; how it
    // went reads after the work it is about.
    expect(
      tester.getTopLeft(find.text('LESSON')).dy,
      lessThan(tester.getTopLeft(find.text('Exercise Review Note')).dy),
    );
    expect(
      tester.getTopLeft(find.text('+ ADD SET')).dy,
      lessThan(tester.getTopLeft(find.text('Exercise Review Note')).dy),
    );
  });

  testWidgets('with nothing to add, the row can still hold its place — dead', (
    tester,
  ) async {
    // What Compare leans on: the card draws the same workout with the record's
    // rows in place of the plan's, and the grid must not move under the finger
    // that just tapped the button. So the row stays, greyed, with no press.
    var tapped = 0;
    Future<double> heightWith({required bool reserved}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // A scroll view, as the editor has: the card takes its own height
            // instead of being stretched to the screen's.
            body: SingleChildScrollView(
              child: SessionExerciseCard(
                exerciseNames: const ['Bench Press'],
                activeIndex: 0,
                onSelect: (_) {},
                rows: const [],
                onAddSet: reserved ? null : () => tapped++,
                reserveAddSet: reserved,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(SessionExerciseCard)).height;
    }

    final live = await heightWith(reserved: false);
    await tester.tap(find.text('+ ADD SET'));
    expect(tapped, 1, reason: 'the ordinary row is a button');

    final reserved = await heightWith(reserved: true);
    expect(
      reserved,
      live,
      reason: 'reserving the row exists precisely so the card is exactly as '
          'tall either way — the flip changes values, never the layout',
    );
    await tester.tap(find.text('+ ADD SET'));
    expect(tapped, 1, reason: 'and it is dead: there is nothing to add to a '
        'record');
  });
}
