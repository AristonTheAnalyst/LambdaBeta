import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/programs/view/review_workout_note_sheet.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// The sheet one WORKOUT's review note is written in — the workout's note,
/// where an exercise's is a box typed into on its card.
///
/// Three answers it must be able to give, never confused with each other: a
/// trimmed note (write it), an empty string (clear it — the caller removes the
/// entry), and null (dismissed — the caller writes nothing at all). The tests
/// pin each, plus the one header fact the sheet exists to state: whose note
/// this is.
void main() {
  late String? result;

  Future<void> openSheet(
    WidgetTester tester, {
    String workoutName = 'Push Day',
    String initialValue = '',
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showReviewWorkoutNoteSheet(
                    context,
                    workoutName: workoutName,
                    initialValue: initialValue,
                  );
                },
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

  GlassButton saveButton(WidgetTester tester) =>
      tester.widget<GlassButton>(find.widgetWithText(GlassButton, 'Save'));

  testWidgets('names the workout the note is about', (tester) async {
    await openSheet(tester, workoutName: 'Push Day');
    expect(find.text('PUSH DAY'), findsOneWidget);
  });

  testWidgets('Save stays disabled until the text is worth writing', (
    tester,
  ) async {
    await openSheet(tester, initialValue: 'old note');
    expect(saveButton(tester).disabled, isTrue);

    // Whitespace around the same text is not a change: the sheet compares
    // trimmed, so padding cannot arm a Save that would write nothing new.
    await tester.enterText(find.byType(TextField), '  old note  ');
    await tester.pump();
    expect(saveButton(tester).disabled, isTrue);

    await tester.enterText(find.byType(TextField), 'old note, but sharper');
    await tester.pump();
    expect(saveButton(tester).disabled, isFalse);
  });

  testWidgets('Save returns the trimmed note', (tester) async {
    await openSheet(tester);
    await tester.enterText(
      find.byType(TextField),
      '  Cut the volume next time  ',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, 'Cut the volume next time');
  });

  testWidgets('no Delete button over an empty note', (tester) async {
    // Nothing to delete: the button would be a second way to say "leave it
    // unwritten", next to the dismiss gesture that already exists.
    await openSheet(tester);
    expect(find.text('Delete note'), findsNothing);
  });

  testWidgets('Delete returns empty, which the caller reads as clear', (
    tester,
  ) async {
    await openSheet(tester, initialValue: 'old note');
    expect(find.text('Delete note'), findsOneWidget);

    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    expect(result, '');
  });

  testWidgets('dismissing returns null — the caller must write nothing', (
    tester,
  ) async {
    await openSheet(tester, initialValue: 'old note');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
