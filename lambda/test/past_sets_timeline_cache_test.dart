import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/session_repository.dart';

/// The shared timeline cache's contract (2026-10-13): memoized per user
/// until invalidated, and — the guard this whole feature leans on — every
/// fact-writing method on [SessionRepository] invalidates, so a new write
/// path that forgets the call fails this suite instead of serving stale
/// history.
void main() {
  late int reads;

  setUp(() {
    reads = 0;
    PastSetsTimelineCache.loaderOverride = (userId) async {
      reads++;
      return [
        PastSetRow(
          sessionExerciseSetId: 's-$userId',
          sessionExerciseId: 'se1',
          sessionId: 'w1',
          userId: userId,
          exerciseId: 'ex1',
          setNumber: 1,
          reps: const [5],
          sessionCreatedDate: DateTime(2026, 10, 1),
        ),
      ];
    };
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  test('the first read queries, later reads ride the cache', () async {
    final first = await PastSetsTimelineCache.instance.get('u1');
    final second = await PastSetsTimelineCache.instance.get('u1');
    expect(identical(first, second), isTrue);
    expect(reads, 1, reason: 'one query for any number of reads');
  });

  test('invalidate makes the next read re-query', () async {
    await PastSetsTimelineCache.instance.get('u1');
    PastSetsTimelineCache.instance.invalidate();
    await PastSetsTimelineCache.instance.get('u1');
    expect(reads, 2);
  });

  test('each user has their own memoized read', () async {
    await PastSetsTimelineCache.instance.get('u1');
    await PastSetsTimelineCache.instance.get('u2');
    expect(reads, 2);
    await PastSetsTimelineCache.instance.get('u1');
    expect(reads, 2, reason: 'u1 still cached after u2 read');
  });

  test('the asc copy is the timeline in engine walk order', () async {
    PastSetsTimelineCache.loaderOverride = (userId) async => [
      PastSetRow(
        sessionExerciseSetId: 'newer',
        sessionExerciseId: 'se1',
        sessionId: 'w2',
        userId: userId,
        exerciseId: 'ex1',
        setNumber: 1,
        reps: const [5],
        sessionCreatedDate: DateTime(2026, 10, 2),
      ),
      PastSetRow(
        sessionExerciseSetId: 'older',
        sessionExerciseId: 'se1',
        sessionId: 'w1',
        userId: userId,
        exerciseId: 'ex1',
        setNumber: 1,
        reps: const [5],
        sessionCreatedDate: DateTime(2026, 10, 1),
      ),
    ];
    await PastSetsTimelineCache.instance.get('u3');
    final asc = PastSetsTimelineCache.instance.asc('u3')!;
    expect(
      asc.map((r) => r.sessionExerciseSetId).toList(),
      ['older', 'newer'],
    );
  });

  test('every fact-writing repo method invalidates the cache', () async {
    final repo = SessionRepository();
    // The invalidation runs at the top of each write method, before the
    // database call — the uninitialised PowerSync database in a host test
    // throws after it, which is fine: the counter is what is under test.
    Future<void> attempt(Future<void> Function() call) async {
      final before = PastSetsTimelineCache.instance.invalidations;
      try {
        await call();
      } catch (_) {}
      expect(PastSetsTimelineCache.instance.invalidations, greaterThan(before),
          reason: 'the write must invalidate the timeline cache');
    }

    await attempt(
      () => repo.createSession('u1'),
    );
    await attempt(() => repo.endSession('w1'));
    await attempt(() => repo.updatePostQuestionnaire('w1'));
    await attempt(() => repo.updateSessionNotes('w1'));
    await attempt(() => repo.reorderSessionExercises('w1', const []));
    await attempt(() => repo.insertSessionExercise(
          sessionId: 'w1',
          userId: 'u1',
          exerciseOrder: 1,
        ));
    await attempt(
      () => repo.updateSessionExercise('se1', exerciseId: 'ex2'),
    );
    await attempt(
      () => repo.updateSessionExercise('se1', clearExercise: true),
    );
    await attempt(() => repo.insertSet(
          sessionExerciseId: 'se1',
          sessionId: 'w1',
          userId: 'u1',
          setNumber: 1,
          reps: const [],
        ));
    await attempt(() => repo.updateSet('s1', weight: 5));
    await attempt(() => repo.deleteSet('s1'));
    await attempt(() => repo.deleteSessionExercise('se1'));
    await attempt(() => repo.reorderSets('w1', const []));
    await attempt(() => repo.deleteSession('w1'));
  });
}
