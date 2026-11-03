import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/lambda_exception.dart';
import 'package:lambda/data/models/coach_assignment.dart';
import 'package:lambda/data/models/coach_feedback.dart';
import 'package:lambda/data/models/coach_relationship.dart';
import 'package:lambda/data/models/friend.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/repositories/coach_repository.dart';
import 'package:lambda/data/repositories/friend_repository.dart';
import 'package:lambda/features/coach/view/assign_workout_sheet.dart';
import 'package:lambda/features/friends/viewmodel/friend_profile_viewmodel.dart';
import 'package:lambda/features/logs/view/session_detail_screen.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// Coach authoring (2026-10-26, #24): the assignment and feedback models, the
/// ViewModel's two new slices and its commands, the Coach screen's new
/// sections, and the two sheets. The database half — the name remap and the
/// transaction that copies a workout into the athlete's library — is
/// `integration_test/coach_authoring_test.dart`'s.
class _FakeFriendRepository extends Fake implements FriendRepository {
  @override
  Stream<List<Friend>> watchFriends(String userId) => Stream.value(const []);

  @override
  Stream<String?> watchMyCode(String userId) => Stream.value(null);
}

class _FakeCoachRepository extends Fake implements CoachRepository {
  _FakeCoachRepository({this.workouts = const []});

  List<PlannedSession> workouts;

  final assigned = <(String, String, String?)>[];
  final acceptedAssignments = <String>[];
  final declinedAssignments = <String>[];
  final withdrawnAssignments = <String>[];
  Object? error;

  @override
  Stream<List<CoachRelationship>> watchRelationships(String userId) =>
      Stream.value(const []);

  @override
  Stream<List<CoachAssignment>> watchAssignments(String userId) =>
      Stream.value(const []);

  @override
  Future<List<PlannedSession>> assignableWorkouts(String coachId) async =>
      workouts;

  @override
  Future<CoachAssignment> createAssignment({
    required String coachId,
    required String athleteId,
    required PlannedSession workout,
    String? note,
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    assigned.add((athleteId, workout.sessionId, note));
    return _assignment(
      coach: coachId,
      athlete: athleteId,
      name: workout.name,
      note: note,
    );
  }

  @override
  Future<PlannedSession> acceptAssignment(
    String athleteId,
    CoachAssignment assignment,
  ) async {
    acceptedAssignments.add(assignment.assignmentId);
    return PlannedSession(
      sessionId: 'copy-${assignment.assignmentId}',
      userId: athleteId,
      name: assignment.name,
      coachAssignmentId: assignment.assignmentId,
    );
  }

  @override
  Future<void> declineAssignment(
    String athleteId,
    CoachAssignment assignment,
  ) async {
    declinedAssignments.add(assignment.assignmentId);
  }

  @override
  Future<void> withdrawAssignment(
    String coachId,
    CoachAssignment assignment,
  ) async {
    withdrawnAssignments.add(assignment.assignmentId);
  }
}

CoachAssignment _assignment({
  String id = 'as-1',
  String coach = 'coach-1',
  String athlete = 'me',
  String name = 'Push A',
  String? note,
  DateTime? created,
  DateTime? accepted,
  DateTime? declined,
}) => CoachAssignment(
  assignmentId: id,
  coachUserId: coach,
  athleteUserId: athlete,
  plannedSessionId: 'ws-1',
  name: name,
  note: note,
  snapshotContent: '{"schema":2}',
  namesJson: '{"exercises":{"ex-1":"Bench Press"},'
      '"variations":{"var-1":"Pause"}}',
  createdDate: created ?? DateTime.utc(2026, 10, 24, 12),
  acceptedDate: accepted,
  declinedDate: declined,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoachAssignment — the hand-off row', () {
    test('round-trips through the mirror encoding', () {
      final row = _assignment(
        note: 'Keep the bar path tight',
        created: DateTime.utc(2026, 10, 24, 9, 30),
        accepted: DateTime.utc(2026, 10, 25, 8),
      ).toMap();
      final back = CoachAssignment.fromMap(row);
      expect(back.assignmentId, 'as-1');
      expect(back.coachUserId, 'coach-1');
      expect(back.athleteUserId, 'me');
      expect(back.plannedSessionId, 'ws-1');
      expect(back.name, 'Push A');
      expect(back.note, 'Keep the bar path tight');
      expect(back.isAccepted, isTrue);
      expect(back.isPending, isFalse);
      expect(back.isDeclined, isFalse);
      expect(back.snapshotContent, '{"schema":2}');
      expect(back.createdDate, DateTime.utc(2026, 10, 24, 9, 30));
    });

    test('status is two nullable stamps', () {
      expect(_assignment().isPending, isTrue);
      expect(_assignment(accepted: DateTime.utc(2026, 10, 25)).isAccepted, isTrue);
      expect(_assignment(declined: DateTime.utc(2026, 10, 25)).isDeclined, isTrue);
    });

    test('names_json decodes into the two id maps', () {
      final assignment = _assignment();
      expect(assignment.exerciseNames, {'ex-1': 'Bench Press'});
      expect(assignment.variationNames, {'var-1': 'Pause'});
    });

    test('a missing or malformed names_json reads as empty, never throws', () {
      final noNames = CoachAssignment.fromMap({
        'assignment_id': 'as-2',
        'coach_user_id': 'coach-1',
        'athlete_user_id': 'me',
        'planned_session_id': 'ws-1',
        'name': 'Push A',
        'snapshot_content': '{"schema":2}',
      });
      expect(noNames.exerciseNames, isEmpty);
      expect(noNames.variationNames, isEmpty);

      final broken = CoachAssignment.fromMap({
        'assignment_id': 'as-3',
        'coach_user_id': 'coach-1',
        'athlete_user_id': 'me',
        'planned_session_id': 'ws-1',
        'name': 'Push A',
        'snapshot_content': '{"schema":2}',
        'names_json': 'not json',
      });
      expect(broken.exerciseNames, isEmpty);
    });
  });

  group('CoachFeedback — one note per (coach, session)', () {
    test('round-trips and reads its display date', () {
      final feedback = CoachFeedback(
        feedbackId: 'fb-1',
        coachUserId: 'coach-1',
        athleteUserId: 'me',
        sessionId: 's-1',
        body: 'Great depth',
        createdDate: DateTime.utc(2026, 10, 24, 9),
        editedDate: DateTime.utc(2026, 10, 25, 9),
      );
      final back = CoachFeedback.fromMap(feedback.toMap());
      expect(back.feedbackId, 'fb-1');
      expect(back.body, 'Great depth');
      expect(back.isEdited, isTrue);
      expect(back.displayDate, DateTime.utc(2026, 10, 25, 9));
    });

    test('an unedited note displays its first write', () {
      final feedback = CoachFeedback(
        feedbackId: 'fb-1',
        coachUserId: 'coach-1',
        athleteUserId: 'me',
        sessionId: 's-1',
        body: 'Great depth',
        createdDate: DateTime.utc(2026, 10, 24, 9),
      );
      expect(feedback.isEdited, isFalse);
      expect(feedback.displayDate, DateTime.utc(2026, 10, 24, 9));
    });
  });

  group('The assign sheet', () {
    testWidgets('lists the coach\'s workouts and sends the chosen one', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final repo = _FakeCoachRepository(
        workouts: const [
          PlannedSession(sessionId: 'ws-1', userId: 'me', name: 'Push A'),
          PlannedSession(sessionId: 'ws-2', userId: 'me', name: 'Pull B'),
        ],
      );
      final vm = FriendProfileViewModel(
        me: 'me',
        friendId: 'sam',
        friendRepo: _FakeFriendRepository(),
        coachRepo: repo,
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAssignWorkoutSheet(
                  context,
                  vm: vm,
                  athleteName: 'Sam',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Assign a workout'), findsOneWidget);
      expect(find.text('Push A'), findsOneWidget);
      expect(find.text('Pull B'), findsOneWidget);
      // Nothing is chosen yet: the send button is spent.
      expect(
        tester
            .widget<GlassButton>(
              find.byKey(const ValueKey('assign-workout-send')),
            )
            .disabled,
        isTrue,
      );

      await tester.tap(find.text('Pull B'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Focus on the pull');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-workout-send')));
      await tester.pumpAndSettle();

      expect(repo.assigned.single, ('sam', 'ws-2', 'Focus on the pull'));
      expect(find.text('Assign a workout'), findsNothing);
    });

    testWidgets('a refused send stays open and says why', (tester) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final repo = _FakeCoachRepository(
        workouts: const [
          PlannedSession(sessionId: 'ws-1', userId: 'me', name: 'Push A'),
        ],
      )..error = LambdaException('That workout is already pending.');
      final vm = FriendProfileViewModel(
        me: 'me',
        friendId: 'sam',
        friendRepo: _FakeFriendRepository(),
        coachRepo: repo,
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAssignWorkoutSheet(
                  context,
                  vm: vm,
                  athleteName: 'Sam',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Push A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-workout-send')));
      await tester.pumpAndSettle();

      // The sheet is still up, carrying the view model's own sentence.
      expect(find.text('Assign a workout'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assign-workout-error')),
        findsOneWidget,
      );
      expect(find.text('That workout is already pending.'), findsOneWidget);
    });
  });

  group('The feedback sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      CoachFeedback? feedback,
      required Future<bool> Function(String body) onSave,
      Future<bool> Function()? onDelete,
      String? Function()? errorText,
    }) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCoachFeedbackSheet(
                  context,
                  eyebrow: 'Push A',
                  feedback: feedback,
                  onSave: onSave,
                  onDelete: onDelete,
                  errorText: errorText,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    GlassButton saveButton(WidgetTester tester) => tester.widget<GlassButton>(
      find.byKey(const ValueKey('session-coach-feedback-save')),
    );

    testWidgets('Save is spent until there is text, then writes it', (
      tester,
    ) async {
      String? saved;
      await pumpSheet(
        tester,
        onSave: (body) async {
          saved = body;
          return true;
        },
      );

      expect(find.text('Coach Feedback'), findsOneWidget);
      expect(saveButton(tester).disabled, isTrue);

      await tester.enterText(find.byType(TextField), '  Tight bar path  ');
      await tester.pumpAndSettle();
      expect(saveButton(tester).disabled, isFalse);

      await tester.tap(find.byKey(const ValueKey('session-coach-feedback-save')));
      await tester.pumpAndSettle();

      expect(saved, '  Tight bar path  ');
      expect(find.text('Coach Feedback'), findsNothing);
    });

    testWidgets('an unchanged rewrite writes nothing', (tester) async {
      var calls = 0;
      await pumpSheet(
        tester,
        feedback: CoachFeedback(
          feedbackId: 'fb-1',
          coachUserId: 'coach-1',
          athleteUserId: 'me',
          sessionId: 's-1',
          body: 'Great depth',
          createdDate: DateTime.utc(2026, 10, 24),
        ),
        onSave: (_) async {
          calls++;
          return true;
        },
        onDelete: () async => true,
      );

      expect(saveButton(tester).disabled, isTrue);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('session-coach-feedback-save')));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('Delete asks first and only then calls the callback', (
      tester,
    ) async {
      var deleted = 0;
      await pumpSheet(
        tester,
        feedback: CoachFeedback(
          feedbackId: 'fb-1',
          coachUserId: 'coach-1',
          athleteUserId: 'me',
          sessionId: 's-1',
          body: 'Great depth',
          createdDate: DateTime.utc(2026, 10, 24),
        ),
        onSave: (_) async => true,
        onDelete: () async {
          deleted++;
          return true;
        },
      );

      await tester.tap(find.byKey(const ValueKey('session-coach-feedback-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete feedback?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Keep it'));
      await tester.pumpAndSettle();
      expect(deleted, 0);

      await tester.tap(
        find.byKey(const ValueKey('session-coach-feedback-delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete feedback'));
      await tester.pumpAndSettle();
      expect(deleted, 1);
    });

    testWidgets('a refused save draws the caller\'s sentence, not a generic one',
        (tester) async {
      await pumpSheet(
        tester,
        onSave: (_) async => false,
        errorText: () => 'Feedback is not reaching the server right now.',
      );

      await tester.enterText(find.byType(TextField), 'Tight bar path');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-coach-feedback-save')));
      await tester.pumpAndSettle();

      // The sheet stays up, carrying the real reason under the field.
      expect(find.text('Coach Feedback'), findsOneWidget);
      expect(
        find.text('Feedback is not reaching the server right now.'),
        findsOneWidget,
      );
    });
  });

  group('The viewer gate', () {
    test('a read-only friend viewer never gains the coach door', () {
      // The card only offers a write door when `canCoach` is passed, and only
      // the coach route passes it (2026-10-26, #24).
      const friendViewer = SessionDetailScreen(
        sessionId: 's-1',
        userId: 'friend-1',
        readOnly: true,
        navRoute: '/friends',
      );
      expect(friendViewer.canCoach, isFalse);
    });
  });
}
