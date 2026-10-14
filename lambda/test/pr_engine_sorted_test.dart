import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/session/model/pr_engine.dart';

/// `prEventsSorted` is the engine's walk over history known to be
/// chronological — `prEvents` sorts then delegates, so the two must agree
/// byte-for-byte on every input (2026-10-13). Pinning the split protects the
/// live session's sorted-timeline fast path from drifting.
void main() {
  PastSetRow set({
    required String id,
    required String sessionId,
    required DateTime date,
    required int setNumber,
    double? weight,
    int reps = 0,
    String? exerciseId = 'bench',
    String? variationId,
  }) => PastSetRow(
    sessionExerciseSetId: id,
    sessionExerciseId: 'se-$id',
    sessionId: sessionId,
    userId: 'u1',
    exerciseId: exerciseId,
    variationId: variationId,
    setNumber: setNumber,
    weight: weight,
    reps: reps == 0 ? const [] : [reps],
    sessionCreatedDate: date,
  );

  bool sameEvents(List<PrEvent> a, List<PrEvent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.sessionExerciseSetId != y.sessionExerciseSetId ||
          x.exerciseId != y.exerciseId ||
          x.variationId != y.variationId ||
          x.weight != y.weight ||
          x.reps != y.reps ||
          x.beforeWeight != y.beforeWeight ||
          x.beforeReps != y.beforeReps ||
          x.sessionId != y.sessionId) {
        return false;
      }
    }
    return true;
  }

  test('sorted and unsorted inputs produce identical events', () {
    final base = DateTime(2026, 10, 1);
    final rows = <PastSetRow>[
      // Same-session tie-break: two sets in one workout.
      set(id: 'a', sessionId: 's1', date: base, setNumber: 2, weight: 100, reps: 5),
      set(id: 'b', sessionId: 's1', date: base, setNumber: 1, weight: 100, reps: 3),
      // An earlier session, heavier weight, fewer reps — the frontier pair.
      set(id: 'c', sessionId: 's0', date: base.subtract(const Duration(days: 1)), setNumber: 1, weight: 110, reps: 1),
      // Null variation is its own key — same exercise, separate pair.
      set(
        id: 'd',
        sessionId: 's0',
        date: base.subtract(const Duration(days: 1)),
        setNumber: 2,
        weight: 60,
        reps: 10,
        variationId: 'paused',
      ),
      // Dominated by the earlier 110×1 on the same pair — no event.
      set(
        id: 'e',
        sessionId: 's1',
        date: base,
        setNumber: 3,
        weight: 105,
        reps: 1,
      ),
    ];

    final shuffled = [...rows]..shuffle();
    final asc = [...rows]..sort((a, b) {
      final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
      return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
    });

    expect(sameEvents(prEvents(shuffled), prEventsSorted(asc)), isTrue,
        reason: 'the sorted fast path must walk exactly the engine\'s order');
  });

  test('a frontier extended mid-session still reads the before-facts', () {
    final base = DateTime(2026, 10, 2);
    final rows = [
      set(id: 'a', sessionId: 's1', date: base, setNumber: 1, weight: 100, reps: 5),
      set(id: 'b', sessionId: 's1', date: base, setNumber: 2, weight: 100, reps: 6),
    ];
    final asc = [...rows]..sort((a, b) => a.setNumber.compareTo(b.setNumber));

    final events = prEventsSorted(asc);
    expect(events.map((e) => e.sessionExerciseSetId), ['a', 'b']);
    expect(events.last.beforeReps, 5,
        reason: 'the second set beat the first at exactly 100kg');
  });
}
