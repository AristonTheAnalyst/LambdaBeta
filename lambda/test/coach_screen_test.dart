import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/athlete.dart';
import 'package:lambda/data/repositories/coach_repository.dart';
import 'package:lambda/features/coach/view/coach_screen.dart';
import 'package:lambda/features/coach/viewmodel/coach_viewmodel.dart';

/// The Coach roster's draw (2026-10-26): accepted athletes, their names, and
/// the empty state that says why nobody is here.
class _FakeCoachRepository extends Fake implements CoachRepository {
  _FakeCoachRepository(this.athletes);

  final List<Athlete> athletes;

  @override
  Stream<List<Athlete>> watchAthletes(String coachUserId) =>
      Stream.value(athletes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, List<Athlete> athletes) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final vm = CoachViewModel(
      repo: _FakeCoachRepository(athletes),
      userId: 'coach-1',
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(home: CoachScreen(viewModel: vm)));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the accepted athletes by name', (tester) async {
    await pump(tester, const [
      Athlete(userId: 'a1', firstName: 'Jamie', lastName: 'Rivera'),
      Athlete(userId: 'a2', firstName: 'Sam'),
    ]);

    expect(find.text('Jamie Rivera'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'the caption count');
    expect(find.text('No athletes yet'), findsNothing);
  });

  testWidgets('an athlete with no synced name still draws a row', (
    tester,
  ) async {
    await pump(tester, const [Athlete(userId: 'a1')]);
    expect(find.text('Athlete'), findsOneWidget);
  });

  testWidgets('the empty state says an invitation must be accepted', (
    tester,
  ) async {
    await pump(tester, const []);

    expect(find.text('No athletes yet'), findsOneWidget);
    expect(
      find.textContaining('accepting your coaching invitation'),
      findsOneWidget,
    );
    expect(find.text('0'), findsOneWidget);
  });
}
