import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/coach_assignment.dart';
import 'package:lambda/data/models/coach_relationship.dart';
import 'package:lambda/data/models/friend.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/repositories/coach_repository.dart';
import 'package:lambda/data/repositories/friend_repository.dart';
import 'package:lambda/features/friends/view/friend_profile_screen.dart';
import 'package:lambda/features/friends/view/friends_screen.dart';
import 'package:lambda/features/friends/viewmodel/friend_profile_viewmodel.dart';
import 'package:lambda/features/friends/viewmodel/friends_viewmodel.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// The Social tab (2026-10-30): one friends list whose rows carry a COACH /
/// CLIENT pill, and a friend profile that owns every friendship verb —
/// coaching asks in both directions, the nickname, the note tier, removal.
class _FakeFriendRepository extends Fake implements FriendRepository {
  _FakeFriendRepository([this.friends = const []]);

  List<Friend> friends;
  final removed = <String>[];
  final nicknames = <(String, String?)>[];
  final noteWrites = <(String, bool)>[];

  @override
  Stream<List<Friend>> watchFriends(String userId) => Stream.value(friends);

  @override
  Stream<String?> watchMyCode(String userId) => Stream.value('ABCDEFGH');

  @override
  Future<void> removeFriend(String userId, String friendId) async {
    removed.add(friendId);
    friends = [for (final f in friends) if (f.userId != friendId) f];
  }

  @override
  Future<void> setNickname(
    String userId,
    String friendId,
    String? nickname,
  ) async {
    nicknames.add((friendId, nickname));
  }

  @override
  Future<void> setShareNotes(
    String userId,
    String friendId,
    bool shareNotes,
  ) async {
    noteWrites.add((friendId, shareNotes));
  }
}

class _FakeCoachRepository extends Fake implements CoachRepository {
  _FakeCoachRepository({this.edges = const []});

  List<CoachRelationship> edges;
  final asks = <String>[];
  final offers = <String>[];
  final accepts = <String>[];
  final removed = <(String, String)>[];

  @override
  Stream<List<CoachRelationship>> watchRelationships(String userId) =>
      Stream.value(edges);

  @override
  Stream<List<CoachAssignment>> watchAssignments(String userId) =>
      Stream.value(const []);

  @override
  Future<List<PlannedSession>> assignableWorkouts(String coachId) async =>
      const [];

  @override
  Future<CoachingRequest> requestCoaching(
    String userId,
    String coachUserId,
  ) async {
    asks.add(coachUserId);
    return CoachingRequest(
      coachUserId: coachUserId,
      athleteUserId: 'me',
      created: true,
    );
  }

  @override
  Future<CoachingRequest> offerCoaching(
    String userId,
    String athleteUserId,
  ) async {
    offers.add(athleteUserId);
    return CoachingRequest(
      coachUserId: 'me',
      athleteUserId: athleteUserId,
      created: true,
    );
  }

  @override
  Future<void> acceptRequest(String userId, String otherUserId) async {
    accepts.add(otherUserId);
  }

  @override
  Future<void> remove(String userId, String otherUserId) async {
    removed.add((userId, otherUserId));
  }
}

Friend _friend({
  String id = 'friend-1',
  String name = 'Jamie',
  bool coachesMe = false,
  bool iCoachThem = false,
}) => Friend(
  userId: id,
  firstName: name,
  createdDate: DateTime.utc(2026, 10, 20),
  coachesMe: coachesMe,
  iCoachThem: iCoachThem,
);

CoachRelationship _edge({
  String coach = 'friend-1',
  String athlete = 'me',
  String? requestedBy,
  DateTime? accepted,
}) => CoachRelationship(
  coachUserId: coach,
  athleteUserId: athlete,
  requestedByUserId: requestedBy,
  createdDate: DateTime.utc(2026, 10, 28),
  acceptedDate: accepted,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void sizeUp(WidgetTester tester) {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpList(WidgetTester tester, List<Friend> friends) async {
    sizeUp(tester);
    final vm = FriendsViewModel(
      repo: _FakeFriendRepository(friends),
      userId: 'me',
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(home: FriendsScreen(viewModel: vm)));
    await tester.pumpAndSettle();
  }

  Future<(FriendProfileViewModel, _FakeCoachRepository, _FakeFriendRepository)>
  pumpProfile(
    WidgetTester tester, {
    List<Friend> friends = const [],
    List<CoachRelationship> edges = const [],
  }) async {
    sizeUp(tester);
    final coachRepo = _FakeCoachRepository(edges: edges);
    final friendRepo = _FakeFriendRepository(
      friends.isEmpty ? [_friend()] : friends,
    );
    final vm = FriendProfileViewModel(
      me: 'me',
      friendId: 'friend-1',
      friendRepo: friendRepo,
      coachRepo: coachRepo,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FriendProfileScreen(
          friendId: 'friend-1',
          initialName: 'Jamie',
          viewModel: vm,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (vm, coachRepo, friendRepo);
  }

  group('The Social list', () {
    testWidgets('the header names the hub and no coaching panel is drawn', (
      tester,
    ) async {
      await pumpList(tester, [_friend()]);

      expect(find.text('Social'), findsOneWidget);
      expect(find.text('Coach'), findsNothing);
      expect(find.text('Friends'), findsNothing);
    });

    testWidgets('a plain friendship wears no pill', (tester) async {
      await pumpList(tester, [_friend()]);

      expect(find.text('COACH'), findsNothing);
      expect(find.text('CLIENT'), findsNothing);
    });

    testWidgets('a coach and a client each wear their pill', (tester) async {
      await pumpList(tester, [
        _friend(id: 'coach-1', name: 'Sam', coachesMe: true),
        _friend(id: 'client-1', name: 'Rivera', iCoachThem: true),
      ]);

      expect(find.text('COACH'), findsOneWidget);
      expect(find.text('CLIENT'), findsOneWidget);
    });
  });

  group('The friend profile — no coaching edge', () {
    testWidgets('offers both asks, and asking reaches the repository', (
      tester,
    ) async {
      final (_, coachRepo, _) = await pumpProfile(tester);

      expect(find.text('No coaching yet'), findsOneWidget);
      final ask = find.widgetWithText(GlassButton, 'Ask to be coached');
      expect(ask, findsOneWidget);
      expect(
        find.widgetWithText(GlassButton, 'Offer to coach'),
        findsOneWidget,
      );

      await tester.tap(ask);
      await tester.pumpAndSettle();
      expect(coachRepo.asks, ['friend-1']);
      expect(find.text('Asked Jamie to coach you'), findsOneWidget);
    });

    testWidgets('offering reaches the repository', (tester) async {
      final (_, coachRepo, _) = await pumpProfile(tester);

      await tester.tap(find.widgetWithText(GlassButton, 'Offer to coach'));
      await tester.pumpAndSettle();
      expect(coachRepo.offers, ['friend-1']);
    });
  });

  group('The friend profile — a pending ask', () {
    testWidgets('one they asked shows Accept and Decline', (tester) async {
      final (_, coachRepo, _) = await pumpProfile(
        tester,
        edges: [_edge(requestedBy: 'friend-1')],
      );

      expect(find.text('Jamie wants to coach you'), findsOneWidget);
      await tester.tap(find.widgetWithText(GlassButton, 'Accept'));
      await tester.pumpAndSettle();

      // The athlete's consent statement stands between the tap and the
      // write; only its Accept reaches the repository.
      expect(
        find.widgetWithText(GlassButton, 'Accept coaching'),
        findsOneWidget,
      );
      expect(coachRepo.accepts, isEmpty);

      await tester.tap(find.widgetWithText(GlassButton, 'Accept coaching'));
      await tester.pumpAndSettle();
      expect(coachRepo.accepts, ['friend-1']);
    });

    testWidgets('one the caller asked can be cancelled', (tester) async {
      final (_, coachRepo, _) = await pumpProfile(
        tester,
        edges: [_edge(requestedBy: 'me')],
      );

      expect(find.text('Waiting on Jamie'), findsOneWidget);
      await tester.tap(find.widgetWithText(GlassButton, 'Cancel request'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel Request'), findsOneWidget);

      await tester.tap(find.widgetWithText(GlassButton, 'Withdraw'));
      await tester.pumpAndSettle();
      expect(coachRepo.removed, [('me', 'friend-1')]);
    });
  });

  group('The friend profile — an accepted edge', () {
    testWidgets('a coach is named, and can be ended', (tester) async {
      final (_, coachRepo, _) = await pumpProfile(
        tester,
        friends: [_friend(coachesMe: true)],
        edges: [_edge(accepted: DateTime.utc(2026, 10, 29))],
      );

      expect(find.text('COACH'), findsOneWidget);
      expect(find.text('Jamie coaches you'), findsOneWidget);

      await tester.tap(find.widgetWithText(GlassButton, 'End coaching'));
      await tester.pumpAndSettle();
      // The dialog's confirm shares the verb.
      await tester.tap(find.widgetWithText(GlassButton, 'End coaching').last);
      await tester.pumpAndSettle();
      expect(coachRepo.removed, [('me', 'friend-1')]);
    });

    testWidgets('a client gets the coach tools', (tester) async {
      await pumpProfile(
        tester,
        friends: [_friend(iCoachThem: true)],
        edges: [
          _edge(
            coach: 'me',
            athlete: 'friend-1',
            requestedBy: 'friend-1',
            accepted: DateTime.utc(2026, 10, 29),
          ),
        ],
      );

      expect(find.text('CLIENT'), findsOneWidget);
      expect(find.text('You coach Jamie'), findsOneWidget);
      expect(
        find.widgetWithText(GlassButton, 'Open as coach'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(GlassButton, 'Assign workout'),
        findsOneWidget,
      );
    });
  });

  group('The friend profile — the friendship itself', () {
    testWidgets('removing a friend asks first, then cuts and leaves', (
      tester,
    ) async {
      final (_, _, friendRepo) = await pumpProfile(tester);

      await tester.scrollUntilVisible(find.text('Remove friend'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GlassButton, 'Remove friend'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Friend'), findsOneWidget);

      await tester.tap(find.widgetWithText(GlassButton, 'Keep it'));
      await tester.pumpAndSettle();
      expect(friendRepo.removed, isEmpty);

      await tester.scrollUntilVisible(find.text('Remove friend'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GlassButton, 'Remove friend'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GlassButton, 'Remove').last);
      await tester.pumpAndSettle();
      expect(friendRepo.removed, ['friend-1']);
    });
  });
}
