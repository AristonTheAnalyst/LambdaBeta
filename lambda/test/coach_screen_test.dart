import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/coach_assignment.dart';
import 'package:lambda/data/models/coach_relationship.dart';
import 'package:lambda/data/repositories/coach_repository.dart';
import 'package:lambda/features/coach/view/coach_screen.dart';
import 'package:lambda/features/coach/viewmodel/coach_viewmodel.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// The Coach page's draw (2026-10-26, #22): the four slices, the invitation
/// verbs, and the invite sheet.
class _FakeCoachRepository extends Fake implements CoachRepository {
  _FakeCoachRepository(this.rows);

  final List<CoachRelationship> rows;
  final invites = <String>[];
  final accepted = <String>[];
  final removed = <String>[];

  @override
  Stream<List<CoachRelationship>> watchRelationships(String userId) =>
      Stream.value(rows);

  @override
  Stream<List<CoachAssignment>> watchAssignments(String userId) =>
      Stream.value(const []);

  @override
  Future<CoachInvite> inviteByCode(String userId, String rawCode) async {
    invites.add(rawCode);
    return const CoachInvite(athleteUserId: 'a-new', created: true);
  }

  @override
  Future<void> acceptInvitation(String userId, String coachId) async {
    accepted.add(coachId);
  }

  @override
  Future<void> remove(String userId, String otherId) async {
    removed.add(otherId);
  }
}

CoachRelationship _row({
  required String coach,
  required String athlete,
  String? coachName,
  String? athleteName,
  DateTime? created,
  DateTime? accepted,
}) => CoachRelationship(
  coachUserId: coach,
  athleteUserId: athlete,
  coachFirstName: coachName,
  athleteFirstName: athleteName,
  createdDate: created ?? DateTime.utc(2026, 10, 20, 12),
  acceptedDate: accepted,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakeCoachRepository> pump(
    WidgetTester tester,
    List<CoachRelationship> rows,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _FakeCoachRepository(rows);
    final vm = CoachViewModel(repo: repo, userId: 'me');
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(home: CoachScreen(viewModel: vm)));
    await tester.pumpAndSettle();
    return repo;
  }

  List<CoachRelationship> fullRoster() => [
    _row(
      coach: 'coach-1',
      athlete: 'me',
      coachName: 'Jamie',
      created: DateTime.utc(2026, 10, 24, 12),
    ),
    _row(
      coach: 'me',
      athlete: 'sam',
      athleteName: 'Sam',
      accepted: DateTime.utc(2026, 10, 2),
    ),
    _row(
      coach: 'coach-2',
      athlete: 'me',
      coachName: 'Rivera',
      accepted: DateTime.utc(2026, 10, 3),
    ),
    _row(
      coach: 'me',
      athlete: 'pending',
      created: DateTime.utc(2026, 10, 25, 12),
    ),
  ];

  testWidgets('draws all four slices of the caller\'s coaching edges', (
    tester,
  ) async {
    await pump(tester, fullRoster());

    expect(find.text('INVITATIONS TO YOU'), findsOneWidget);
    expect(find.text('Jamie'), findsOneWidget);
    expect(find.text('Wants to coach you'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    expect(find.text('ATHLETES'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);

    expect(find.text('YOUR COACHES'), findsOneWidget);
    expect(find.text('Rivera'), findsOneWidget);

    expect(find.text('INVITATIONS SENT'), findsOneWidget);
    expect(find.text('Invitation pending'), findsOneWidget);
    // The stream sends nothing about an unaccepted athlete: the pending row
    // carries no name, only when it was sent.
    expect(find.textContaining('Sent '), findsOneWidget);
  });

  testWidgets('Accept hands the invitation to the view model', (tester) async {
    final repo = await pump(tester, fullRoster());

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(repo.accepted, ['coach-1']);
  });

  testWidgets('Decline asks first, and Keep it writes nothing', (tester) async {
    final repo = await pump(tester, fullRoster());

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(find.text('Decline Invitation'), findsOneWidget);

    await tester.tap(find.widgetWithText(GlassButton, 'Keep it'));
    await tester.pumpAndSettle();

    expect(repo.removed, isEmpty);
    expect(find.text('Decline Invitation'), findsNothing);
  });

  testWidgets('Decline confirms through to the removal', (tester) async {
    final repo = await pump(tester, fullRoster());

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GlassButton, 'Decline').last);
    await tester.pumpAndSettle();

    expect(repo.removed, ['coach-1']);
  });

  testWidgets('the invite sheet normalizes the code it sends', (tester) async {
    final repo = await pump(tester, []);

    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pumpAndSettle();
    expect(find.text('Invite an athlete'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abcd-efgh');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(repo.invites, ['ABCDEFGH']);
  });

  testWidgets('the empty state says how coaching starts', (tester) async {
    await pump(tester, []);

    expect(find.text('No coaching yet'), findsOneWidget);
    expect(
      find.textContaining('Invite an athlete with their friend code'),
      findsOneWidget,
    );
    expect(find.text('INVITATIONS TO YOU'), findsNothing);
    expect(find.text('ATHLETES'), findsNothing);
  });
}
