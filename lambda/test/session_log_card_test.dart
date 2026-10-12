import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/shared/widgets/confirm_delete_session_dialog.dart';
import 'package:lambda/shared/widgets/session_log_card.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

/// A completed session with [setCount] logged sets — nothing else about the
/// rows matters to the card's chrome.
SessionWithSets _session({int setCount = 2}) {
  final session = Session(
    sessionId: 's1',
    userId: 'u1',
    createdDatetime: DateTime(2026, 9, 15, 9, 30),
    endDatetime: DateTime(2026, 9, 15, 10, 30),
    preFeeling: 3,
    feeling: 4,
  );
  return SessionWithSets(
    session: session,
    sets: [
      for (var i = 0; i < setCount; i++)
        SessionExerciseSet(
          sessionExerciseSetId: 'set$i',
          sessionExerciseId: 'se1',
          sessionId: 's1',
          userId: 'u1',
          setNumber: i + 1,
          weight: 60,
          reps: const [8],
          exerciseId: 'ex1',
          exerciseName: 'Bench Press',
        ),
    ],
  );
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('no onDelete → the card carries no swipe drawer', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionLogCard(
          workout: _session(),
          prsByExercise: const {},
          onTap: () {},
        ),
      ),
    );

    expect(find.byType(SwipeActions), findsNothing);
  });

  testWidgets('onDelete → swipe reveals Delete, which runs it', (tester) async {
    var deleted = 0;
    var tapped = 0;

    await tester.pumpWidget(
      _host(
        SessionLogCard(
          workout: _session(),
          prsByExercise: const {},
          onDelete: () => deleted++,
          onTap: () => tapped++,
        ),
      ),
    );

    expect(find.byType(SwipeActions), findsOneWidget);

    // At rest the drawer sits behind the card at zero opacity: its delete
    // button is in the tree, but the card owns that hit area.
    await tester.tap(find.byIcon(Icons.delete_outline), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tapped, 1, reason: 'the card owns the hit area while shut');
    expect(deleted, 0, reason: 'the drawer stays shut until swiped');

    await tester.drag(find.text('Bench Press'), const Offset(-120, 0));
    await tester.pumpAndSettle();

    // Drop the at-rest tap so the assertions below read against the swipe.
    tapped = 0;
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(deleted, 1, reason: 'the drawer action runs onDelete');
    expect(tapped, 0, reason: 'the drawer must not open the session');
  });

  testWidgets('tapping the card body still opens the session', (tester) async {
    var deleted = 0;
    var tapped = 0;

    await tester.pumpWidget(
      _host(
        SessionLogCard(
          workout: _session(),
          prsByExercise: const {},
          onDelete: () => deleted++,
          onTap: () => tapped++,
        ),
      ),
    );

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(deleted, 0);
  });

  testWidgets('the confirmation warns with the set count and defaults to no',
      (tester) async {
    bool? result;

    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await confirmDeleteSession(context, setCount: 3);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Session'), findsOneWidget);
    expect(
      find.text(
          "Delete this session and its 3 logged sets? This can't be undone."),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('confirming the warning returns true, and a single set is '
      'singular', (tester) async {
    bool? result;

    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await confirmDeleteSession(context, setCount: 1);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          "Delete this session and its 1 logged set? This can't be undone."),
      findsOneWidget,
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('an empty session drops the set clause entirely',
      (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => confirmDeleteSession(context, setCount: 0),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text("Delete this session? This can't be undone."),
      findsOneWidget,
    );
  });
}
