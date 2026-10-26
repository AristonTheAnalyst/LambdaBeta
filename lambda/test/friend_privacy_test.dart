import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/friend.dart';
import 'package:lambda/data/repositories/friend_repository.dart';
import 'package:lambda/features/friends/view/friends_screen.dart';
import 'package:lambda/features/friends/viewmodel/friends_viewmodel.dart';

/// Per-friend privacy tiers (2026-10-26, #23): the flag rides the caller's own
/// `friend_relationship` row, the sheet writes through the ViewModel, and the
/// first tier is not a choice.
class _FakeFriendRepository extends Fake implements FriendRepository {
  _FakeFriendRepository(this.friends, {this.failWrites = false});

  final List<Friend> friends;
  final bool failWrites;
  final writes = <(String, bool)>[];

  @override
  Stream<List<Friend>> watchFriends(String userId) => Stream.value(friends);

  @override
  Stream<String?> watchMyCode(String userId) => Stream.value('ABCDEFGH');

  @override
  Future<void> setShareNotes(
    String userId,
    String friendId,
    bool shareNotes,
  ) async {
    if (failWrites) throw Exception('local write failed');
    writes.add((friendId, shareNotes));
  }
}

Friend _friend({bool shareNotes = false}) => Friend(
  userId: 'friend-1',
  firstName: 'Jamie',
  createdDate: DateTime.utc(2026, 10, 20),
  shareNotes: shareNotes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Friend — the note tier', () {
    test('share_notes reads as a flag, absent as numbers only', () {
      Map<String, dynamic> row(Object? value) => {
        'friend_user_id': 'friend-1',
        'share_notes': value,
      };
      expect(Friend.fromMap(row(1)).shareNotes, isTrue);
      expect(Friend.fromMap(row(0)).shareNotes, isFalse);
      expect(
        Friend.fromMap(row(null)).shareNotes,
        isFalse,
        reason: 'a row that predates the column reads as the default tier',
      );
    });

    test('toMap writes the mirror encoding', () {
      expect(_friend(shareNotes: true).toMap()['share_notes'], 1);
      expect(_friend().toMap()['share_notes'], 0);
    });
  });

  group('FriendsViewModel.setShareNotes', () {
    test('hands the friend and the choice to the repository', () async {
      final repo = _FakeFriendRepository([_friend()]);
      final vm = FriendsViewModel(repo: repo, userId: 'me');
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      expect(await vm.setShareNotes(_friend(), true), isTrue);
      expect(repo.writes, [('friend-1', true)]);
    });

    test('a failed write answers false and records the sentence', () async {
      final repo = _FakeFriendRepository([_friend()], failWrites: true);
      final vm = FriendsViewModel(repo: repo, userId: 'me');
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      expect(await vm.setShareNotes(_friend(), true), isFalse);
      expect(vm.state.value.error, isNotNull);
    });
  });

  group('the per-friend privacy sheet', () {
    Future<FriendsViewModel> pumpFriends(
      WidgetTester tester,
      _FakeFriendRepository repo,
    ) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vm = FriendsViewModel(repo: repo, userId: 'me');
      addTearDown(vm.dispose);
      await tester.pumpWidget(MaterialApp(home: FriendsScreen(viewModel: vm)));
      await tester.pumpAndSettle();
      return vm;
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.drag(find.text('Jamie'), const Offset(-120, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
    }

    testWidgets('draws both tiers, the notes one off by default', (
      tester,
    ) async {
      await pumpFriends(tester, _FakeFriendRepository([_friend()]));
      await openSheet(tester);

      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Training and sets'), findsOneWidget);
      expect(find.text('Exercise and session notes'), findsOneWidget);
      expect(
        find.byIcon(Icons.check_circle),
        findsOneWidget,
        reason: 'only the always-on tier is marked',
      );
    });

    testWidgets('the always-on tier cannot be turned off', (tester) async {
      final repo = _FakeFriendRepository([_friend()]);
      await pumpFriends(tester, repo);
      await openSheet(tester);

      await tester.tap(find.text('Training and sets'));
      await tester.pumpAndSettle();

      expect(repo.writes, isEmpty);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('tapping the notes tier writes, and writes back off', (
      tester,
    ) async {
      final repo = _FakeFriendRepository([_friend()]);
      await pumpFriends(tester, repo);
      await openSheet(tester);

      await tester.tap(find.text('Exercise and session notes'));
      await tester.pumpAndSettle();
      expect(repo.writes, [('friend-1', true)]);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

      await tester.tap(find.text('Exercise and session notes'));
      await tester.pumpAndSettle();
      expect(repo.writes, [('friend-1', true), ('friend-1', false)]);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('a sheet opened on a sharing friend starts marked', (
      tester,
    ) async {
      await pumpFriends(
        tester,
        _FakeFriendRepository([_friend(shareNotes: true)]),
      );
      await openSheet(tester);

      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });

    testWidgets('a failed write keeps the old mark and says so', (
      tester,
    ) async {
      await pumpFriends(
        tester,
        _FakeFriendRepository([_friend()], failWrites: true),
      );
      await openSheet(tester);

      await tester.tap(find.text('Exercise and session notes'));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.check_circle),
        findsOneWidget,
        reason: 'a choice that did not land must not read as one that did',
      );
      expect(
        find.textContaining('Something went wrong'),
        findsOneWidget,
        reason: 'the failure is stated where the choice was made',
      );
    });
  });
}
