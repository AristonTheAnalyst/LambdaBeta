import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/features/programs/view/program_workout_row.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

/// The row both the program detail screen and the block editor render their
/// workouts with. Null callbacks hide their control — the convention the
/// shared session widgets follow.
void main() {
  testWidgets('renders the name and the badge', (tester) async {
    await tester.pumpWidget(
      _host(
        ProgramWorkoutRow(
          workout: _workout(name: 'Squat Day', notes: 'Heavy singles'),
          badge: 'Session 3',
        ),
      ),
    );

    expect(find.text('Squat Day'), findsOneWidget);
    expect(find.text('Heavy singles'), findsOneWidget);
    expect(find.text('Session 3'), findsOneWidget);
  });

  testWidgets('no badge, no dragIndex → no chrome for them',
      (tester) async {
    await tester.pumpWidget(_host(ProgramWorkoutRow(workout: _workout())));

    expect(find.text('Session 1'), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byType(SwipeActions), findsNothing,
        reason: 'no actions means no drawer, not an empty one');
  });

  testWidgets('a dragIndex adds the handle; actions add the drawer',
      (tester) async {
    await tester.pumpWidget(
      _host(
        ProgramWorkoutRow(
          workout: _workout(),
          dragIndex: 0,
          swipeActions: [
            SwipeAction(
              icon: Icons.copy_rounded,
              label: 'Duplicate',
              color: Colors.blue,
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.drag_handle), findsOneWidget);
    expect(find.byType(SwipeActions), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('tapping the card opens the workout', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        ProgramWorkoutRow(
          workout: _workout(name: 'Squat Day'),
          onTap: () => opened++,
        ),
      ),
    );

    await tester.tap(find.text('Squat Day'));
    expect(opened, 1);
  });
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

PlannedSession _workout({String name = 'Bench Day', String? notes}) =>
    PlannedSession(
      sessionId: 'w1',
      userId: 'u1',
      name: name,
      notes: notes,
    );
