import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/exercise_usage.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/session_exercise_set.dart';

/// Workout-recency ordering (2026-10-26): "most recently logged first, then
/// newest created" is the app's one template order — the library listing, the
/// Training selector and the review picker all speak it, and it derives from
/// the same timeline the exercise pickers already order by.
void main() {
  PastSetRow row({
    required String sessionId,
    String? plannedSessionId,
    required DateTime at,
  }) => PastSetRow(
    sessionExerciseSetId: 'set-$sessionId',
    sessionExerciseId: 'se-$sessionId',
    sessionId: sessionId,
    userId: 'u1',
    setNumber: 1,
    reps: const [5],
    sessionCreatedDate: at,
    plannedSessionId: plannedSessionId,
  );

  PlannedSession workout(String id, {DateTime? created}) =>
      PlannedSession(sessionId: id, userId: 'u1', name: id, createdDate: created);

  group('lastUsedByPlannedSession', () {
    test('the latest session per template wins; freestyle rows are skipped', () {
      final last = lastUsedByPlannedSession([
        row(
          sessionId: 's1',
          plannedSessionId: 't1',
          at: DateTime(2026, 10, 1),
        ),
        row(
          sessionId: 's2',
          plannedSessionId: 't1',
          at: DateTime(2026, 10, 9),
        ),
        row(sessionId: 's3', at: DateTime(2026, 10, 10)),
        row(
          sessionId: 's4',
          plannedSessionId: 't2',
          at: DateTime(2026, 10, 5),
        ),
      ]);

      expect(last['t1'], DateTime(2026, 10, 9));
      expect(last['t2'], DateTime(2026, 10, 5));
      expect(
        last,
        hasLength(2),
        reason: 'a freestyle session logs no template',
      );
    });
  });

  group('compareByLastLogged', () {
    final last = <String, DateTime>{'logged': DateTime(2026, 10, 1)};

    test('a logged workout outranks an unlogged one, however new it is', () {
      final logged = workout('logged', created: DateTime(2026, 1, 1));
      final fresh = workout('fresh', created: DateTime(2026, 10, 25));
      expect(compareByLastLogged(logged, fresh, last), lessThan(0));
      expect(compareByLastLogged(fresh, logged, last), greaterThan(0));
    });

    test('two logged workouts: the more recent session leads', () {
      final map = {
        'older': DateTime(2026, 10, 1),
        'newer': DateTime(2026, 10, 9),
      };
      expect(
        compareByLastLogged(workout('newer'), workout('older'), map),
        lessThan(0),
      );
    });

    test('two unlogged workouts: the newer template leads', () {
      final older = workout('a', created: DateTime(2026, 10, 1));
      final newer = workout('b', created: DateTime(2026, 10, 2));
      expect(compareByLastLogged(newer, older, last), lessThan(0));
    });

    test('a shared date falls back to the id — a full, deterministic order', () {
      final at = DateTime(2026, 10, 1);
      final a = workout('aaa', created: at);
      final b = workout('bbb', created: at);
      expect(compareByLastLogged(b, a, const {}), lessThan(0));
      expect(compareByLastLogged(a, b, const {}), greaterThan(0));
    });
  });

  test('sortByLastLogged sorts in place into that order', () {
    final map = {'t2': DateTime(2026, 10, 5)};
    final list = [
      workout('t1', created: DateTime(2026, 10, 20)), // newest, never logged
      workout('t2', created: DateTime(2026, 10, 1)), // logged
      workout('t3', created: DateTime(2026, 10, 10)), // never logged
    ];
    final sorted = sortByLastLogged(list, map);

    expect(sorted.map((w) => w.sessionId), ['t2', 't1', 't3']);
    expect(
      identical(sorted, list),
      isTrue,
      reason: 'the caller\'s list is the one ordered',
    );
  });
}
