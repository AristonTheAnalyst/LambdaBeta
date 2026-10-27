import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/core/utils/device_id.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/friend.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/friend_repository.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/friends/viewmodel/friends_viewmodel.dart';
import 'package:lambda/features/logs/viewmodel/logs_viewmodel.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';
import 'package:powersync/powersync.dart';

/// The friends feature's data layer against a real local mirror (2026-10-23).
///
/// The SQL RPCs and the friends_data stream itself are server-side and are
/// verified manually with two accounts; everything the client owns is here:
///
/// * an add mirrors ONLY the caller's own directed row (the synthetic id the
///   stream uses) — the reciprocal row is the RPC's, and mirroring it would
///   queue an upload the friend's RLS rejects;
/// * the friend's history reads through the existing read-only surfaces:
///   completed sessions only (the active one never appears), PRs and goals
///   derived per user from the shared timeline cache, exercise notes read
///   under the friend's id;
/// * a removal cuts the local row and drops the friend's cached timeline.
///
///   flutter test integration_test/friends_sync_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const me = 'u1';
  const friend = 'u2';
  const squat = 'ex-squat';

  late Directory dir;
  late PowerSyncDatabase db;
  late _FakeFriendRemote remote;
  late FriendRepository friends;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_friends');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    remote = _FakeFriendRemote(friendUserId: friend);
    friends = FriendRepository(remote: remote);
    // The date bar's live check asks the device's id; the seam keeps the
    // preferences plugin out of a DB-only suite.
    DeviceId.override('test-device');
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() async {
    DeviceId.override(null);
    PastSetsTimelineCache.instance.invalidate();
    await db.close();
    await dir.delete(recursive: true);
  });

  /// The two users the fixture spans: the caller and the friend, with the
  /// friend's name row local (the friends stream delivers it in production).
  Future<void> seedUsers() async {
    for (final (id, first, last) in [
      (me, 'Rocky', 'Zubiri'),
      (friend, 'Jamie', 'Rivera'),
    ]) {
      await db.execute(
        'INSERT INTO dim_user (id, user_id, user_name, user_lastname) '
        'VALUES (?, ?, ?, ?)',
        [id, id, first, last],
      );
    }
  }

  /// Seed the caller's own outgoing row — what the stream would have
  /// delivered after the RPC.
  Future<void> seedOwnFriendshipRow() async {
    await db.execute(
      'INSERT INTO friend_relationship '
      '(id, user_id, friend_user_id, created_date) VALUES (?, ?, ?, ?)',
      [
        '$me-$friend',
        me,
        friend,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  /// The friend's history: one completed session (a 100×5 set — a first PR
  /// and a goal hit — and a flagged 120×5 row that must count for neither),
  /// one ACTIVE session that must never surface, plus a note and a goal.
  Future<({String completedId, SessionExerciseSet set})> seedFriendHistory() async {
    final repo = SessionRepository();
    final completedId = await repo.createSession(friend, deviceId: 'friend-phone');
    final group = await repo.insertSessionExercise(
      sessionId: completedId,
      userId: friend,
      exerciseOrder: 1,
      exerciseId: squat,
    );
    final set = await repo.insertSet(
      sessionExerciseId: group.sessionExerciseId,
      sessionId: completedId,
      userId: friend,
      setNumber: 1,
      weight: 100,
      reps: [5],
    );
    final flagged = await repo.insertSet(
      sessionExerciseId: group.sessionExerciseId,
      sessionId: completedId,
      userId: friend,
      setNumber: 2,
      weight: 120,
      reps: [5],
    );
    await repo.updateSet(flagged.sessionExerciseSetId, isDeleted: true);
    await repo.endSession(completedId);

    // A live session on the friend's phone — never synced to this device.
    await repo.createSession(friend, deviceId: 'friend-phone');

    await ExerciseNoteRepository().createNote(
      friend,
      squat,
      'Chest up, sit back',
      sessionId: completedId,
    );
    await ProgramRepository().createGoal(
      friend,
      Goal(
        goalId: 'g1',
        userId: friend,
        exerciseId: squat,
        targetWeight: 90,
        targetReps: 3,
      ),
    );
    return (completedId: completedId, set: set);
  }

  /// Polls until [condition] holds — PowerSync watches and the VMs' background
  /// reads are asynchronous, and a DB-only suite has no pump to advance.
  Future<void> waitFor(
    bool Function() condition, {
    String? reason,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting${reason == null ? '' : ' for $reason'}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('adding by code mirrors only the caller\'s own row, and the list names '
      'the friend', () async {
    await seedUsers();
    await db.execute(
      'INSERT INTO dim_friend_code (id, user_id, friend_code, created_date) '
      'VALUES (?, ?, ?, ?)',
      [me, me, 'ABCD2345', DateTime.now().toUtc().toIso8601String()],
    );

    final vm = FriendsViewModel(repo: friends, userId: me);
    vm.start();
    addTearDown(vm.dispose);

    await waitFor(
      () => !vm.state.value.isLoading && vm.state.value.myCode != null,
      reason: 'the code card\'s row',
    );
    expect(vm.state.value.myCode, 'ABCD2345');
    expect(vm.state.value.friends, isEmpty);

    // The field's cleaner and the parser are one rule: spaces and the drawn
    // hyphen are noise, lower case is the same code.
    final result = await vm.add(' abcd-efgh ');
    expect(result, isNotNull);
    expect(result!.friend.userId, friend);
    expect(result.friend.displayName, 'Jamie Rivera');
    expect(result.created, isTrue);
    expect(remote.lastCode, 'ABCDEFGH');

    await waitFor(
      () => vm.state.value.friends.length == 1,
      reason: 'the watch to carry the mirrored row',
    );
    final added = vm.state.value.friends.single;
    expect(added.userId, friend);
    expect(
      added.displayName,
      'Jamie Rivera',
      reason: 'the name comes from the friend\'s dim_user row',
    );

    // Exactly one local row — the caller's own. The reciprocal row belongs to
    // the friend (the RPC wrote it server-side); mirroring it here would
    // queue an upload this user's RLS rejects.
    final rows = await db.getAll(
      'SELECT id, user_id, friend_user_id FROM friend_relationship',
    );
    expect(rows, hasLength(1));
    expect(rows.single['id'], '$me-$friend');
    expect(rows.single['user_id'], me);
    expect(rows.single['friend_user_id'], friend);
  });

  test('a friend\'s history reads like the user\'s own — completed only, with '
      'PRs, goal badges and exercise notes', () async {
    await seedUsers();
    await seedOwnFriendshipRow();
    final seeded = await seedFriendHistory();
    PastSetsTimelineCache.instance.invalidate();

    // The list: the completed session only, and only its performed set.
    final logs = LogsViewModel(userId: friend);
    await logs.load();
    addTearDown(logs.dispose);
    expect(logs.state.value.error, isNull);
    expect(
      logs.state.value.sessions.map((w) => w.session.sessionId),
      [seeded.completedId],
      reason: 'the friend\'s active session is never listed',
    );
    expect(
      logs.state.value.sessions.single.sets.map(
        (s) => s.sessionExerciseSetId,
      ),
      [seeded.set.sessionExerciseSetId],
      reason: 'a flagged set is not performed work',
    );

    // The viewer under the friend's id: the same derived reads the user's own
    // record gets.
    final detail = SessionDetailViewModel(userId: friend);
    await detail.load(seeded.completedId);
    addTearDown(detail.dispose);
    await waitFor(
      () => detail.state.value.pastSetsLoaded,
      reason: 'the heavy context (timeline, goals, notes)',
    );

    final state = detail.state.value;
    expect(state.isLoading, isFalse);
    expect(state.session?.sessionId, seeded.completedId);
    expect(state.exerciseSlots.map((s) => s.exerciseId), contains(squat));
    expect(state.totalPRCount, 1, reason: '100×5 opens the frontier');
    expect(
      state.prEventSetIds,
      contains(seeded.set.sessionExerciseSetId),
      reason: 'one PrEvent, drawn on its own set',
    );
    expect(
      state.goalSetIds,
      contains(seeded.set.sessionExerciseSetId),
      reason: '90×3 was met by the 100×5 set',
    );
    expect(
      state.notesByExercise[squat]?.single.text,
      'Chest up, sit back',
      reason: 'the friend\'s notes read under the friend\'s id',
    );
    expect(
      state.sessionTitle,
      'Freestyle Session',
      reason: 'the record had no plan, so the header says so',
    );
  });

  test('removing a friend cuts the local row and drops the cached timeline', () async {
    await seedUsers();
    await seedOwnFriendshipRow();
    await seedFriendHistory();
    PastSetsTimelineCache.instance.invalidate();

    final vm = FriendsViewModel(repo: friends, userId: me);
    vm.start();
    addTearDown(vm.dispose);
    await waitFor(
      () => vm.state.value.friends.length == 1,
      reason: 'the seeded row to arrive',
    );

    // Warm the friend's timeline cache — the viewer reads it while the
    // friendship exists.
    await PastSetsTimelineCache.instance.get(friend);
    expect(PastSetsTimelineCache.instance.asc(friend), isNotNull);

    final removed = await vm.remove(vm.state.value.friends.single);
    expect(removed, isTrue);
    expect(remote.removals, [friend]);

    await waitFor(
      () => vm.state.value.friends.isEmpty,
      reason: 'the list to empty at once',
    );
    final rows = await db.getAll(
      'SELECT 1 FROM friend_relationship WHERE user_id = ? AND friend_user_id = ?',
      [me, friend],
    );
    expect(rows, isEmpty);
    expect(
      PastSetsTimelineCache.instance.asc(friend),
      isNull,
      reason: 'nothing may serve the removed friend\'s rows between the cut '
          'and the next sync round',
    );
  });

  test('a nickname is the caller\'s own label: set, repaint, clear, capped',
      () async {
    await seedUsers();
    await seedOwnFriendshipRow();

    final vm = FriendsViewModel(repo: friends, userId: me);
    vm.start();
    addTearDown(vm.dispose);
    await waitFor(
      () => vm.state.value.friends.length == 1,
      reason: 'the seeded row',
    );
    expect(vm.state.value.friends.single.displayName, 'Jamie Rivera');

    expect(
      await vm.setNickname(vm.state.value.friends.single, 'Natasha'),
      isTrue,
    );
    await waitFor(
      () => vm.state.value.friends.single.displayName == 'Natasha',
      reason: 'the watch to repaint with the nickname',
    );
    final stored = await db.getAll(
      'SELECT nickname FROM friend_relationship '
      'WHERE user_id = ? AND friend_user_id = ?',
      [me, friend],
    );
    expect(stored.single['nickname'], 'Natasha');

    // Clearing falls back to the friend's own name.
    expect(await vm.setNickname(vm.state.value.friends.single, null), isTrue);
    await waitFor(
      () => vm.state.value.friends.single.displayName == 'Jamie Rivera',
      reason: 'the cleared nickname to fall back',
    );

    // The repository is the rail: twenty characters land, twenty-one are
    // refused before any write (the database's own rail is 120).
    await friends.setNickname(me, friend, 'a' * 20);
    await expectLater(
      friends.setNickname(me, friend, 'a' * 21),
      throwsArgumentError,
    );
  });

  test('a friend with no name reads as their code, then Friend', () async {
    // A friend whose dim_user row carries no name, and whose code has not
    // arrived yet.
    await db.execute(
      'INSERT INTO dim_user (id, user_id, user_name, user_lastname) '
      'VALUES (?, ?, NULL, NULL)',
      ['u3', 'u3'],
    );
    await db.execute(
      'INSERT INTO friend_relationship '
      '(id, user_id, friend_user_id, created_date) VALUES (?, ?, ?, ?)',
      ['$me-u3', me, 'u3', DateTime.now().toUtc().toIso8601String()],
    );

    final vm = FriendsViewModel(repo: friends, userId: me);
    vm.start();
    addTearDown(vm.dispose);
    await waitFor(
      () => vm.state.value.friends.length == 1,
      reason: 'the seeded row',
    );
    expect(
      vm.state.value.friends.single.displayName,
      'Friend',
      reason: 'no name and no code yet',
    );

    // The widened friends_data stream delivers a mutual friend's code; this
    // insert stands in for that download.
    await db.execute(
      'INSERT INTO dim_friend_code (id, user_id, friend_code, created_date) '
      'VALUES (?, ?, ?, ?)',
      ['u3', 'u3', 'WXYZ2345', DateTime.now().toUtc().toIso8601String()],
    );
    await waitFor(
      () => vm.state.value.friends.single.displayName == 'WXYZ-2345',
      reason: 'the code fallback',
    );
  });

  test('the list orders by the name it draws, so a nickname reorders it',
      () async {
    await seedUsers();
    await db.execute(
      'INSERT INTO dim_user (id, user_id, user_name, user_lastname) '
      'VALUES (?, ?, ?, ?)',
      ['u3', 'u3', 'Aaron', 'Stone'],
    );
    for (final other in [friend, 'u3']) {
      await db.execute(
        'INSERT INTO friend_relationship '
        '(id, user_id, friend_user_id, created_date) VALUES (?, ?, ?, ?)',
        ['$me-$other', me, other, DateTime.now().toUtc().toIso8601String()],
      );
    }

    final vm = FriendsViewModel(repo: friends, userId: me);
    vm.start();
    addTearDown(vm.dispose);
    await waitFor(
      () => vm.state.value.friends.length == 2,
      reason: 'both friends',
    );
    expect(
      vm.state.value.friends.map((f) => f.displayName),
      ['Aaron Stone', 'Jamie Rivera'],
    );

    // Renaming the first row to a name that sorts after the second flips the
    // order — proof the query orders by the label it draws.
    expect(
      await vm.setNickname(vm.state.value.friends.first, 'Zulu'),
      isTrue,
    );
    await waitFor(
      () => vm.state.value.friends
              .map((f) => f.displayName)
              .join('|') ==
          'Jamie Rivera|Zulu',
      reason: 'the nickname to reorder the list',
    );
  });
}

/// The RPC seam: the SQL side is server-side, so the test drives the client's
/// half with a fixed friend answer.
class _FakeFriendRemote implements FriendRemote {
  _FakeFriendRemote({required this.friendUserId});

  final String friendUserId;
  String? lastCode;
  final List<String> removals = [];

  @override
  Future<AddFriendResult> addByCode(String code) async {
    lastCode = code;
    return AddFriendResult(
      friend: Friend(
        userId: friendUserId,
        firstName: 'Jamie',
        lastName: 'Rivera',
      ),
      created: true,
    );
  }

  @override
  Future<void> remove(String friendUserId) async {
    removals.add(friendUserId);
  }
}
