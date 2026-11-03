import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/friend.dart';
import 'package:lambda/data/repositories/friend_repository.dart';
import 'package:lambda/features/friends/view/friends_screen.dart';
import 'package:lambda/features/friends/viewmodel/friend_profile_viewmodel.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  group('FriendProfileViewModel.setShareNotes', () {
    test('hands the friend and the choice to the repository', () async {
      final repo = _FakeFriendRepository([_friend()]);
      final vm = FriendProfileViewModel(
        me: 'me',
        friendId: 'friend-1',
        friendRepo: repo,
      );
      addTearDown(vm.dispose);

      expect(await vm.setShareNotes(true), isTrue);
      expect(repo.writes, [('friend-1', true)]);
    });

    test('a failed write answers false and records the sentence', () async {
      final repo = _FakeFriendRepository([_friend()], failWrites: true);
      final vm = FriendProfileViewModel(
        me: 'me',
        friendId: 'friend-1',
        friendRepo: repo,
      );
      addTearDown(vm.dispose);

      expect(await vm.setShareNotes(true), isFalse);
      expect(vm.state.value.error, isNotNull);
    });
  });

  group('the per-friend privacy sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      Friend friend, {
      required Future<bool> Function(bool shareNotes) onShareNotes,
      String? Function()? errorOf,
    }) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFriendPrivacySheet(
                  context,
                  friend: friend,
                  onShareNotes: onShareNotes,
                  errorOf: errorOf,
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

    testWidgets('draws both tiers, the notes one off by default', (
      tester,
    ) async {
      await pumpSheet(tester, _friend(), onShareNotes: (_) async => true);

      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Training and sets'), findsOneWidget);
      expect(find.text('Exercise and session notes'), findsOneWidget);
      expect(
        find.byIcon(LucideIcons.circleCheck),
        findsOneWidget,
        reason: 'only the always-on tier is marked',
      );
    });

    testWidgets('the always-on tier cannot be turned off', (tester) async {
      final writes = <bool>[];
      await pumpSheet(tester, _friend(), onShareNotes: (v) async {
        writes.add(v);
        return true;
      });

      await tester.tap(find.text('Training and sets'));
      await tester.pumpAndSettle();

      expect(writes, isEmpty);
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
    });

    testWidgets('tapping the notes tier writes, and writes back off', (
      tester,
    ) async {
      final writes = <bool>[];
      await pumpSheet(tester, _friend(), onShareNotes: (v) async {
        writes.add(v);
        return true;
      });

      await tester.tap(find.text('Exercise and session notes'));
      await tester.pumpAndSettle();
      expect(writes, [true]);
      expect(find.byIcon(LucideIcons.circleCheck), findsNWidgets(2));

      await tester.tap(find.text('Exercise and session notes'));
      await tester.pumpAndSettle();
      expect(writes, [true, false]);
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
    });

    testWidgets('a sheet opened on a sharing friend starts marked', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        _friend(shareNotes: true),
        onShareNotes: (_) async => true,
      );

      expect(find.byIcon(LucideIcons.circleCheck), findsNWidgets(2));
    });

    testWidgets('a failed write keeps the old mark and says so', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        _friend(),
        onShareNotes: (_) async => false,
        errorOf: () => 'Something went wrong. Please try again.',
      );

      await tester.tap(find.text('Exercise and session notes'));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(LucideIcons.circleCheck),
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
