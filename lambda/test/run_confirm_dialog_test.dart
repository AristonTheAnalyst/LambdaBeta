import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/programs/view/run_confirm_dialog.dart';

/// The question asked before a run begins or resumes.
///
/// It is asked every time, whatever else is open, so it has to carry its own
/// weight in every case: what the act does when nothing else is running, what
/// becomes of the run it steps aside when something is, and — since a paused
/// run is neither — that a pause survives a begin it is not part of. It used to
/// be asked only in the middle case, which is what these tests exist to keep
/// from coming back. No font loading here, unlike the screen tests: an
/// `AlertDialog` wraps its text, so there is no fixed-width box for a fallback
/// face to overflow.
void main() {
  late bool? answer;

  Future<void> openDialog(
    WidgetTester tester, {
    RunEntry entry = RunEntry.begin,
    String programName = 'Base',
    bool displacesCurrentRun = true,
    String? displacedName = 'Lambda',
    bool otherRunPaused = false,
  }) async {
    answer = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  answer = await confirmStartRun(
                    context,
                    entry: entry,
                    programName: programName,
                    displacesCurrentRun: displacesCurrentRun,
                    displacedName: displacedName,
                    otherRunPaused: otherRunPaused,
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

  testWidgets('names both programs, and says the left one is paused not ended',
      (tester) async {
    await openDialog(tester, programName: 'Base', displacedName: 'Lambda');

    expect(find.text('Begin "Base"?'), findsOneWidget,
        reason: 'the title has to name what is being begun — "another '
            'program" is not something a decision can be weighed against');
    expect(find.textContaining('"Lambda" will be paused, not ended'),
        findsOneWidget,
        reason: 'the run being left keeps everything, so the sentence has to '
            'promise keeping — copy that cried destruction over a pause is how '
            'a user learns to fear switching');
    expect(find.textContaining('pick it back up any time'), findsOneWidget,
        reason: 'the way back is what makes the rule liveable rather than a '
            'wall, and the question is the one place it must be said');
  });

  testWidgets('a begin with nothing to displace still says what it does',
      (tester) async {
    await openDialog(tester,
        programName: 'Sample Program',
        displacesCurrentRun: false,
        displacedName: null);

    expect(find.text('Begin "Sample Program"?'), findsOneWidget);
    expect(find.text('This starts a new run, from your first workout.'),
        findsOneWidget,
        reason: 'the gate is always there now, so the case it used to skip is '
            'the one it most has to be worth reading: with nothing running, '
            'the implication is simply that a new attempt starts');
  });

  testWidgets('a resume with nothing to displace says it picks up where it left'
      ' off', (tester) async {
    await openDialog(tester,
        entry: RunEntry.resume,
        programName: 'Lambda',
        displacesCurrentRun: false,
        displacedName: null);

    expect(find.text('Resume "Lambda"?'), findsOneWidget);
    expect(find.text('This picks your run back up where you left off.'),
        findsOneWidget,
        reason: 'resuming is not beginning — a dialog that said "starts a new '
            'run" over a paused one would make the user doubt the whole point '
            'of pausing');
  });

  testWidgets('a paused run elsewhere is said to stay paused',
      (tester) async {
    await openDialog(tester,
        programName: 'Sample Program',
        displacesCurrentRun: false,
        displacedName: null,
        otherRunPaused: true);

    expect(
        find.text('This starts a new run, from your first workout. '
            'Your paused programs stay paused.'),
        findsOneWidget,
        reason: 'entering a run leaves every paused one exactly where it is, '
            'and this sentence has nowhere else to be said — the case that '
            'prompted the always-ask rule was a user beginning a program while '
            'another sat paused, with nothing on screen to say what had '
            'happened to it');
  });

  testWidgets('on a resume the paused clause says "other"', (tester) async {
    await openDialog(tester,
        entry: RunEntry.resume,
        programName: 'Sample Program',
        displacesCurrentRun: false,
        displacedName: null,
        otherRunPaused: true);

    expect(
        find.text('This picks your run back up where you left off. '
            'Your other paused programs stay paused.'),
        findsOneWidget,
        reason: 'the program being resumed is itself paused, so the bare '
            'sentence would read as including it — and then the dialog would '
            'be promising the opposite of what it is about to do');
  });

  testWidgets('the paused clause stays out of the displacing sentence',
      (tester) async {
    await openDialog(tester, displacedName: 'Lambda', otherRunPaused: true);

    expect(find.textContaining('stay paused'), findsNothing,
        reason: '"paused, not ended" has already said what happens to the run '
            'being left; saying it twice over a warning that is already two '
            'clauses long is how the sentence stops being read');
  });

  testWidgets('the confirm button carries the verb, and returns true',
      (tester) async {
    await openDialog(tester,
        entry: RunEntry.resume,
        programName: 'Lambda',
        displacedName: 'Base');

    expect(find.text('Resume "Lambda"?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });

  testWidgets('an unreadable name is called "another program", not quoted',
      (tester) async {
    await openDialog(tester, displacedName: null);

    expect(find.textContaining('Your current run on another program will be'),
        findsOneWidget,
        reason: 'the name can fail to load — and "another program" is the '
            'phrasing that still makes sense, whereas quoting a missing name '
            'would read as a program that does not exist');
  });

  testWidgets('cancelling returns false', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('dismissing the dialog is a no, not a yes', (tester) async {
    await openDialog(tester);

    // The barrier is how a user backs out without choosing a button.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(answer, isFalse,
        reason: 'a dismissed dialog answers null — read as "go ahead" it would '
            'begin the program the user had just backed away from');
  });
}
